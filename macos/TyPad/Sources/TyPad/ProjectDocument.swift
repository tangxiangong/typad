import AppKit
import SwiftUI

/// NSDocument supplies Save, window-close and application-quit confirmation for project buffers.
@MainActor
final class ProjectDocument: NSDocument {
    let workspace: ProjectWorkspace

    init(root: URL) throws {
        workspace = try ProjectWorkspace(root: root)
        super.init()
        fileURL = workspace.root
        fileType = "org.typad.project"
        workspace.didEdit = { [weak self] in
            guard let self else { return }
            self.updateChangeCount(self.workspace.isDirty ? .changeDone : .changeCleared)
        }
        if workspace.isDirty { updateChangeCount(.changeDone) }
    }

    override var isDocumentEdited: Bool { workspace.isDirty }
    override class var autosavesInPlace: Bool { false }
    override class var autosavesDrafts: Bool { false }
    override class var preservesVersions: Bool { false }
    override class var writableTypes: [String] { ["org.typad.project"] }
    override class func isNativeType(_ type: String) -> Bool { type == "org.typad.project" }
    override func canAsynchronouslyWrite(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) -> Bool { false }

    override func makeWindowControllers() {
        let controller = NSHostingController(rootView: ProjectEditorView(workspace: workspace))
        let window = NSWindow(contentViewController: controller)
        window.setContentSize(NSSize(width: 1180, height: 740))
        window.styleMask.insert([.resizable, .miniaturizable])
        window.title = workspace.root?.lastPathComponent ?? "TyPad"
        window.center()
        addWindowController(NSWindowController(window: window))
    }

    override func write(to url: URL, ofType typeName: String) throws {
        if Thread.isMainThread {
            try MainActor.assumeIsolated { try saveProject(to: url) }
        } else {
            try DispatchQueue.main.sync { try self.saveProject(to: url) }
        }
    }

    private func saveProject(to url: URL) throws {
        guard url.standardizedFileURL.resolvingSymlinksInPath() == workspace.root else {
            throw ProjectFailure.outsideProject
        }
        try workspace.saveAll()
    }

    // NSDocument's default safe-write algorithm replaces the destination. A folder project
    // instead atomically saves each edited file, preserving every unrelated resource.
    override func writeSafely(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType) throws {
        try write(to: url, ofType: typeName)
    }

    override func close() {
        do { try workspace.clearRecovery() } catch { presentError(error) }
        super.close()
    }

    override func saveAs(_ sender: Any?) { saveCopy() }
    override func duplicate(_ sender: Any?) { saveCopy() }

    private func saveCopy() {
        guard let buffer = workspace.active else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = buffer.url.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard !workspace.contains(url) else { throw ProjectFailure.externalChange(url.lastPathComponent) }
            try buffer.data.write(to: url, options: .atomic)
        } catch { presentError(error) }
    }

    static func createFolder() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Untitled Project"
        panel.prompt = String(localized: "Create Project")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard !FileManager.default.fileExists(atPath: url.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("= New document\n\n".utf8).write(to: url.appendingPathComponent("main.typ"), options: .withoutOverwriting)
            openFolder(url)
        } catch { NSApp.presentError(error) }
    }

    static func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Open")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFolder(url)
    }

    static var recentFolders: [URL] {
        (UserDefaults.standard.stringArray(forKey: "recentProjectFolders") ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func openFolder(_ url: URL) {
        let root = url.standardizedFileURL.resolvingSymlinksInPath()
        if let existing = NSDocumentController.shared.documents.compactMap({ $0 as? ProjectDocument })
            .first(where: { $0.workspace.root == root }) {
            existing.showWindows()
            return
        }
        do {
            let document = try ProjectDocument(root: root)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()
            let recent = [root.path] + recentFolders.map(\.path).filter { $0 != root.path }
            UserDefaults.standard.set(Array(recent.prefix(20)), forKey: "recentProjectFolders")
        } catch { NSApp.presentError(error) }
    }
}

private struct ProjectEditorView: View {
    @ObservedObject var workspace: ProjectWorkspace
    var body: some View {
        // An outgoing editor must keep reading/writing its own buffer during a tab transition.
        let url = workspace.activeURL
        EditorView(document: Binding(get: {
            var document = TypstDocument()
            document.source = workspace.buffers.first { $0.url == url }?.source ?? ""
            return document
        }, set: { value in
            if let url { workspace.edit(value.source, at: url) }
        }), fileURL: url, workspace: workspace)
    }
}
