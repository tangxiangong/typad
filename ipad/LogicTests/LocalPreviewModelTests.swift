import Foundation
import PDFKit

@main
struct LocalPreviewModelTests {
    @MainActor
    static func main() async throws {
        let model = LocalPreviewModel()
        model.update(source: "Discarded draft", url: nil, resourceFolder: nil, automatic: true)
        model.update(source: "= 身上\n\n中文 English $x^2$", url: nil, resourceFolder: nil, automatic: true)
        try await wait { model.pdf != nil && !model.isCompiling }
        guard let firstPDF = model.pdf,
              PDFDocument(data: firstPDF)?.string?.contains("身上") == true else {
            fatalError("Debounce must compile the latest source snapshot into a readable PDF")
        }
        let firstRevision = model.previewRevision
        // Keep a renderable artifact: text extraction alone cannot detect .notdef boxes.
        try firstPDF.write(to: URL(fileURLWithPath: "target/ipad-logic/chinese-preview.pdf"))

        model.update(source: "#let x =", url: nil, resourceFolder: nil, automatic: true, immediate: true)
        try await wait { !model.diagnostics.isEmpty && !model.isCompiling }
        precondition(model.pdf == firstPDF, "A compilation error must retain the last successful PDF")
        precondition(model.isStale && model.previewRevision == firstRevision)

        model.update(source: "Paused draft", url: nil, resourceFolder: nil, automatic: false)
        try await Task.sleep(nanoseconds: 500_000_000)
        precondition(model.previewRevision == firstRevision && model.isStale)
        model.update(source: "Manual draft", url: nil, resourceFolder: nil, automatic: false, immediate: true)
        try await wait { !model.isStale && !model.isCompiling }
        precondition(PDFDocument(data: model.pdf!)?.string?.contains("Manual draft") == true)

        let lastPDF = model.pdf
        model.update(source: "Cancelled draft", url: nil, resourceFolder: nil, automatic: true)
        model.stop()
        try await Task.sleep(nanoseconds: 500_000_000)
        precondition(model.pdf == lastPDF, "Closing a document must cancel its pending debounce")
        print("LocalPreviewModel: debounce, PDF output, failure retention, pause, manual compile and stop passed")
    }

    @MainActor
    private static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(30)
        while !condition() {
            guard Date() < deadline else { fatalError("Timed out waiting for local compilation") }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
