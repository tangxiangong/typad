import SwiftUI

struct ConflictView: View {
    @ObservedObject var workspace: ProjectWorkspace
    let snapshot: ProjectConflict
    private var url: URL { snapshot.url }
    private var disk: ProjectBuffer { snapshot.disk }
    @Environment(\.dismiss) private var dismiss
    @State private var merged = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Resolve external changes").font(.headline)
            Text(workspace.relativePath(url)).foregroundStyle(.secondary)
            HSplitView {
                VStack(alignment: .leading) {
                    Text("On Disk").font(.headline)
                    ScrollView { Text(disk.source).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                }
                VStack(alignment: .leading) {
                    Text("Merged Result").font(.headline)
                    TextEditor(text: $merged).font(.system(.body, design: .monospaced))
                }
            }
            Text("The result starts with your local edits. Compare with the disk version and edit the result, then apply and save.")
                .font(.callout).foregroundStyle(.secondary)
            if let failure { Text(failure).foregroundStyle(.red) }
            HStack {
                Button("Use Disk Version") { merged = disk.source }
                Button("Use Local Version") { merged = snapshot.localSource }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply Merge") {
                    do { try workspace.resolveConflict(url, source: merged, expectedDisk: disk.savedData, expectedSource: snapshot.localSource); dismiss() }
                    catch { failure = error.localizedDescription }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(minWidth: 800, minHeight: 500)
        .onAppear { merged = snapshot.localSource }
    }
}

/// A separate native editor session keeps each pane's selection and undo stack independent.
struct SecondaryEditor: View {
    @ObservedObject var workspace: ProjectWorkspace
    let url: URL
    let close: () -> Void
    @StateObject private var sessions = SourceEditorSessions()
    @StateObject private var language = LanguageModel()
    @State private var cursor = 0
    @State private var assistance = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(workspace.relativePath(url)).lineLimit(1)
                Spacer()
                Button(action: close) { Label("Close Split Editor", systemImage: "xmark") }.labelStyle(.iconOnly)
            }.font(.caption).padding(8)
            Divider()
            SourceEditor(text: Binding(get: { workspace.buffers.first { $0.url == url }?.source ?? "" },
                                       set: { workspace.edit($0, at: url) }), selection: nil, cursor: $cursor,
                         replacement: nil, language: language, assistanceVisible: $assistance,
                         requestCompletion: { _ in }, acceptCompletion: { _ in }, session: sessions.session(for: url))
                .id(url)
        }
    }
}
