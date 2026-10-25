import SwiftUI
import TyPadCore

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
    @StateObject private var preview = PreviewModel()
    @StateObject private var language = LanguageModel()
    @State private var lineCount: UInt64 = 1
    @State private var headings: [DocumentHeading] = []
    @State private var automatic = true
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showIssues = false
    @State private var layout = WorkspaceLayout.split
    @State private var scale = PreviewScale.fit
    @State private var selection: SourceSelection?
    @State private var cursor = 0
    @State private var replacement: SourceReplacement?
    @State private var showAssistance = false
    private var filename: String { fileURL?.lastPathComponent ?? String(localized: "Untitled.typ") }

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                WorkspaceSidebar(filename: filename, headings: headings, diagnostics: preview.diagnostics, issues: $showIssues) { offset in
                    if layout == .preview { layout = .split }
                    selection = SourceSelection(offset: offset)
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
            } detail: {
                HSplitView {
                    if layout != .preview { sourcePane.frame(minWidth: 280, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity) }
                    if layout != .source { previewPane.frame(minWidth: 280, idealWidth: 440, maxWidth: .infinity, maxHeight: .infinity) }
                }
            }
            .navigationSplitViewStyle(.balanced)
            Divider()
            statusBar
        }
        .frame(minWidth: 780, minHeight: 480)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { compile(immediate: true) } label: {
                    Label("Compile", systemImage: "gearshape.2")
                }.keyboardShortcut("b", modifiers: .command).help("Compile document (⌘B)")
                Menu {
                    Toggle("Live preview", isOn: $automatic)
                    Divider()
                    Text(preview.status)
                } label: {
                    Text(automatic ? String(localized: "Live") : String(localized: "Manual")).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(automatic ? Color.accentColor : Color.secondary)
                }.help("Preview updates")
                Button {
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
        .onAppear { preview.worker.reopen(); compile() }
        .onChange(of: document.source) { dismissAssistance(); compile() }
        .onChange(of: fileURL) { dismissAssistance(); compile() }
        .onChange(of: cursor) { dismissAssistance() }
        .onChange(of: layout) { dismissAssistance() }
        .onChange(of: automatic) { compile() }
        .onDisappear { dismissAssistance(); preview.stop() }
        .task(id: document.source) {
            let source = document.source
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
            let result = await Task.detached(priority: .utility) {
                (TyPadCore.summarizeSource(source: source).lineCount, DocumentHeading.scan(source))
            }.value
            guard !Task.isCancelled else { return }
            lineCount = result.0
            headings = result.1
        }
    }

    private var sourcePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(.secondary)
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
            SourceEditor(text: $document.source, selection: selection, cursor: $cursor, replacement: replacement,
                         language: language, assistanceVisible: $showAssistance,
                         requestCompletion: { query("complete", offset: $0) }, acceptCompletion: { item in
                replacement = SourceReplacement(source: language.source, edits: item.edits)
                showAssistance = false
            }).clipped()
        }
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
                Picker("Zoom", selection: $scale) {
                    ForEach(PreviewScale.allCases, id: \.self) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }.labelsHidden().frame(width: 106).controlSize(.small).disabled(preview.pdf == nil)
            }.font(.system(size: 12)).padding(.horizontal, 12).frame(height: 28)
            Divider()
            if let pdf = preview.pdf {
                PDFPreview(data: pdf, revision: preview.previewRevision, scale: scale)
                    .overlay(alignment: .top) {
                        if preview.isStale && (!automatic || !preview.diagnostics.isEmpty) {
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

    private func query(_ operation: String, offset: Int) {
        showAssistance = true
        language.query(operation, source: document.source, path: fileURL?.path,
                       offset: offset, revision: preview.revision, worker: preview.worker)
    }
    private func dismissAssistance() { showAssistance = false; language.invalidate() }
    private func compile(immediate: Bool = false) {
        preview.update(source: document.source, url: fileURL, automatic: automatic, immediate: immediate)
    }
}
