import AppKit
import SwiftUI

struct ProjectNavigator: View {
    @ObservedObject var workspace: ProjectWorkspace
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let root = workspace.root { FileIcon(url: root, isDirectory: true, isExpanded: true, isRoot: true) }
                Text(workspace.root?.lastPathComponent ?? "").font(.headline).lineLimit(1)
                Spacer()
                Button { createFile() } label: {
                    Label("New file…", systemImage: "doc.badge.plus")
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
                Button { perform { try workspace.refresh() } } label: {
                    Label("Refresh files", systemImage: "arrow.clockwise")
                }.labelStyle(.iconOnly).buttonStyle(.borderless)
            }.padding(10)
            List {
                ForEach(workspace.files) { file in
                    ProjectFileRow(file: file, workspace: workspace)
                }
            }.listStyle(.sidebar)
            if let main = workspace.mainURL {
                Text("Main: \(workspace.relativePath(main))").font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).padding(8).help(workspace.relativePath(main))
            }
        }
    }
    private func createFile() {
        let panel = NSSavePanel()
        panel.directoryURL = workspace.root
        panel.nameFieldStringValue = "Untitled.typ"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            guard workspace.contains(url) else { throw ProjectFailure.outsideProject }
            try Data().write(to: url, options: .withoutOverwriting)
            try workspace.refresh()
            try workspace.open(url)
        }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { workspace.error = error.localizedDescription }
    }
}

private struct ProjectFileRow: View {
    let file: ProjectFile
    @ObservedObject var workspace: ProjectWorkspace
    @State private var expanded = false

    var body: some View {
        Group {
            if let children = file.children {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children) { child in
                        ProjectFileRow(file: child, workspace: workspace)
                    }
                } label: {
                    rowLabel
                }
            } else {
                Button {
                    do { try workspace.open(file.url) } catch { workspace.error = error.localizedDescription }
                } label: { rowLabel }
                    .buttonStyle(.plain)
            }
        }
        .help(workspace.relativePath(file.url))
        .contextMenu {
            if file.children == nil, file.url.pathExtension == "typ" {
                Button("Set as Main Document") {
                    do { try workspace.setMain(file.url) } catch { workspace.error = error.localizedDescription }
                }
            }
            Button("Rename or Move…") { moveItem() }
            Button("Move to Trash", role: .destructive) { trashItem() }
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }

    private var canManageItem: Bool {
        let open = NSDocumentController.shared.documents.contains { document in
            guard !(document is ProjectDocument), let url = document.fileURL?.standardizedFileURL.resolvingSymlinksInPath() else { return false }
            return url == file.url || url.path.hasPrefix(file.url.path + "/")
        }
        if open { workspace.error = String(localized: "Close standalone document windows for this item before moving or deleting it. Project tabs can remain open.") }
        return !open
    }

    private func moveItem() {
        guard canManageItem else { return }
        let panel = NSSavePanel()
        panel.directoryURL = file.url.deletingLastPathComponent()
        panel.nameFieldStringValue = file.url.lastPathComponent
        panel.prompt = String(localized: "Move")
        panel.message = String(localized: "Literal file references will be updated as unsaved edits. Review and save the project; computed paths may need manual changes.")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do { try workspace.move(file.url, to: destination) }
        catch { workspace.error = error.localizedDescription }
    }

    private func trashItem() {
        guard canManageItem else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Move to Trash") + ": " + file.url.lastPathComponent
        let dirty = workspace.buffers.contains { ($0.url == file.url || $0.url.path.hasPrefix(file.url.path + "/")) && $0.isDirty }
        alert.informativeText = dirty
            ? String(localized: "This item has unsaved edits. Save the project before moving it to Trash. References are not removed.")
            : String(localized: "You can restore this item from Trash. References are not removed.")
        alert.addButton(withTitle: dirty ? String(localized: "Save and Move to Trash") : String(localized: "Move to Trash"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            if dirty { try workspace.saveAll() }
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
            try workspace.forgetRemovedItem(file.url)
        } catch { workspace.error = error.localizedDescription }
    }

    private var rowLabel: some View {
        HStack(spacing: 6) {
            FileIcon(url: file.url, isDirectory: file.children != nil, isExpanded: expanded)
            Text(file.url.lastPathComponent).lineLimit(1)
            if file.url == workspace.mainURL {
                Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Main: \(file.url.lastPathComponent)"))
            }
        }.foregroundStyle(file.url == workspace.activeURL ? Color.accentColor : Color.primary)
    }
}

struct ProjectTabs: View {
    @ObservedObject var workspace: ProjectWorkspace
    let didClose: (URL) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 2) {
                ForEach(workspace.buffers) { buffer in
                    HStack(spacing: 6) {
                        Button { perform { try workspace.open(buffer.url) } } label: {
                            HStack(spacing: 4) {
                                FileIcon(url: buffer.url)
                                if buffer.isDirty { Image(systemName: "circle.fill").font(.system(size: 6)).accessibilityLabel("Unsaved changes") }
                                if buffer.url == workspace.mainURL { Image(systemName: "pin.fill") }
                                Text(buffer.url.lastPathComponent).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                        Button { close(buffer) } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                            .buttonStyle(.plain).disabled(buffer.url == workspace.mainURL)
                            .help(buffer.url == workspace.mainURL ? String(localized: "Choose another main document before closing this tab.") : String(localized: "Close tab"))
                            .accessibilityLabel(Text("Close \(buffer.url.lastPathComponent)"))
                    }.font(.caption).padding(8)
                        .background(buffer.url == workspace.activeURL ? Color.accentColor.opacity(0.12) : Color.clear)
                        .help(workspace.relativePath(buffer.url))
                }
            }
        }.frame(height: 32)
    }
    private func close(_ buffer: ProjectBuffer) {
        if buffer.isDirty {
            let alert = NSAlert()
            alert.messageText = String(localized: "Save changes to \(buffer.url.lastPathComponent)?")
            alert.addButton(withTitle: String(localized: "Save"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            alert.addButton(withTitle: String(localized: "Don’t Save"))
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                do { try workspace.save(buffer.url) } catch { workspace.error = error.localizedDescription; return }
            case .alertThirdButtonReturn: break
            default: return
            }
        }
        perform { try workspace.close(buffer.url); didClose(buffer.url) }
    }
    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { workspace.error = error.localizedDescription }
    }
}
