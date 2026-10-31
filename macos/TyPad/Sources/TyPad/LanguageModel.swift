import SwiftUI

@MainActor
final class LanguageModel: ObservableObject {
    @Published private(set) var completions: [WorkerCompletion] = []
    @Published private(set) var documentation = ""
    @Published private(set) var status = ""
    @Published private(set) var busy = false
    private var generation = UUID()
    private(set) var source = ""

    func invalidate() {
        generation = UUID()
        completions = []
        documentation = ""
        busy = false
        status = String(localized: "Request suggestions or documentation at the current cursor.")
    }

    func query(_ operation: String, source: String, path: String?, offset: Int, revision: UInt64, worker: WorkerClient, root: String? = nil, files: [String: String] = [:]) {
        invalidate()
        self.source = source
        let token = generation
        busy = true
        status = String(localized: "Analyzing with Tinymist…")
        Task { [weak self] in
            do {
                let result = try await worker.request(operation: operation, source: source, path: path, revision: revision, offset: offset, root: root, files: files)
                guard let self, self.generation == token else { return }
                self.completions = result.completions ?? []
                self.documentation = result.documentation ?? ""
                self.status = operation == "complete" ? String(localized: "\(self.completions.count) suggestions") : (self.documentation.isEmpty ? String(localized: "No documentation at this position") : String(localized: "Tinymist documentation"))
                self.busy = false
            } catch {
                guard let self, self.generation == token else { return }
                self.status = error.localizedDescription
                self.busy = false
            }
        }
    }
}

struct SourceReplacement: Equatable {
    let id = UUID()
    let source: String
    let edits: [WorkerEdit]
}
