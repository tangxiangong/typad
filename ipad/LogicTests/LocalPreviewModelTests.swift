import Foundation
import PDFKit

@main
struct LocalPreviewModelTests {
    @MainActor
    static func main() async throws {
        for (before, after) in [("", "中文"), ("简体", "簡體"), ("a😀z", "a😃z"), ("abc😀", "abc"),
                                ("e\u{301}", "é"), ("one\r\ntwo", "one\ntwo"), ("👩‍💻中文", "👩‍🔬中文")] {
            let change = TextChange(from: before, to: after)!
            precondition(change.applying(to: before).utf16.elementsEqual(after.utf16))
            precondition(change.inverse(in: before).applying(to: after).utf16.elementsEqual(before.utf16))
        }
        let large = String(repeating: "a", count: 100_000)
        precondition(TextChange(from: large, to: large + "中")?.replacement == "中")
        @MainActor final class UndoProbe {
            var value = 0
            func change(to value: Int, using history: TextUndoManager) {
                let previous = self.value
                history.recordEdit(withTarget: self, name: "Edit") { $0.change(to: previous, using: history) }
                self.value = value
            }
        }
        let probe = UndoProbe()
        let history = TextUndoManager()
        history.groupsByEvent = false
        for disabledLevels in 0...2 {
            history.resetEdits()
            history.beginUndoGrouping()
            history.beginUndoGrouping() // UIKit can leave nested native groups open.
            for _ in 0..<disabledLevels { history.disableUndoRegistration() }
            probe.value = 0
            history.recordEdit(withTarget: probe, name: "Edit") { $0.value = 1 }
            precondition(history.canUndo && history.groupingLevel == 2)
            history.registerUndo(withTarget: probe) { $0.value = 99 } // Simulate duplicate native registration.
            history.undo()
            precondition(probe.value == 1 && !history.canUndo, "Native groups and registrations must not enter app history")
            history.endUndoGrouping()
            history.endUndoGrouping()
        }
        history.resetEdits()
        probe.value = 0
        probe.change(to: 1, using: history)
        probe.change(to: 2, using: history)
        history.undo()
        precondition(probe.value == 1 && history.canRedo)
        history.undo()
        precondition(probe.value == 0 && !history.canUndo)
        history.redo()
        precondition(probe.value == 1)
        history.redo()
        precondition(probe.value == 2 && !history.canRedo)
        history.resetEdits()
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let main = root.appendingPathComponent("src/main.typ")
        let child = root.appendingPathComponent("child.typ")
        try Data().write(to: main)
        try Data("#let broken =".utf8).write(to: child)
        model.update(source: "#include \"/child.typ\"", url: main, resourceFolder: root,
                     automatic: true, immediate: true, projectRoot: root, files: [child.path: "Unsaved child 中文"])
        try await wait { !model.isStale && !model.isCompiling }
        precondition(PDFDocument(data: model.pdf!)?.string?.contains("Unsaved child") == true)
        let disk = try String(contentsOf: child, encoding: .utf8)
        precondition(disk == "#let broken =")
        model.update(source: "#include \"/child.typ\"", url: main, resourceFolder: root,
                     automatic: true, immediate: true, projectRoot: root)
        try await wait { !model.diagnostics.isEmpty && !model.isCompiling }
        precondition(model.isStale, "Closing a child buffer must stop shadowing its on-disk contents")
        try Data("Coordinated disk child".utf8).write(to: child)
        model.update(source: "#include \"/child.typ\"", url: main, resourceFolder: root,
                     automatic: true, immediate: true, projectRoot: root)
        try await wait { !model.isStale && !model.isCompiling }
        precondition(PDFDocument(data: model.pdf!)?.string?.contains("Coordinated disk child") == true)
        model.update(source: "#set page(width: 100pt, height: 60pt, margin: 10pt)\n#set text(font: \"Noto Sans SC\", size: 20pt)\n中文",
                     url: nil, resourceFolder: nil, automatic: true, immediate: true)
        try await wait { !model.isStale && !model.isCompiling }
        precondition(model.diagnostics.isEmpty, "Bundled Chinese fallback must be available")
        let chineseDocument = PDFDocument(data: model.pdf!)!
        let page = chineseDocument.page(at: 0)!
        try model.pdf!.write(to: URL(fileURLWithPath: "target/ipad-logic/chinese-fallback.pdf"))
        var pixels = [UInt8](repeating: 255, count: 200 * 120 * 4)
        let ink = withExtendedLifetime(chineseDocument) { pixels.withUnsafeMutableBytes { buffer -> Int in
            let context = CGContext(data: buffer.baseAddress, width: 200, height: 120, bitsPerComponent: 8,
                                    bytesPerRow: 200 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
            context.scaleBy(x: 2, y: 2)
            page.draw(with: .mediaBox, to: context)
            let bytes = buffer.bindMemory(to: UInt8.self)
            return stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] < 128 && bytes[$0 + 1] < 128 && bytes[$0 + 2] < 128 }.count
        }
        }
        precondition(ink > 100, "Chinese PDF must draw visible glyphs, not only expose accessibility text")
        print("LocalPreviewModel: debounce, PDF output, failure retention, pause, manual compile, stop, project snapshots Chinese glyph rasterization and isolated undo/redo passed")
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
