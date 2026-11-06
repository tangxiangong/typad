import SwiftUI
import TyPadCore
import UniformTypeIdentifiers

private enum WorkspaceLayout: String, CaseIterable {
    case source = "Editor", split = "Editor and Preview", preview = "Preview"
    var icon: String {
        switch self { case .source: return "rectangle.lefthalf.filled"
        case .split: return "rectangle.split.2x1"
        case .preview: return "rectangle.righthalf.filled" }
    }
}

struct EditorView: View {
    @Binding var document: TypstDocument
    let fileURL: URL?
    @ObservedObject var workspace = ProjectWorkspace()
    @StateObject private var openSource = OpenSource()
    @StateObject private var sessions = SourceEditorSessions()
    @State private var showFiles = true
    @StateObject private var preview = PreviewModel()
    @StateObject private var language = LanguageModel()
    @State private var lineCount: UInt64 = 1
    @State private var headings: [DocumentHeading] = []
    @State private var automatic = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showIssues = false
    @State private var layout = WorkspaceLayout.split
    @State private var scale = PreviewScale.fit
    @State private var pages = PreviewPages.continuous
    @State private var pageInput = ""
    @State private var requestedPage: PDFPageRequest?
    @State private var selection: SourceSelection?
    @State private var selectionFile: URL?
    @State private var replacementFile: URL?
    @State private var cursor = 0
    @State private var conflict: ProjectConflict?
    @State private var secondaryURL: URL?
    @State private var replacement: SourceReplacement?
    @State private var showAssistance = false
    @State private var restoredState = false
    private var filename: String { fileURL?.lastPathComponent ?? String(localized: "Untitled.typ") }

