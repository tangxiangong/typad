import SwiftUI
import UniformTypeIdentifiers

/// Owns the Files permission for the entire workspace lifetime, including async compilation.
@MainActor
final class IPadProjectSession: ObservableObject, Identifiable {
    let id = UUID()
    let workspace: ProjectWorkspace
    let accessURL: URL
    private let hasAccess: Bool
    init(url: URL, accessURL: URL? = nil, legacyRoots: [URL] = []) async throws {
        self.accessURL = accessURL ?? url
        hasAccess = self.accessURL.startAccessingSecurityScopedResource()
        do { workspace = try await ProjectWorkspace.loadAsync(root: url, legacyRoots: legacyRoots) }
        catch {
            if hasAccess { self.accessURL.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    deinit { if hasAccess { accessURL.stopAccessingSecurityScopedResource() } }
}

struct IPadProjectsView: View {
    @State private var loading = false
    @State private var session: IPadProjectSession?
    @State private var chooseFolder = false
    @State private var creating = false
    @State private var name = "Untitled"
    @State private var namePrompt = false
    @State private var error: String?
    @AppStorage("ipad.recentProjects") private var recentData = Data()

    private struct Recent: Codable, Identifiable, Sendable {
        var id: String { path }
        let path: String
        let name: String
        let bookmark: Data
        let relativePath: String?
        var legacyPaths: [String]?
    }
    private var recent: [Recent] { (try? JSONDecoder().decode([Recent].self, from: recentData)) ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Button("Open Project…") { creating = false; chooseFolder = true }
                Button("New Project…") { namePrompt = true }
                Section("Recent Projects") {
                    ForEach(recent) { item in
                        Button(item.name) {
                            Task { @MainActor in
                                loading = true
                                defer { loading = false }
                                do {
                                    var stale = false
                                    let url = try URL(resolvingBookmarkData: item.bookmark, options: [], bookmarkDataIsStale: &stale)
                                    try await open(item.relativePath.map { url.appendingPathComponent($0, isDirectory: true) } ?? url, accessURL: url)
                                } catch { self.error = error.localizedDescription }
                            }
                        }
                    }
                }
            }
            .task { await normalizeRecent() }
            .disabled(loading)
            .overlay { if loading { ProgressView() } }
            .navigationTitle("Projects")
            .alert("New Project…", isPresented: $namePrompt) {
                TextField("Name", text: $name)
                Button("Choose Parent Folder…") { creating = true; chooseFolder = true }
                    .disabled(!validName(name))
                Button("Cancel", role: .cancel) {}
            }
            .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
                Task { @MainActor in
                    loading = true
                    defer { loading = false }
                    do {
                        let parent = try result.get()
                        let access = parent.startAccessingSecurityScopedResource()
                        defer { if access { parent.stopAccessingSecurityScopedResource() } }
                        var url = parent
                        if creating {
                            guard validName(name) else { throw CocoaError(.fileWriteInvalidFileName) }
                            let projectName = name
                            url = try await ProjectFileAccess.writeAsync(parent) { coordinatedParent in
                                let destination = coordinatedParent.appendingPathComponent(projectName, isDirectory: true)
                                guard !FileManager.default.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists) }
                                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
                                try Data("= Untitled\n".utf8).write(to: destination.appendingPathComponent("main.typ"), options: .withoutOverwriting)
                                return destination
                            }
                        }
                        try await open(url, accessURL: parent)
                    } catch { self.error = error.localizedDescription }
                }
            }
            .fullScreenCover(item: $session) { session in
                IPadProjectView(session: session) { self.session = nil }
            }
            .alert("File operation failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private func normalizeRecent() async {
        let original = recentData
        let items = recent
        let normalized = await Task.detached {
            var result: [Recent] = []
            for item in items {
                do {
                    var stale = false
                    let grant = try URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale)
                    let url = item.relativePath.map { grant.appendingPathComponent($0, isDirectory: true) } ?? grant
                    let identity = ProjectLocation.identity(for: url)
                    let oldPaths = (item.legacyPaths ?? []) + (item.path.hasPrefix("/") ? [item.path] : [])
                    if let index = result.firstIndex(where: { $0.path == identity }) {
                        result[index].legacyPaths = Array(Set((result[index].legacyPaths ?? []) + oldPaths))
                    } else {
                        result.append(Recent(path: identity, name: item.name, bookmark: item.bookmark,
                                             relativePath: item.relativePath, legacyPaths: Array(Set(oldPaths))))
                    }
                } catch { result.append(item) }
            }
            return result
        }.value
        if recentData == original, let data = try? JSONEncoder().encode(normalized) { recentData = data }
    }

    private func validName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name != "." && name != ".." && !name.contains("/")
    }

    private func open(_ url: URL, accessURL: URL? = nil) async throws {
        let grant = accessURL ?? url
        await normalizeRecent()
        let identity = ProjectLocation.identity(for: url)
        let legacyPaths = recent.filter { $0.path == identity }.flatMap { $0.legacyPaths ?? [] }
        let newSession = try await IPadProjectSession(url: url, accessURL: grant,
            legacyRoots: legacyPaths.map { URL(fileURLWithPath: $0, isDirectory: true) })
        let bookmark = try grant.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        let item = Recent(path: identity, name: url.lastPathComponent, bookmark: bookmark,
                          relativePath: grant.standardizedFileURL == url.standardizedFileURL ? nil : url.lastPathComponent, legacyPaths: legacyPaths)
        recentData = try JSONEncoder().encode(Array(([item] + recent.filter { $0.path != item.path }).prefix(12)))
        session = newSession
    }
}

