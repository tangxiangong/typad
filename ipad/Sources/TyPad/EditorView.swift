import SwiftUI
import UniformTypeIdentifiers

struct IPadEditorView: View {
    @Binding var document: TypstDocument
    let fileURL: URL?
    @ObservedObject var workspace: ProjectWorkspace = ProjectWorkspace()
    var projectAccessURL: URL? = nil
    @StateObject private var sessions = IPadEditorSessions()
    @Environment(\.openWindow) private var openWindow
    @StateObject private var preview = LocalPreviewModel()
    @State private var automatic = true
    @State private var showPreview = false
    @State private var showIssues = false
    @State private var exportPDF = false
    @State private var chooseFolder = false
    @State private var resourceFolder: URL?
    @State private var fileError: String?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if geometry.size.width >= 760 {
                    HStack(spacing: 0) {
                        sourceEditor
                        Divider()
                        previewPane
                    }
                } else {
                    Picker("View", selection: $showPreview) {
                        Text("Editor").tag(false)
                        Text("Preview").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    if showPreview { previewPane }
                    else { sourceEditor }
                }
                Divider()
                HStack {
                    if preview.isCompiling { ProgressView().controlSize(.small) }
                    Text(preview.status).font(.caption).lineLimit(2)
                    Spacer()
                    if preview.isStale, preview.pdf != nil {
                        Text("Preview is out of date").font(.caption).foregroundStyle(.secondary)
                    }
                    Button { showIssues = true } label: {
                        Label("\(preview.diagnostics.count)", systemImage: "exclamationmark.bubble")
                    }
                    .accessibilityLabel(Text("Diagnostics: \(preview.diagnostics.count)"))
                    .frame(minWidth: 44, minHeight: 44)
                }
                .padding(.horizontal)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { compile(immediate: true) } label: { Label("Compile", systemImage: "play") }
                    .keyboardShortcut("b", modifiers: .command)
                Menu {
                    let session = sessions.session(for: workspace.root == nil ? nil : fileURL)
                    let history = session.view?.undoManager
                    Button {
                        history?.undo()
                        if let view = session.view {
                            document.source = view.text
                            session.selection = view.selectedRange
                            session.offset = view.contentOffset
                        }
                        sessions.objectWillChange.send()
                    } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                        .disabled(history?.canUndo != true)
                    Button {
                        history?.redo()
                        if let view = session.view {
                            document.source = view.text
                            session.selection = view.selectedRange
                            session.offset = view.contentOffset
                        }
                        sessions.objectWillChange.send()
                    } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                        .disabled(history?.canRedo != true)
                    Divider()
                    Toggle("Live preview", isOn: $automatic)
                    if workspace.root == nil { Button { chooseFolder = true } label: { Label("Allow Resource Folder…", systemImage: "folder") } }
                    Button("Projects") { openWindow(id: "projects") }
                    Button { exportPDF = true } label: { Label("Export PDF…", systemImage: "square.and.arrow.up") }
                        .disabled(preview.pdf == nil || preview.isStale)
                } label: { Label("Document options", systemImage: "ellipsis.circle") }
            }
        }
        .onAppear { compile() }
        .onChange(of: document.source) { if workspace.root == nil { compile() } }
        .onChange(of: workspace.revision) { compile() }
        .onChange(of: workspace.buffers.map(\.url)) { sessions.retain(workspace.buffers.map(\.url)) }
        .onChange(of: fileURL) { if workspace.root == nil { resourceFolder = nil; compile() } }
        .onChange(of: automatic) { compile() }
        .onDisappear { preview.stop() }
        .sheet(isPresented: $showIssues) {
            NavigationStack {
                List {
                    if preview.diagnostics.isEmpty { Text("No diagnostics") }
                    ForEach(preview.diagnostics.indices, id: \.self) { index in
                        let issue = preview.diagnostics[index]
                        VStack(alignment: .leading, spacing: 4) {
                            Label(issue.message, systemImage: issue.warning ? "exclamationmark.triangle" : "xmark.circle")
                            if let line = issue.line { Text("Line \(line)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
                .navigationTitle("Diagnostics")
                .toolbar { Button("Done") { showIssues = false } }
            }
        }
        .fileImporter(isPresented: $chooseFolder, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url): resourceFolder = url; compile(immediate: true)
            case .failure(let error): fileError = error.localizedDescription
            }
        }
        .fileExporter(isPresented: $exportPDF, document: PDFExportDocument(data: preview.pdf ?? Data()),
                      contentType: .pdf, defaultFilename: (workspace.mainURL ?? fileURL)?.deletingPathExtension().lastPathComponent ?? "Untitled") { result in
            if case .failure(let error) = result { fileError = error.localizedDescription }
        }
        .alert("File operation failed", isPresented: Binding(get: { fileError != nil }, set: { if !$0 { fileError = nil } })) {
            Button("OK") { fileError = nil }
        } message: { Text(fileError ?? "") }
    }

    private var sourceEditor: some View {
        let key = workspace.root == nil ? nil : fileURL
        return IPadSourceEditor(source: $document.source, session: sessions.session(for: key)).id(key)
    }

    @ViewBuilder private var previewPane: some View {
        if let data = preview.pdf {
            IPadPDFPreview(data: data, revision: preview.previewRevision)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.richtext").font(.largeTitle).accessibilityHidden(true)
                Text("PDF Preview").font(.headline)
                Text(preview.status).foregroundStyle(.secondary)
                if !preview.diagnostics.isEmpty { Button("Show diagnostics") { showIssues = true } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func compile(immediate: Bool = false) {
        if workspace.root != nil, workspace.mainURL == nil {
            preview.waitForMainDocument()
            return
        }
        preview.update(source: workspace.main?.source ?? document.source, url: workspace.mainURL ?? fileURL,
                       resourceFolder: projectAccessURL ?? workspace.root ?? resourceFolder, automatic: automatic, immediate: immediate,
                       projectRoot: workspace.root, files: workspace.snapshots)
    }
}

private struct PDFExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
