import Foundation
import SwiftUI

/// One in-flight compile and one replaceable pending snapshot per document window.
@MainActor
final class PreviewModel: ObservableObject {
    @Published private(set) var pdf: Data?
    @Published private(set) var diagnostics: [WorkerDiagnostic] = []
    @Published private(set) var status = String(localized: "Waiting to compile")
    @Published private(set) var isCompiling = false
    @Published private(set) var isStale = true
    @Published private(set) var pageCount: UInt64 = 0
    @Published private(set) var previewRevision: UInt64 = 0
    @Published private(set) var revision: UInt64 = 0
    private var debounce: Task<Void, Never>?
    private var pending: Snapshot?
    // One isolated worker per document window; requests run serially inside it.
    let worker = WorkerClient()

    private struct Snapshot {
        let source: String
        let path: String?
        let revision: UInt64
        let root: String?
        let files: [String: String]
    }

    func update(source: String, url: URL?, automatic: Bool, immediate: Bool = false, root: String? = nil, files: [String: String] = [:]) {
        revision &+= 1
        isStale = true
        diagnostics = []
        debounce?.cancel()
        pending = nil
        guard automatic || immediate else {
            status = String(localized: "Auto compile paused")
            return
        }
        let snapshot = Snapshot(source: source, path: url?.path, revision: revision, root: root, files: files)
        status = String(localized: "Waiting to compile")
        debounce = Task { [weak self] in
            if !immediate {
                do { try await Task.sleep(nanoseconds: 350_000_000) }
                catch { return }
            }
            guard !Task.isCancelled, let self, self.revision == snapshot.revision else { return }
            self.pending = snapshot
            self.startNext()
        }
    }

    func invalidate() {
        revision &+= 1
        debounce?.cancel()
        pending = nil
        isStale = true
        pdf = nil
        diagnostics = []
        status = String(localized: "Choose a main Typst document")
    }

    func stop() {
        revision &+= 1
        debounce?.cancel()
        pending = nil
        worker.close()
    }

    private func startNext() {
        guard !isCompiling, let snapshot = pending else { return }
        pending = nil
        isCompiling = true
        status = String(localized: "Compiling…")
        Task { [weak self] in
            guard let self else { return }
            do {
                let output = try await worker.request(operation: "compile", source: snapshot.source,
                    path: snapshot.path, revision: snapshot.revision, root: snapshot.root, files: snapshot.files)
                if snapshot.revision == revision {
                    diagnostics = output.diagnostics ?? []
                    if let bytes = output.pdf {
                        pdf = bytes
                        pageCount = output.pageCount ?? 0
                        previewRevision = snapshot.revision
                        isStale = false
                        status = String(localized: "Compiled in \(output.elapsedMs ?? 0) ms")
                    } else { status = String(localized: "Compilation failed") }
                }
            } catch {
                if snapshot.revision == revision { status = error.localizedDescription }
            }
            isCompiling = false
            startNext()
        }
    }
}
