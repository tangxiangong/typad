import Foundation
import Darwin

struct WorkerEdit: Codable, Equatable {
    let start: Int
    let length: Int
    let text: String
}
struct WorkerCompletion: Decodable, Identifiable {
    var id: String { label + edits.map { "\($0.start):\($0.text)" }.joined() }
    let label: String
    let detail: String
    let edits: [WorkerEdit]
}
struct WorkerDiagnostic: Decodable {
    let warning: Bool
    let message: String
    let file: String?
    let line: UInt64?
    let column: UInt64?
    let utf16Offset: UInt64?
}
struct WorkerResult: Decodable {
    let pdf: Data?
    let pageCount: UInt64?
    let elapsedMs: UInt64?
    let diagnostics: [WorkerDiagnostic]?
    let completions: [WorkerCompletion]?
    let documentation: String?
}
private struct WorkerResponse: Decodable {
    let `protocol`: Int
    let id: UInt64
    let revision: UInt64
    let result: WorkerResult?
    let error: String?
}
private struct WorkerRequest: Encodable {
    let `protocol` = 1
    let id: UInt64
    let revision: UInt64
    let operation: String
    let source: String
    let path: String?
    let offset: Int
}

enum WorkerFailure: LocalizedError {
    case unavailable, disconnected, timeout, invalidResponse, operation(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: return String(localized: "The TyPad worker is missing. Rebuild the application.")
        case .disconnected: return String(localized: "The TyPad worker exited unexpectedly.")
        case .timeout: return String(localized: "The TyPad worker timed out. Try compiling again.")
        case .invalidResponse: return String(localized: "The TyPad worker returned an invalid response.")
        case .operation(let message): return message
        }
    }
}

/// The main process only transports immutable snapshots. Heavy work lives in Rust.
@MainActor
final class WorkerClient {
    private struct Pending {
        let revision: UInt64
        let continuation: CheckedContinuation<WorkerResult, Error>
        let timer: Task<Void, Never>
    }
    private let executable: URL?
    private let timeout: UInt64
    private let writes = DispatchQueue(label: "com.typad.worker.write")
    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var pending: [UInt64: Pending] = [:]
    private var nextID: UInt64 = 0
    private var generation = UUID()
    private var closed = false

    init(executable: URL? = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("typad-worker"), timeoutSeconds: UInt64 = 60) {
        self.executable = executable
        self.timeout = timeoutSeconds
    }

    func request(operation: String, source: String, path: String?, revision: UInt64, offset: Int = 0) async throws -> WorkerResult {
        // One bounded automatic restart, always resending the full unsaved snapshot.
        for attempt in 0...1 {
            do { return try await send(operation: operation, source: source, path: path, revision: revision, offset: offset) }
            catch {
                if closed || Task.isCancelled { throw CancellationError() }
                if case WorkerFailure.operation = error { throw error }
                if case WorkerFailure.unavailable = error { throw error }
                if attempt == 1 { throw error }
            }
        }
        throw WorkerFailure.disconnected
    }

    func reopen() { closed = false }

    func close() {
        closed = true
        fail(WorkerFailure.disconnected)
    }

    private func start() throws {
        guard !closed else { throw CancellationError() }
        if let process, process.isRunning { return }
        guard let executable, FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw WorkerFailure.unavailable
        }
        let child = Process()
        let stdin = Pipe(), stdout = Pipe()
        child.executableURL = executable
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.standardError
        let token = UUID()
        generation = token
        buffer = Data()
        child.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.fail(WorkerFailure.disconnected)
            }
        }
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        try child.run()
        process = child
        input = stdin.fileHandleForWriting
        let reader = stdout.fileHandleForReading
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            defer { try? reader.close() }
            var bytes = [UInt8](repeating: 0, count: 65_536)
            while true {
                let count = Darwin.read(reader.fileDescriptor, &bytes, bytes.count)
                if count < 0 && errno == EINTR { continue }
                if count <= 0 { break }
                let data = Data(bytes.prefix(count))
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.receive(data)
                }
            }

        }
    }

    private func send(operation: String, source: String, path: String?, revision: UInt64, offset: Int) async throws -> WorkerResult {
        try Task.checkCancellation()
        try start()
        nextID &+= 1
        let id = nextID, token = generation
        var data = try JSONEncoder().encode(WorkerRequest(id: id, revision: revision, operation: operation, source: source, path: path, offset: offset))
        guard data.count < 16 * 1024 * 1024 else { throw WorkerFailure.operation(String(localized: "Document exceeds the worker request limit.")) }
        data.append(10)
        let frame = data
        guard let input else { throw WorkerFailure.disconnected }
        return try await withCheckedThrowingContinuation { continuation in
            let timer = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: (self?.timeout ?? 60) * 1_000_000_000) }
                catch { return }
                guard let self, self.generation == token, self.pending[id] != nil else { return }
                self.fail(WorkerFailure.timeout)
            }
            pending[id] = Pending(revision: revision, continuation: continuation, timer: timer)
            writes.async { [weak self] in
                do { try input.write(contentsOf: frame) }
                catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.generation == token else { return }
                        self.fail(WorkerFailure.disconnected)
                    }
                }
            }
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 128 * 1024 * 1024 else { fail(WorkerFailure.invalidResponse); return }
        while let newline = buffer.firstIndex(of: 10) {
            let frame = buffer[..<newline]
            guard let response = try? JSONDecoder().decode(WorkerResponse.self, from: frame), response.protocol == 1 else {
                fail(WorkerFailure.invalidResponse); return
            }
            buffer.removeSubrange(...newline)
            guard let item = pending.removeValue(forKey: response.id) else { continue }
            item.timer.cancel()
            if response.revision != item.revision {
                item.continuation.resume(throwing: WorkerFailure.invalidResponse)
            } else if let error = response.error {
                item.continuation.resume(throwing: WorkerFailure.operation(error))
            } else if let result = response.result {
                item.continuation.resume(returning: result)
            } else {
                item.continuation.resume(throwing: WorkerFailure.invalidResponse)
            }
        }
    }

    private func fail(_ error: Error) {
        generation = UUID()
        let child = process
        process = nil
        let writer = input
        input = nil
        writes.async { try? writer?.close() }
        buffer = Data()
        let requests = pending
        pending.removeAll()
        for item in requests.values {
            item.timer.cancel()
            item.continuation.resume(throwing: error)
        }
        if let child, child.isRunning {
            child.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
            }
        }
    }
}
