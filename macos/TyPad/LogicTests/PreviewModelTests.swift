import Foundation
import PDFKit

@main
struct PreviewModelTests {
    @MainActor
    static func main() async throws {
        let binary = URL(fileURLWithPath: CommandLine.arguments[1])
        let worker = WorkerClient(executable: binary, timeoutSeconds: 30)
        let model = PreviewModel(worker: worker)
        defer { model.stop() }
        for template in ProjectTemplate.allCases {
            let result = try await worker.request(operation: "compile", source: template.source, path: nil, revision: 0)
            precondition(result.pdf != nil, "Template must compile: \(template.rawValue)")
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let main = temp.appendingPathComponent("main.typ")
        let child = temp.appendingPathComponent("child.typ")
        model.update(source: "#include \"child.typ\"", url: main, automatic: true, immediate: true,
                     root: temp.path, files: [child.path: "= 中文 English\n$ 1 + 2 = 3 $"])
        try await wait { model.pdf != nil && !model.isStale }
        let goodPDF = model.pdf!
        precondition(goodPDF.starts(with: Data("%PDF-".utf8)))
        precondition(model.previewRevision == model.revision && model.pageCount > 0)
        let rendered = PDFDocument(data: goodPDF)?.string ?? ""
        precondition(rendered.contains("English") && rendered.contains("中文") && rendered.contains("1") && rendered.contains("2") && rendered.contains("3") && rendered.contains("+"), "PDF text: \(rendered)")
        let exported = temp.appendingPathComponent("output.pdf")
        try model.exportPDF(to: exported, expectedRevision: model.revision)
        let exportedData = try Data(contentsOf: exported)
        precondition(exportedData == goodPDF, "Export must match the displayed source revision exactly")
        model.update(source: "#include \"child.typ\"", url: main, automatic: true, immediate: true,
                     root: temp.path, files: [child.path: "😀 #missing_symbol"])
        try await wait { !model.isCompiling && !model.diagnostics.isEmpty }
        precondition(model.pdf == goodPDF && model.isStale, "Failed compilation keeps the last successful preview and blocks current-result export")
        do { try model.exportPDF(to: exported, expectedRevision: model.revision); preconditionFailure("Stale export must fail") }
        catch { }
        let preserved = try Data(contentsOf: exported)
        precondition(preserved == goodPDF, "Rejected export must preserve the destination")
        let issue = model.diagnostics.first { !$0.warning }!
        precondition(issue.destination(root: temp, main: main) == child)
        precondition(issue.utf16Offset == 4, "Child diagnostic offsets use UTF-16, including surrogate pairs")
        let escape = WorkerDiagnostic(warning: false, message: "test", file: "../outside.typ", line: 1, column: 1, utf16Offset: 0)
        precondition(escape.destination(root: temp, main: main) == nil)
        model.update(source: "#missing_symbol", url: main, automatic: true, immediate: true)
        model.update(source: "Latest revision", url: main, automatic: true, immediate: true)
        try await wait { !model.isStale }
        precondition(model.diagnostics.isEmpty && model.previewRevision == model.revision)
        do { try model.exportPDF(to: exported, expectedRevision: model.revision - 1); preconditionFailure("A save panel opened for an older revision must not export") }
        catch { }
        let revision = model.previewRevision
        model.update(source: "Paused edit", url: main, automatic: false)
        try await Task.sleep(for: .milliseconds(450))
        precondition(model.isStale && model.previewRevision == revision && !model.isCompiling)
        model.update(source: "Cancelled edit", url: main, automatic: true)
        model.cancel()
        try await Task.sleep(for: .milliseconds(450))
        precondition(model.isStale && model.previewRevision == revision && !model.isCompiling)
        model.update(source: "After cancellation", url: main, automatic: true, immediate: true)
        try await wait { !model.isStale }
        let marker = temp.appendingPathComponent("cancelled-worker")
        setenv("TYPAD_WORKER_TEST_BINARY", binary.path, 1)
        setenv("TYPAD_WORKER_TEST_STATE", marker.path, 1)
        setenv("TYPAD_WORKER_TEST_MODE", "hang", 1)
        defer {
            unsetenv("TYPAD_WORKER_TEST_BINARY"); unsetenv("TYPAD_WORKER_TEST_STATE"); unsetenv("TYPAD_WORKER_TEST_MODE")
        }
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ci/fixtures/worker-failure.py")
        let cancellable = PreviewModel(worker: WorkerClient(executable: fixture, timeoutSeconds: 15))
        defer { cancellable.stop() }
        cancellable.update(source: "Cancel in flight", url: nil, automatic: true, immediate: true)
        try await wait { cancellable.isCompiling && FileManager.default.fileExists(atPath: marker.path) }
        cancellable.cancel()
        try await wait { !cancellable.isCompiling }
        let starts = try String(contentsOf: marker, encoding: .utf8)
        precondition(starts == "1", "An explicitly cancelled request must not automatically restart after reopen")
        setenv("TYPAD_WORKER_TEST_MODE", "once", 1)
        cancellable.update(source: "Compile after cancelling active worker", url: nil, automatic: true, immediate: true)
        try await wait { !cancellable.isStale }
        model.invalidate()
        precondition(model.pdf == nil && model.pageCount == 0 && model.isStale)
        print("PASS: templates, PDF content/export, multi-file preview, Unicode child diagnostics, stale-result gating, latest revision, pause/cancel/restart and invalidation")
    }

    @MainActor
    static func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(40)
        while !condition() {
            precondition(Date() < deadline, "Preview operation timed out")
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}
