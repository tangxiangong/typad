import Foundation
import Combine
import CryptoKit

/// Serializes access with Files providers and their file presenters.
enum ProjectFileAccess {
    static func read<T>(_ url: URL, _ action: (URL) throws -> T) throws -> T {
        try coordinate(url, writing: false, action)
    }
    static func write<T>(_ url: URL, _ action: (URL) throws -> T) throws -> T {
        try coordinate(url, writing: true, action)
    }
    static func readAsync<T: Sendable>(_ url: URL, _ action: @escaping @Sendable (URL) throws -> T) async throws -> T {
        try await Task.detached { try read(url, action) }.value
    }
    static func writeAsync<T: Sendable>(_ url: URL, _ action: @escaping @Sendable (URL) throws -> T) async throws -> T {
        try await Task.detached { try write(url, action) }.value
    }
    static func scan(_ directory: URL) throws -> [ProjectFile] {
        // Release each directory's coordination before recursing into the next one.
        let entries: [(URL, Bool)] = try read(directory) { directory in
            try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .compactMap { url in
                    let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values.isSymbolicLink != true,
                          !["target", "node_modules", ".build"].contains(url.lastPathComponent) else { return nil }
                    return (url.standardizedFileURL.resolvingSymlinksInPath(), values.isDirectory == true)
                }
        }
        return try entries.map { url, directory in
            ProjectFile(url: url, children: directory ? try scan(url) : nil)
        }
    }
    static func buffer(_ url: URL) throws -> ProjectBuffer {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size < 8 * 1024 * 1024 else { throw ProjectFailure.unsupportedFile }
        let data = try Data(contentsOf: url)
        let bom = data.starts(with: [0xef, 0xbb, 0xbf])
        guard let source = String(data: bom ? data.dropFirst(3) : data, encoding: .utf8), !source.contains("\0") else {
            throw ProjectFailure.unsupportedFile
        }
        return ProjectBuffer(url: url, source: source, savedData: data, hasBOM: bom)
    }
    private static func coordinate<T>(_ url: URL, writing: Bool, _ action: (URL) throws -> T) throws -> T {
#if os(iOS)
        let expected = url.standardizedFileURL.resolvingSymlinksInPath()
        var result: Result<T, Error>?
        var error: NSError?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        if writing {
            coordinator.coordinate(writingItemAt: url, options: [], error: &error) { coordinatedURL in
                result = Result {
                    guard coordinatedURL.standardizedFileURL.resolvingSymlinksInPath() == expected else {
                        throw ProjectFailure.externalChange(url.lastPathComponent)
                    }
                    return try action(coordinatedURL)
                }
            }
        } else {
            coordinator.coordinate(readingItemAt: url, options: [], error: &error) { coordinatedURL in
                result = Result {
                    guard coordinatedURL.standardizedFileURL.resolvingSymlinksInPath() == expected else {
                        throw ProjectFailure.externalChange(url.lastPathComponent)
                    }
                    return try action(coordinatedURL)
                }
            }
        }
        if let result { return try result.get() }
        throw error ?? CocoaError(writing ? .fileWriteUnknown : .fileReadUnknown) as NSError
#else
        return try action(url)
#endif
    }
}

enum ProjectLocation {
    static var appContainer: URL? {
#if os(iOS)
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
#else
        nil
#endif
    }
    static func identity(for url: URL, container: URL? = appContainer) -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if let container {
            let base = container.standardizedFileURL.resolvingSymlinksInPath().path
            if path.hasPrefix(base + "/") { return "app:" + path.dropFirst(base.count + 1) }
        }
        return path
    }
}

struct ProjectFile: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let children: [ProjectFile]?
}

struct ProjectBuffer: Identifiable, Codable, Sendable {
    var id: URL { url }
    let url: URL
    var source: String
    var savedData: Data
    var hasBOM: Bool
    var data: Data { (hasBOM ? Data([0xef, 0xbb, 0xbf]) : Data()) + Data(source.utf8) }
    var isDirty: Bool { data != savedData }
}

enum ProjectFailure: LocalizedError {
    case outsideProject, unsupportedFile, mainDocumentOpen, externalChange(String)
    var errorDescription: String? {
        switch self {
        case .mainDocumentOpen: return String(localized: "Choose another main document before closing this tab.")
        case .outsideProject: return String(localized: "The file is outside this project.")
        case .unsupportedFile: return String(localized: "Choose a UTF-8 text file smaller than 8 MB.")
        case .externalChange(let name): return String(localized: "The file changed on disk: \(name). Your edits have been kept. Save a copy before resolving the conflict.")
        }
    }
}

