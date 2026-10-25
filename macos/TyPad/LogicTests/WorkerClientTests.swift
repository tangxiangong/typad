import Foundation

@main
struct WorkerClientTests {
    @MainActor
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let binary = root.appendingPathComponent("target/debug/typad-worker")
        let client = WorkerClient(executable: binary, timeoutSeconds: 15)
        let source = "= Unsaved 中文 😀\n\nHello"
        let output = try await client.request(operation: "compile", source: source, path: nil, revision: 7)
        precondition(output.pdf?.starts(with: Data("%PDF-".utf8)) == true)
        let completionSource = "#let mycustom = 2\n#myc"
        let completion = try await client.request(operation: "complete", source: completionSource, path: nil, revision: 8, offset: completionSource.utf16.count)
        precondition(completion.completions?.contains(where: { $0.label == "mycustom" }) == true)
        let unicodeSource = "😀 #tex"
        let unicodeCompletion = try await client.request(operation: "complete", source: unicodeSource, path: nil, revision: 81, offset: unicodeSource.utf16.count)
        precondition(unicodeCompletion.completions?.allSatisfy { $0.label.lowercased().hasPrefix("tex") } == true,
                     "Completion candidates must be filtered before the result limit")
        let textItem = unicodeCompletion.completions!.first { $0.label == "text" }!
        let inserted = NSMutableString(string: unicodeSource)
        for edit in textItem.edits.sorted(by: { $0.start > $1.start }) {
            inserted.replaceCharacters(in: NSRange(location: edit.start, length: edit.length), with: edit.text)
        }
        precondition((inserted as String).hasPrefix("😀 #text"))
        let hover = try await client.request(operation: "hover", source: "#text[Hello]", path: nil, revision: 9, offset: 3)
        precondition(hover.documentation?.isEmpty == false)
        let invalid = "😀 中文 #unknown_name"
        let failed = try await client.request(operation: "compile", source: invalid, path: nil, revision: 10)
        precondition(failed.pdf == nil)
        precondition(failed.diagnostics?.contains(where: { $0.utf16Offset == 7 && !$0.warning }) == true)
        client.close()
        print("PASS: actual worker PDF, user-symbol completion, documentation and Unicode diagnostics")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        setenv("TYPAD_WORKER_TEST_BINARY", binary.path, 1)
        let fixture = root.appendingPathComponent("ci/fixtures/worker-failure.py")
        for mode in ["once", "always", "hang"] {
            let marker = temp.appendingPathComponent(mode)
            setenv("TYPAD_WORKER_TEST_STATE", marker.path, 1)
            setenv("TYPAD_WORKER_TEST_MODE", mode, 1)
            let recovering = WorkerClient(executable: fixture, timeoutSeconds: mode == "hang" ? 1 : 15)
            do {
                let recovered = try await recovering.request(operation: "compile", source: source, path: nil, revision: 12)
                precondition(mode == "once")
                precondition(recovered.pdf?.starts(with: Data("%PDF-".utf8)) == true)
            } catch {
                precondition(mode != "once", "Recovery failed: \(error)")
            }
            recovering.close()
            let starts = try String(contentsOf: marker, encoding: .utf8)
            precondition(starts == "2", "Expected one bounded restart; got \(starts)")
            print("PASS: \(mode) — exactly one restart, full unsaved snapshot replay or bounded failure")
        }
    }
}