    private var shell: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                if workspace.root != nil && showFiles {
                    ProjectNavigator(workspace: workspace)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
                } else {
                    WorkspaceSidebar(filename: filename, headings: headings, diagnostics: preview.diagnostics, issues: $showIssues,
                                     navigate: { offset in navigate(to: fileURL, offset: offset) },
                                     navigateIssue: navigateIssue)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
                }
            } detail: {
                HSplitView {
                    if layout != .preview {
                        HSplitView {
                            sourcePane
                            if let secondaryURL, workspace.buffers.contains(where: { $0.url == secondaryURL }) {
                                SecondaryEditor(workspace: workspace, url: secondaryURL) { self.secondaryURL = nil }
                                    .frame(minWidth: 240)
                            }
                        }.frame(minWidth: 280, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity)
                    }
                    if layout != .source { previewPane.frame(minWidth: 280, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
            .navigationSplitViewStyle(.balanced)
            Divider()
            statusBar
        }
        .frame(minWidth: 780, minHeight: 480)
        .background(WorkspaceRestoration(key: stateKey.map { $0 + ":" + layout.rawValue + ":" + String(secondaryURL != nil) }))
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if workspace.root != nil {
                    Button { tryAction { try workspace.goBack() } } label: { Label("Back", systemImage: "chevron.left") }
                        .disabled(!workspace.canGoBack)
                    Button { tryAction { try workspace.goForward() } } label: { Label("Forward", systemImage: "chevron.right") }
                        .disabled(!workspace.canGoForward)
                    Menu {
                        ForEach(workspace.buffers) { buffer in
                            Button(buffer.url.lastPathComponent) { secondaryURL = buffer.url; layout = .source }
                        }
                        Button("Close Split Editor") { secondaryURL = nil }.disabled(secondaryURL == nil)
                    } label: { Label("Split Editor", systemImage: "rectangle.split.2x1") }
                    if !workspace.conflicts.isEmpty {
                        Menu {
                            ForEach(workspace.conflicts.keys.sorted(by: { $0.path < $1.path }), id: \.self) { url in
                                Button(workspace.relativePath(url)) { conflict = workspace.conflictSnapshot(at: url) }
                            }
                        } label: { Label("Resolve external changes", systemImage: "exclamationmark.arrow.triangle.2.circlepath") }
                    }
                    Button { showFiles.toggle(); showIssues = false; columnVisibility = .all } label: {
                        Label(showFiles ? "Document outline" : "Project files", systemImage: showFiles ? "list.bullet.indent" : "folder")
                    }
                }
                Button { compile(immediate: true) } label: {
                    Label("Compile", systemImage: "gearshape.2")
                }.keyboardShortcut("b", modifiers: .command).help("Compile document (⌘B)")
                if preview.isCompiling {
                    Button { preview.cancel(); dismissAssistance() } label: { Label("Cancel Compilation", systemImage: "stop.circle") }
                }
                Menu {
                    Toggle("Live preview", isOn: $automatic)
                    Divider()
                    Text(preview.status)
                } label: {
                    Text(automatic ? String(localized: "Live") : String(localized: "Manual")).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(automatic ? Color.accentColor : Color.secondary)
                }.help("Preview updates")
                Button {
                    showFiles = false
                    showIssues = true
                    columnVisibility = .all
                } label: {
                    Label(preview.diagnostics.isEmpty ? String(localized: "No issues") : String(localized: "\(preview.diagnostics.count) issues"),
                          systemImage: preview.diagnostics.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                }
                .help(preview.diagnostics.isEmpty ? String(localized: "No compilation issues") : String(localized: "Show compilation issues"))
            }
            ToolbarItem(placement: .primaryAction) {
                Picker("Workspace layout", selection: $layout) {
                    ForEach(WorkspaceLayout.allCases, id: \.self) { value in
                        Image(systemName: value.icon).tag(value).help(LocalizedStringKey(value.rawValue)).accessibilityLabel(LocalizedStringKey(value.rawValue))
                    }
                }.pickerStyle(.segmented).frame(width: 112).help("Editor · Split · Preview")
            }
        }
    }

    private var observedContent: some View {
        shell
        .onAppear { restoreState(); joinOpenSources(); preview.worker.reopen(); compile(); applyPendingNavigation() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in applyPendingNavigation() }
        .sheet(item: $conflict) { snapshot in
            ConflictView(workspace: workspace, snapshot: snapshot)
        }
        .task(id: workspace.root) {
            guard workspace.root != nil else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                do { try await workspace.refreshExternalChanges() }
                catch { workspace.error = error.localizedDescription }
            }
        }
        .onChange(of: document.source) { old, new in
            openSource.source = new
            if workspace.root == nil, let fileURL {
                ProjectEdits.changes.send(ProjectEdits.Change(url: fileURL.standardizedFileURL.resolvingSymlinksInPath(), before: old, after: new))
            }
            dismissAssistance(); compile()
        }
        .onReceive(ProjectEdits.changes) { change in
            guard workspace.root == nil, let url = fileURL?.standardizedFileURL.resolvingSymlinksInPath() else { return }
            guard url == change.url else {
                if change.url.path.hasPrefix(url.deletingLastPathComponent().path + "/") { compile() }
                return
            }
            guard document.source != change.after else { return }
            guard document.source == change.before else {
                workspace.error = String(localized: "Another window has different edits for this file. Your local edits have been kept.")
                return
            }
            document.source = change.after
        }
        .onChange(of: fileURL) {
            joinOpenSources(); dismissAssistance(); replacement = nil; cursor = 0
            if selectionFile != fileURL { selection = nil }
            compile()
        }
        .onChange(of: workspace.revision) { compile() }
        .alert(workspace.error == nil ? String(localized: "Recovered edits") : String(localized: "Project error"),
               isPresented: Binding(get: { workspace.error != nil || workspace.recoveredEdits }, set: {
                   if !$0 { workspace.error = nil; workspace.recoveredEdits = false }
               })) {
            Button("OK") { workspace.error = nil; workspace.recoveredEdits = false }
        } message: { Text(workspace.error ?? String(localized: "Recovered unsaved project edits. Review them before saving.")) }
    }

    var body: some View {
        observedContent
        .onChange(of: cursor) { dismissAssistance() }
        .onChange(of: layout) { dismissAssistance() }
        .onChange(of: automatic) { compile() }
        .onDisappear { saveState(); sessions.captureAll(); leaveOpenSources(); dismissAssistance(); preview.stop() }
        .onChange(of: layout) { saveState() }
        .onChange(of: scale) { saveState() }
        .onChange(of: pages) { saveState() }
        .onChange(of: showFiles) { saveState() }
        .onChange(of: showIssues) { saveState() }
        .onChange(of: automatic) { saveState() }
        .onChange(of: secondaryURL) { saveState() }
        .onChange(of: columnVisibility) { saveState() }
        .task(id: document.source) { await updateOutline() }
    }

    private func updateOutline() async {
        let source = document.source
        do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
        let result: (UInt64, [DocumentHeading]) = await Task.detached(priority: .utility) {
            let count = TyPadCore.summarizeSource(source: source).lineCount
            let outline = DocumentHeading.scan(source)
            return (count, outline)
        }.value
        guard !Task.isCancelled else { return }
        lineCount = result.0
        headings = result.1
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            if workspace.root != nil {
                ProjectTabs(workspace: workspace) { sessions.remove($0) }
                Divider()
            }
            HStack(spacing: 8) {
                FileIcon(url: fileURL ?? URL(fileURLWithPath: "Untitled.typ"))
                Text(verbatim: filename).lineLimit(1).truncationMode(.middle)
                Spacer()
                Menu {
                    Button("Complete") { query("complete", offset: cursor) }.keyboardShortcut(" ", modifiers: .control)
                    Button("Quick Help") { query("hover", offset: cursor) }.keyboardShortcut("i", modifiers: [.option, .command])
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().help("Editing assistance")
            }
            .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 28)
            .background(.bar).zIndex(1)
            Divider()
            if let url = fileURL, let message = workspace.unavailableFiles[url] {
                VStack(alignment: .leading, spacing: 6) {
                    Label("File unavailable on disk — buffer retained", systemImage: "exclamationmark.triangle")
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    if !FileManager.default.fileExists(atPath: url.path) {
                        Button("Restore Missing File") { tryAction { try workspace.restoreMissingFile(url) } }
                    }
                }.font(.callout).padding(10)
                Divider()
            }
            if workspace.root == nil || workspace.activeURL != nil {
                nativeEditor
            } else {
                Text("Choose a file in the project navigator").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var nativeEditor: some View {
        let activeSelection: SourceSelection? = selectionFile == fileURL ? selection : nil
        let activeReplacement: SourceReplacement? = replacementFile == fileURL ? replacement : nil
        let session: SourceEditorSession? = fileURL.map { sessions.session(for: $0) }
        return SourceEditor(text: $document.source, selection: activeSelection, cursor: $cursor,
                            replacement: activeReplacement, language: language, assistanceVisible: $showAssistance,
                            requestCompletion: { query("complete", offset: $0) }, acceptCompletion: acceptCompletion,
                            session: session).id(workspace.root == nil ? nil : fileURL).clipped()
    }
    private func acceptCompletion(_ item: WorkerCompletion) {
        replacementFile = fileURL
        replacement = SourceReplacement(source: language.source, edits: item.edits)
        showAssistance = false
    }

    private var previewPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext").foregroundStyle(.secondary)
                Text("PDF")
                Spacer()
                if preview.pdf != nil {
                    Text("\(preview.pageCount) pages").foregroundStyle(.secondary)
                }
                Button("Export PDF…", systemImage: "square.and.arrow.up") { exportPDF() }
                    .labelStyle(.iconOnly).help("Export current PDF")
                    .disabled(!preview.canExport)
                Menu {
                    Picker("Zoom", selection: $scale) {
                        ForEach(PreviewScale.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    Divider()
                    Picker("Page Layout", selection: $pages) {
                        ForEach(PreviewPages.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                } label: { Label("Zoom and page layout", systemImage: "book") }.labelStyle(.iconOnly)
                    .menuStyle(.borderlessButton).fixedSize()
                TextField("Page", text: $pageInput).frame(width: 44)
                    .onSubmit { goToPage() }
                    .help("Enter a page number")
                Button(action: goToPage) { Label("Go to Page", systemImage: "arrow.right.circle") }
                    .labelStyle(.iconOnly).help("Go to Page")
                    .disabled(pageNumber == nil)
            }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 28)
            Divider()
            if let pdf = preview.pdf {
                PDFPreview(data: pdf, revision: preview.previewRevision, scale: scale, pages: pages,
                           requestedPage: $requestedPage, storageKey: (workspace.root ?? fileURL).map { "pdfPosition:" + $0.path })
                    .overlay(alignment: .top) {
                        if preview.isStale {
                            Label("Previous preview", systemImage: "clock")
                                .font(.caption).padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.regularMaterial, in: Capsule()).padding(10)
                                .allowsHitTesting(false)
                        }
                    }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.richtext").font(.system(size: 38, weight: .ultraLight))
                    Text(preview.diagnostics.isEmpty ? String(localized: "Ready when you are") : String(localized: "The preview needs a correction"))
                        .font(.system(size: 15, weight: .medium))
                    Text(preview.diagnostics.isEmpty ? String(localized: "Write on the left. Your pages appear here.") : String(localized: "Choose an issue in the navigator to locate it."))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Compile document") { compile(immediate: true) }.controlSize(.small).padding(.top, 4)
                }.foregroundStyle(.secondary).padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .underPageBackgroundColor))
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(lineCount) lines")
            Text("Typst").foregroundStyle(.tertiary)
            Spacer(minLength: 20)
            if preview.isCompiling { ProgressView().controlSize(.mini) }
            Text(preview.status).lineLimit(1).truncationMode(.middle).help(preview.status)
        }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 12).frame(height: 26)
    }

    private func leaveOpenSources() {
        guard let url = openSource.url else { return }
        openSource.url = nil
        ProjectEdits.changes.send(ProjectEdits.Change(url: url, before: openSource.source, after: openSource.source))
    }

    private func joinOpenSources() {
        guard workspace.root == nil, let url = fileURL?.standardizedFileURL.resolvingSymlinksInPath() else { return }
        if openSource.url != url, let shared = ProjectEdits.source(for: url),
           let data = try? Data(contentsOf: url), let disk = String(data: data, encoding: .utf8), document.source == disk {
            document.source = shared
        }
        openSource.url = url
        openSource.source = document.source
        ProjectEdits.register(openSource)
    }

    private var stateKey: String? { (workspace.root ?? fileURL).map { "workspaceState:" + $0.path } }
    private func saveState() {
        guard restoredState, let key = stateKey else { return }
        UserDefaults.standard.set([
            "layout": layout.rawValue, "scale": scale.rawValue, "pages": pages.rawValue, "files": showFiles,
            "issues": showIssues, "automatic": automatic, "secondary": secondaryURL?.path ?? "",
            "sidebar": columnVisibility != .detailOnly
        ], forKey: key)
    }
    private func restoreState() {
        guard !restoredState else { return }
        restoredState = true
        guard let key = stateKey, let state = UserDefaults.standard.dictionary(forKey: key) else { return }
        layout = WorkspaceLayout(rawValue: state["layout"] as? String ?? "") ?? .split
        scale = PreviewScale(rawValue: state["scale"] as? String ?? "") ?? .fit
        pages = PreviewPages(rawValue: state["pages"] as? String ?? "") ?? .continuous
        showFiles = state["files"] as? Bool ?? true
        showIssues = state["issues"] as? Bool ?? false
        automatic = state["automatic"] as? Bool ?? true
        columnVisibility = state["sidebar"] as? Bool == false ? .detailOnly : .all
        if let path = state["secondary"] as? String, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if workspace.buffers.contains(where: { $0.url == url }) { secondaryURL = url }
        }
    }

    private func tryAction(_ action: () throws -> Void) {
        do { try action() } catch { workspace.error = error.localizedDescription }
    }

    private func navigate(to url: URL?, offset: Int) {
        if layout == .preview { layout = .split }
        if let url, workspace.root != nil {
            do { try workspace.open(url) } catch { workspace.error = error.localizedDescription; return }
        }
        selectionFile = url
        selection = SourceSelection(offset: offset)
    }

    private func applyPendingNavigation() {
        guard workspace.root == nil, let url = fileURL?.standardizedFileURL.resolvingSymlinksInPath(),
              let offset = DiagnosticNavigation.pending.removeValue(forKey: url) else { return }
        navigate(to: fileURL, offset: offset)
    }

    private func navigateIssue(_ issue: WorkerDiagnostic) {
        guard let offset = issue.utf16Offset, offset <= UInt64(Int.max) else { return }
        if workspace.root == nil && fileURL == nil { navigate(to: nil, offset: Int(offset)); return }
        let root = workspace.root ?? fileURL?.deletingLastPathComponent()
        let target = issue.destination(root: root, main: workspace.mainURL ?? fileURL)
        guard target != nil else { return }
        if workspace.root != nil || target == fileURL?.standardizedFileURL.resolvingSymlinksInPath() {
            navigate(to: workspace.root == nil ? fileURL : target, offset: Int(offset))
        } else if let target, let root, target.path.hasPrefix(root.path + "/") {
            DiagnosticNavigation.pending[target] = Int(offset)
            NSDocumentController.shared.openDocument(withContentsOf: target, display: true) { _, _, error in
                if let error { DispatchQueue.main.async { NSApp.presentError(error) } }
            }
        }
    }

    private var pageNumber: Int? {
        guard let page = Int(pageInput.trimmingCharacters(in: .whitespaces)),
              page > 0, page <= Int(preview.pageCount), preview.pdf != nil else { return nil }
        return page
    }
    private func goToPage() {
        if let page = pageNumber { requestedPage = PDFPageRequest(page: page) }
    }

    private func exportPDF() {
        guard preview.canExport else { return }
        let revision = preview.revision
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = (workspace.mainURL ?? fileURL)?.deletingPathExtension().lastPathComponent.appending(".pdf") ?? "Untitled.pdf"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try preview.exportPDF(to: url, expectedRevision: revision) }
        catch { workspace.error = error.localizedDescription }
    }

    private func query(_ operation: String, offset: Int) {
        showAssistance = true
        language.query(operation, source: document.source, path: fileURL?.path,
                       offset: offset, revision: preview.revision, worker: preview.worker,
                       root: workspace.root?.path, files: workspace.snapshots)
    }
    private func dismissAssistance() { showAssistance = false; language.invalidate() }
    private func compile(immediate: Bool = false) {
        if workspace.root != nil {
            guard let main = workspace.main else { preview.invalidate(); return }
            preview.update(source: main.source, url: main.url, automatic: automatic, immediate: immediate,
                           root: workspace.root?.path, files: workspace.snapshots)
        } else {
            let root = fileURL?.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            preview.update(source: document.source, url: fileURL, automatic: automatic, immediate: immediate,
                           root: root?.path, files: root.map { ProjectEdits.snapshots(in: $0) } ?? [:])
        }
    }
}