/// Owns one folder's buffers. Saving never serializes or replaces the folder itself.
@MainActor
final class ProjectWorkspace: ObservableObject {
    let root: URL?
    let projectIdentity: String
    @Published private(set) var files: [ProjectFile] = []
    @Published private(set) var buffers: [ProjectBuffer] = []
    @Published private(set) var activeURL: URL?
    @Published private(set) var mainURL: URL?
    @Published private(set) var revision: UInt64 = 0
    @Published var recoveredEdits = false
    @Published var error: String?
    @Published var isBusy = false
    var didEdit: (() -> Void)?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryURL: URL?
    private var legacyRecovery: [(url: URL, root: URL)] = []
    private struct Recovery: Codable {
        var project: String
        var buffers: [RecoveryBuffer]
    }
    private struct RecoveryBuffer: Codable {
        var path: String
        var source: String
        var savedData: Data
        var hasBOM: Bool
    }

    private struct Configuration: Codable, Sendable {
        var main: String?
        var tabs: [String]
        var active: String?
    }
    private var configurationURL: URL? { root?.appendingPathComponent(".typad.json") }
    var isDirty: Bool { buffers.contains(where: \.isDirty) }
    var active: ProjectBuffer? { buffers.first { $0.url == activeURL } }
    var main: ProjectBuffer? { buffers.first { $0.url == mainURL } }
    var snapshots: [String: String] { Dictionary(uniqueKeysWithValues: buffers.map { ($0.url.path, $0.source) }) }

    init() { root = nil; projectIdentity = "" }