struct IPadProjectView: View {
    let session: IPadProjectSession
    @ObservedObject private var workspace: ProjectWorkspace
    let dismiss: () -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var discarded = false
    @State private var closingProject = false
    @State private var closingTab: URL?
    @State private var confirmClose = false
    @State private var newFile = false
    @State private var filename = "Untitled.typ"
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    init(session: IPadProjectSession, dismiss: @escaping () -> Void) {
        self.session = session
        workspace = session.workspace
        self.dismiss = dismiss
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List {
                ForEach(workspace.files) { file in IPadProjectFileRow(file: file, workspace: workspace) }
            }
            .navigationTitle(workspace.root?.lastPathComponent ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close Project") { closingProject = true; requestClose() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { newFile = true } label: { Label("New file…", systemImage: "doc.badge.plus") }
                    Button { perform { try await workspace.refreshAsync() } } label: { Label("Refresh files", systemImage: "arrow.clockwise") }
                }
            }
        } detail: {
            VStack(spacing: 0) {
                tabs
                Divider()
                if let url = workspace.activeURL {
                    IPadEditorView(document: Binding(get: {
                        var document = TypstDocument()
                        document.source = workspace.buffers.first { $0.url == url }?.source ?? ""
                        return document
                    }, set: { workspace.edit($0.source, at: url) }), fileURL: url, workspace: workspace, projectAccessURL: session.accessURL)
                } else { ContentUnavailableView("Open a file", systemImage: "doc.text") }
            }
            .navigationTitle(workspace.root?.lastPathComponent ?? "Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Close Project") { closingProject = true; requestClose() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Save All") { perform { try await workspace.saveAllAsync() } }.disabled(!workspace.isDirty)
                    if let url = workspace.activeURL, url.pathExtension == "typ" {
                        Button("Set as Main Document") { perform { try await workspace.setMainAsync(url) } }
                            .disabled(url == workspace.mainURL)
                    }
                }
            }
        }
        .disabled(workspace.isBusy)
        .overlay { if workspace.isBusy { ProgressView() } }
        .interactiveDismissDisabled()
        .onChange(of: scenePhase) { if !discarded, scenePhase != .active { persistRecovery() } }
        .onDisappear { if !discarded { persistRecovery() } }
        .alert("New file…", isPresented: $newFile) {
            TextField("Name", text: $filename)
            Button("Create") {
                perform {
                    guard let root = workspace.root, !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else {
                        throw CocoaError(.fileWriteInvalidFileName)
                    }
                    let url = root.appendingPathComponent(filename)
                    guard workspace.contains(url) else { throw ProjectFailure.outsideProject }
                    let name = filename
                    try await ProjectFileAccess.writeAsync(root) { coordinatedRoot in
                        let destination = coordinatedRoot.appendingPathComponent(name)
                        guard coordinatedRoot.standardizedFileURL == root.standardizedFileURL else { throw ProjectFailure.outsideProject }
                        try Data().write(to: destination, options: .withoutOverwriting)
                    }
                    try await workspace.refreshAsync()
                    try await workspace.openAsync(url)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Save changes before closing?", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("Save") { perform {
                if closingProject { try await workspace.saveAllAsync() }
                else if let closingTab { try await workspace.saveAsync(closingTab) }
                try await finishClose()
            } }
            Button("Discard Changes", role: .destructive) { perform {
                if closingProject { try workspace.clearRecovery(); discarded = true; dismiss() }
                else { try await finishClose() }
            } }
            Button("Cancel", role: .cancel) { closingTab = nil; closingProject = false }
        }
        .alert(workspace.error == nil ? String(localized: "Recovered edits") : String(localized: "File operation failed"),
               isPresented: Binding(get: { workspace.error != nil || workspace.recoveredEdits }, set: {
                   if !$0 { workspace.error = nil; workspace.recoveredEdits = false }
               })) {
            Button("OK") { workspace.error = nil; workspace.recoveredEdits = false }
        } message: { Text(workspace.error ?? String(localized: "Recovered unsaved project edits. Review them before saving.")) }
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(workspace.buffers) { buffer in
                    HStack(spacing: 4) {
                        Button { perform { try await workspace.openAsync(buffer.url) } } label: {
                            HStack {
                                FileIcon(url: buffer.url)
                                Text(buffer.url.lastPathComponent)
                                if buffer.isDirty { Image(systemName: "circle.fill").font(.system(size: 6)).accessibilityLabel("Unsaved changes") }
                                if buffer.url == workspace.mainURL { Image(systemName: "pin.fill") }
                            }.padding(.vertical, 12)
                        }
                        if buffer.url != workspace.mainURL {
                            Button { closingProject = false; closingTab = buffer.url; requestClose() } label: {
                                Image(systemName: "xmark").frame(width: 44, height: 44)
                            }.accessibilityLabel("Close tab")
                        }
                    }
                    .padding(.horizontal, 8)
                    .background(buffer.url == workspace.activeURL ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                }
            }.padding(.horizontal, 8).padding(.vertical, 4)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(uiColor: .systemBackground))
        .clipped()
    }

    private func persistRecovery() {
        do { try workspace.persistRecovery() } catch { workspace.error = error.localizedDescription }
    }

    private func requestClose() {
        let dirty = closingProject ? workspace.isDirty : workspace.buffers.first { $0.url == closingTab }?.isDirty == true
        if dirty { confirmClose = true } else { perform { try await finishClose() } }
    }
    private func finishClose() async throws {
        if closingProject { try await workspace.persistConfigurationAsync(); dismiss() }
        else if let closingTab { try await workspace.closeAsync(closingTab) }
        closingTab = nil
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !workspace.isBusy else { return }
        workspace.isBusy = true
        Task { @MainActor in
            defer { workspace.isBusy = false }
            do { try await action() } catch { workspace.error = error.localizedDescription }
        }
    }
}

