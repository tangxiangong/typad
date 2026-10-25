import SwiftUI
import TyPadCore

struct EditorView: View {
    @Binding var document: TypstDocument
    @State private var lineCount: UInt64 = 1

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $document.source)
                .font(.system(size: 14, design: .monospaced))
                .disableAutocorrection(true)
                .accessibilityLabel("Typst source")
                .accessibilityIdentifier("typst.source-editor")
            Divider()
            HStack {
                Text("\(lineCount) lines")
                Spacer()
                Text("UTF-8 · Typst")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(8)
        }
        .frame(minWidth: 640, minHeight: 420)
        .task(id: document.source) {
            let source = document.source
            do { try await Task.sleep(nanoseconds: 150_000_000) }
            catch { return }
            let count = await Task.detached(priority: .utility) {
                TyPadCore.summarizeSource(source: source).lineCount
            }.value
            guard !Task.isCancelled else { return }
            lineCount = count
        }
    }
}