    init(root: URL, recoveryDirectory: URL? = nil, load: Bool = true, container: URL? = ProjectLocation.appContainer, legacyRoots: [URL] = []) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        projectIdentity = ProjectLocation.identity(for: root, container: container)
        guard let root = self.root else { return }
        let directory = recoveryDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TyPad/Recovery", isDirectory: true)
        func snapshotURL(_ identity: String) -> URL {
            let key = SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
            return directory.appendingPathComponent(key + ".json")
        }
        recoveryURL = snapshotURL(projectIdentity)
        for oldRoot in [root] + legacyRoots {
            let oldRoot = oldRoot.standardizedFileURL.resolvingSymlinksInPath()
            let url = snapshotURL(oldRoot.path)
            if url != recoveryURL, !legacyRecovery.contains(where: { $0.url == url }) {
                legacyRecovery.append((url, oldRoot))
            }
        }
        guard load else { return }
        try refresh()
        if let configURL = configurationURL, FileManager.default.fileExists(atPath: configURL.path) {
            let config = try JSONDecoder().decode(Configuration.self, from: ProjectFileAccess.read(configURL) { try Data(contentsOf: $0) })
            for path in config.tabs {
                do { try open(root.appendingPathComponent(path), persist: false) }
                catch { self.error = error.localizedDescription }
            }
            if let path = config.main {
                do { try setMain(root.appendingPathComponent(path), persist: false) }
                catch { self.error = error.localizedDescription }
            }
            if let path = config.active {
                do { try open(root.appendingPathComponent(path), persist: false) }
                catch { self.error = error.localizedDescription }
            }
        } else {
            let candidate = root.appendingPathComponent("main.typ")
            if FileManager.default.fileExists(atPath: candidate.path) {
                try setMain(candidate, persist: false)
            }
        }
        try restoreRecovery()
    }

    private func restoreRecovery() throws {
        guard let root, let recoveryURL else { return }
        let existing = legacyRecovery.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            .sorted { ((try? $0.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    > ((try? $1.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        let candidate = FileManager.default.fileExists(atPath: recoveryURL.path) ? (url: recoveryURL, root: root) : existing.first
        guard let candidate else { return }
        let data = try Data(contentsOf: candidate.url)
        let recovered: [ProjectBuffer]
        if let snapshot = try? JSONDecoder().decode(Recovery.self, from: data) {
            guard snapshot.project == projectIdentity else { throw ProjectFailure.outsideProject }
            recovered = try snapshot.buffers.map { item in
                let url = root.appendingPathComponent(item.path).standardizedFileURL.resolvingSymlinksInPath()
                guard !item.path.hasPrefix("/"), !item.path.split(separator: "/").contains(".."), contains(url) else {
                    throw ProjectFailure.outsideProject
                }
                return ProjectBuffer(url: url, source: item.source, savedData: item.savedData, hasBOM: item.hasBOM)
            }
        } else {
            let legacy = try JSONDecoder().decode([ProjectBuffer].self, from: data)
            recovered = try legacy.map { buffer in
                let path = buffer.url.standardizedFileURL.resolvingSymlinksInPath().path
                guard path.hasPrefix(candidate.root.path + "/") else { throw ProjectFailure.outsideProject }
                let relative = String(path.dropFirst(candidate.root.path.count + 1))
                let url = root.appendingPathComponent(relative).standardizedFileURL.resolvingSymlinksInPath()
                guard contains(url) else { throw ProjectFailure.outsideProject }
                return ProjectBuffer(url: url, source: buffer.source, savedData: buffer.savedData, hasBOM: buffer.hasBOM)
            }
        }
        for buffer in recovered where buffer.isDirty {
            if let index = buffers.firstIndex(where: { $0.url == buffer.url }) { buffers[index] = buffer }
            else { buffers.append(buffer) }
        }
        if activeURL == nil { activeURL = buffers.first?.url }
        if mainURL == nil { mainURL = buffers.first { $0.url.pathExtension == "typ" }?.url }
        recoveredEdits = isDirty
        if candidate.url != recoveryURL { try persistRecovery() }
    }

    func contains(_ url: URL) -> Bool {
        guard let root else { return false }
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path.hasPrefix(root.path + "/")
    }

    func refresh() throws {
        guard let root else { return }
        files = try ProjectFileAccess.scan(root)
    }

    func open(_ input: URL, persist: Bool = true) throws {
        let url = input.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(url) else { throw ProjectFailure.outsideProject }
        if !buffers.contains(where: { $0.url == url }) {
            buffers.append(try ProjectFileAccess.read(url) { try ProjectFileAccess.buffer($0) })
            revision &+= 1
        }
        activeURL = url
        if mainURL == nil, url.pathExtension == "typ" { mainURL = url }
        if persist { try persistConfiguration() }
    }

    func edit(_ source: String, at url: URL) {
        guard let index = buffers.firstIndex(where: { $0.url == url }), !buffers[index].source.utf16.elementsEqual(source.utf16) else { return }
        buffers[index].source = source
        revision &+= 1
        didEdit?()
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard let self else { return }
            do { try self.persistRecovery() } catch { self.error = error.localizedDescription }
        }
    }

    func setMain(_ url: URL, persist: Bool = true) throws {
        guard url.pathExtension == "typ" else { throw ProjectFailure.unsupportedFile }
        let selected = activeURL
        try open(url, persist: false)
        mainURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if let selected { activeURL = selected }
        revision &+= 1
        if persist { try persistConfiguration() }
    }

    func save(_ url: URL) throws {
        guard let index = buffers.firstIndex(where: { $0.url == url }), buffers[index].isDirty else { return }
        let buffer = buffers[index]
        try ProjectFileAccess.write(url) { coordinatedURL in
            guard contains(coordinatedURL), (try? Data(contentsOf: coordinatedURL)) == buffer.savedData else {
                throw ProjectFailure.externalChange(url.lastPathComponent)
            }
            try buffer.data.write(to: coordinatedURL, options: .atomic)
        }
        buffers[index].savedData = buffer.data
        try persistRecovery()
        didEdit?()
    }

    func saveAll() throws {
        for buffer in buffers where buffer.isDirty { try save(buffer.url) }
        try persistConfiguration()
    }

    /// Caller obtains a save/discard decision first.
    func close(_ url: URL, persist: Bool = true) throws {
        guard url != mainURL else { throw ProjectFailure.mainDocumentOpen }
        buffers.removeAll { $0.url == url }
        if activeURL == url { activeURL = buffers.last?.url }
        if mainURL == nil { mainURL = buffers.first { $0.url.pathExtension == "typ" }?.url }
        revision &+= 1
        try persistRecovery()
        didEdit?()
        if persist { try persistConfiguration() }
    }

    func persistRecovery() throws {
        recoveryTask?.cancel()
        guard let recoveryURL else { return }
        if isDirty {
            try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = Recovery(project: projectIdentity, buffers: buffers.filter(\.isDirty).map {
                RecoveryBuffer(path: relativePath($0.url), source: $0.source, savedData: $0.savedData, hasBOM: $0.hasBOM)
            })
            try JSONEncoder().encode(snapshot).write(to: recoveryURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: recoveryURL.path) {
            try FileManager.default.removeItem(at: recoveryURL)
        }
        try clearLegacyRecovery()
    }

    private func clearLegacyRecovery() throws {
        for item in legacyRecovery where FileManager.default.fileExists(atPath: item.url.path) {
            try FileManager.default.removeItem(at: item.url)
        }
    }

    func clearRecovery() throws {
        recoveryTask?.cancel()
        if let recoveryURL, FileManager.default.fileExists(atPath: recoveryURL.path) {
            try FileManager.default.removeItem(at: recoveryURL)
        }
        try clearLegacyRecovery()
    }

    func relativePath(_ url: URL) -> String {
        guard let root, contains(url) else { return url.lastPathComponent }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    func persistConfiguration() throws {
        guard let url = configurationURL else { return }
        let config = Configuration(main: mainURL.map(relativePath), tabs: buffers.map { relativePath($0.url) },
                                   active: activeURL.map(relativePath))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try ProjectFileAccess.write(url) { try data.write(to: $0, options: .atomic) }
    }

    /// iPad waits for Files providers away from the main actor, then publishes state here.
    static func loadAsync(root: URL, recoveryDirectory: URL? = nil, container: URL? = ProjectLocation.appContainer, legacyRoots: [URL] = []) async throws -> ProjectWorkspace {
        let workspace = try ProjectWorkspace(root: root, recoveryDirectory: recoveryDirectory, load: false, container: container, legacyRoots: legacyRoots)
        try await workspace.refreshAsync()
        guard let root = workspace.root, let configURL = workspace.configurationURL else { return workspace }
        let hasConfig = await Task.detached { FileManager.default.fileExists(atPath: configURL.path) }.value
        let config: Configuration? = hasConfig ? try await ProjectFileAccess.readAsync(configURL) {
            try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: $0))
        } : nil
        if let config {
            for path in config.tabs {
                do { try await workspace.openAsync(root.appendingPathComponent(path), persist: false) }
                catch { workspace.error = error.localizedDescription }
            }
            if let path = config.main {
                do { try await workspace.setMainAsync(root.appendingPathComponent(path), persist: false) }
                catch { workspace.error = error.localizedDescription }
            }
            if let path = config.active {
                do { try await workspace.openAsync(root.appendingPathComponent(path), persist: false) }
                catch { workspace.error = error.localizedDescription }
            }
        } else {
            let main = root.appendingPathComponent("main.typ")
            if workspace.files.contains(where: { $0.url == main }) { try await workspace.setMainAsync(main, persist: false) }
        }
        try workspace.restoreRecovery()
        return workspace
    }

    func refreshAsync() async throws {
        guard let root else { return }
        files = try await Task.detached { try ProjectFileAccess.scan(root) }.value
    }

    func openAsync(_ input: URL, persist: Bool = true) async throws {
        let url = input.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(url) else { throw ProjectFailure.outsideProject }
        if !buffers.contains(where: { $0.url == url }) {
            let buffer = try await ProjectFileAccess.readAsync(url) { try ProjectFileAccess.buffer($0) }
            if !buffers.contains(where: { $0.url == url }) { buffers.append(buffer); revision &+= 1 }
        }
        activeURL = url
        if mainURL == nil, url.pathExtension == "typ" { mainURL = url }
        if persist { try await persistConfigurationAsync() }
    }

    func setMainAsync(_ url: URL, persist: Bool = true) async throws {
        guard url.pathExtension == "typ" else { throw ProjectFailure.unsupportedFile }
        let selected = activeURL
        try await openAsync(url, persist: false)
        mainURL = url.standardizedFileURL.resolvingSymlinksInPath()
        if let selected { activeURL = selected }
        revision &+= 1
        if persist { try await persistConfigurationAsync() }
    }

    func saveAsync(_ url: URL) async throws {
        guard let buffer = buffers.first(where: { $0.url == url }), buffer.isDirty, let root else { return }
        try await ProjectFileAccess.writeAsync(url) { coordinatedURL in
            guard coordinatedURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.path + "/"),
                  (try? Data(contentsOf: coordinatedURL)) == buffer.savedData else {
                throw ProjectFailure.externalChange(url.lastPathComponent)
            }
            try buffer.data.write(to: coordinatedURL, options: .atomic)
        }
        if let index = buffers.firstIndex(where: { $0.url == url }) { buffers[index].savedData = buffer.data }
        try persistRecovery()
        didEdit?()
    }

    func saveAllAsync() async throws {
        for buffer in buffers where buffer.isDirty { try await saveAsync(buffer.url) }
        try await persistConfigurationAsync()
    }

    func closeAsync(_ url: URL) async throws {
        try close(url, persist: false)
        try await persistConfigurationAsync()
    }

    func persistConfigurationAsync() async throws {
        guard let url = configurationURL else { return }
        let config = Configuration(main: mainURL.map(relativePath), tabs: buffers.map { relativePath($0.url) }, active: activeURL.map(relativePath))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try await ProjectFileAccess.writeAsync(url) { try data.write(to: $0, options: .atomic) }
    }

}