private struct IPadProjectFileRow: View {
    let file: ProjectFile
    @ObservedObject var workspace: ProjectWorkspace
    @State private var expanded = false
    var body: some View {
        Group {
            if let children = file.children {
                DisclosureGroup(isExpanded: $expanded) {
                    ForEach(children) { IPadProjectFileRow(file: $0, workspace: workspace) }
                } label: { label }
            } else {
                Button { perform { try await workspace.openAsync(file.url) } } label: { label }
                    .contextMenu {
                        if file.url.pathExtension == "typ" {
                            Button("Set as Main Document") { perform { try await workspace.setMainAsync(file.url) } }
                        }
                    }
            }
        }
    }
    private var label: some View {
        HStack {
            FileIcon(url: file.url, isDirectory: file.children != nil, isExpanded: expanded)
            Text(file.url.lastPathComponent).lineLimit(1)
            if file.url == workspace.mainURL { Image(systemName: "pin.fill").font(.caption) }
        }.foregroundStyle(file.url == workspace.activeURL ? Color.accentColor : Color.primary)
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !workspace.isBusy else { return }
        workspace.isBusy = true
        Task { @MainActor in
            defer { workspace.isBusy = false }
            do { try await action() } catch { workspace.error = error.localizedDescription }
        }
    }
}
