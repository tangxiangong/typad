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
        guard url.standardizedFileURL == url.standardizedFileURL.resolvingSymlinksInPath() else {
            throw ProjectFailure.externalChange(url.lastPathComponent)
        }
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

struct ProjectFile: Identifiable, Sendable, Equatable {
    var id: URL { url }
    let url: URL
    let children: [ProjectFile]?
}

struct ProjectBuffer: Identifiable, Codable, Sendable {
    var id: URL { url }
    var url: URL
    var source: String
    var savedData: Data
    var hasBOM: Bool
    var missingOnDisk: Bool? = nil
    var data: Data { (hasBOM ? Data([0xef, 0xbb, 0xbf]) : Data()) + Data(source.utf8) }
    var isDirty: Bool { missingOnDisk == true || data != savedData }
}

struct ProjectConflict: Identifiable {
    let id = UUID()
    let url: URL
    let disk: ProjectBuffer
    let localSource: String
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
    @Published private(set) var unavailableFiles: [URL: String] = [:]
    private var diskFingerprint: [URL: String]?
    @Published private(set) var conflicts: [URL: ProjectBuffer] = [:]
    @Published private(set) var history: [URL] = []
    @Published private(set) var historyIndex = -1
    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex + 1 < history.count }
    private var navigatingHistory = false
    var didEdit: (() -> Void)?
    private var sharedEdits: AnyCancellable?
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
        var missingOnDisk: Bool? = nil
    }

    private struct Configuration: Codable, Sendable {
        var main: String?
        var tabs: [String]
        var active: String?
        var history: [String]? = nil
        var historyIndex: Int? = nil
    }
    private var configurationURL: URL? { root?.appendingPathComponent(".typad.json") }
    var isDirty: Bool { buffers.contains(where: \.isDirty) }
    var active: ProjectBuffer? { buffers.first { $0.url == activeURL } }
    var main: ProjectBuffer? { buffers.first { $0.url == mainURL } }
    var snapshots: [String: String] {
        let openDocuments = root.map { ProjectEdits.snapshots(in: $0, includingProjects: false) } ?? [:]
        return openDocuments.merging(Dictionary(uniqueKeysWithValues: buffers.map { ($0.url.path, $0.source) })) { _, project in project }
    }

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
        observeSharedEdits()
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
            restoreHistory(config)
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
                return ProjectBuffer(url: url, source: item.source, savedData: item.savedData, hasBOM: item.hasBOM, missingOnDisk: item.missingOnDisk)
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

    private func restoreHistory(_ config: Configuration) {
        guard let root, let paths = config.history else { return }
        history = paths.map { root.appendingPathComponent($0).standardizedFileURL.resolvingSymlinksInPath() }.filter(contains)
        historyIndex = min(max(0, config.historyIndex ?? history.count - 1), history.count - 1)
        if historyIndex >= 0, history[historyIndex] != activeURL {
            historyIndex = activeURL.flatMap { history.lastIndex(of: $0) } ?? historyIndex
        }
    }

    private func observeSharedEdits() {
        ProjectEdits.register(self)
        sharedEdits = ProjectEdits.changes.sink { [weak self] change in
            MainActor.assumeIsolated {
                guard let self, self.contains(change.url) else { return }
                guard let buffer = self.buffers.first(where: { $0.url == change.url }) else {
                    self.revision &+= 1
                    return
                }
                guard buffer.source != change.after else { return }
                guard buffer.source == change.before else {
                    self.error = String(localized: "Another window has different edits for this file. Your local edits have been kept.")
                    return
                }
                self.edit(change.after, at: change.url)
            }
        }
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
            var buffer = try ProjectFileAccess.read(url) { try ProjectFileAccess.buffer($0) }
            if let source = ProjectEdits.source(for: url) { buffer.source = source }
            buffers.append(buffer)
            revision &+= 1
        }
        activeURL = url
        if !navigatingHistory, historyIndex < 0 || history[historyIndex] != url {
            history = Array(history.prefix(historyIndex + 1)) + [url]
            historyIndex = history.count - 1
        }
        if mainURL == nil, url.pathExtension == "typ" { mainURL = url }
        if persist { try persistConfiguration() }
    }

    func edit(_ source: String, at url: URL) {
        guard let index = buffers.firstIndex(where: { $0.url == url }), !buffers[index].source.utf16.elementsEqual(source.utf16) else { return }
        let oldSource = buffers[index].source
        buffers[index].source = source
        ProjectEdits.changes.send(ProjectEdits.Change(url: url, before: oldSource, after: source))
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
        let wasNavigating = navigatingHistory
        navigatingHistory = selected != nil
        defer { navigatingHistory = wasNavigating }
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

    func goBack() throws { try goHistory(-1) }
    func goForward() throws { try goHistory(1) }
    private func goHistory(_ delta: Int) throws {
        let next = historyIndex + delta
        guard history.indices.contains(next) else { return }
        navigatingHistory = true
        defer { navigatingHistory = false }
        try open(history[next], persist: false)
        historyIndex = next
        try persistConfiguration()
    }

    /// Clean buffers follow disk changes; dirty or unreadable buffers always retain the local edit.
    func reconcileExternalChanges() throws {
        let results = Dictionary(uniqueKeysWithValues: buffers.map { buffer in
            (buffer.url, Result { try ProjectFileAccess.read(buffer.url) { try ProjectFileAccess.buffer($0) } })
        })
        try applyDiskChanges(results)
    }

    func refreshExternalChanges() async throws {
        guard let root else { return }
        let baselines = Dictionary(uniqueKeysWithValues: buffers.map { ($0.url, $0.savedData) })
        let scan = try await Task.detached(priority: .utility) {
            let files = try ProjectFileAccess.scan(root)
            var fingerprint: [URL: String] = [:]
            func record(_ items: [ProjectFile]) throws {
                for item in items {
                    if let children = item.children { try record(children) }
                    else {
                        let values = try item.url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                        fingerprint[item.url] = "\(values.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0):\(values.fileSize ?? 0)"
                    }
                }
            }
            try record(files)
            let results = Dictionary(uniqueKeysWithValues: baselines.keys.map { url in
                (url, Result { try ProjectFileAccess.read(url) { try ProjectFileAccess.buffer($0) } })
            })
            return (files, fingerprint, results)
        }.value
        guard !Task.isCancelled else { return }
        if files != scan.0 { files = scan.0 }
        if let previous = diskFingerprint, previous != scan.1 { revision &+= 1 }
        diskFingerprint = scan.1
        // A save or move performed while the background read ran wins over its stale result.
        let current = scan.2.filter { url, _ in buffers.first { $0.url == url }?.savedData == baselines[url] }
        try applyDiskChanges(current)
    }

    private func applyDiskChanges(_ results: [URL: Result<ProjectBuffer, Error>]) throws {
        var changed = false
        for index in buffers.indices {
            let buffer = buffers[index]
            guard let result = results[buffer.url] else { continue }
            let disk: ProjectBuffer
            switch result {
            case .success(let value):
                disk = value
                unavailableFiles.removeValue(forKey: buffer.url)
            case .failure(let failure):
                let message = failure.localizedDescription
                if unavailableFiles[buffer.url] != message { unavailableFiles[buffer.url] = message; changed = true }
                conflicts.removeValue(forKey: buffer.url)
                if !FileManager.default.fileExists(atPath: buffer.url.path), buffer.missingOnDisk != true {
                    buffers[index].missingOnDisk = true; changed = true
                }
                continue
            }
            if disk.savedData == buffer.savedData {
                if buffer.missingOnDisk == true { buffers[index].missingOnDisk = nil; changed = true }
                conflicts.removeValue(forKey: buffer.url); continue
            }
            if buffer.isDirty && buffer.data != disk.data {
                if conflicts[buffer.url]?.savedData != disk.savedData { conflicts[buffer.url] = disk }
            } else {
                buffers[index] = disk
                conflicts.removeValue(forKey: buffer.url)
                changed = true
            }
        }
        if changed { revision &+= 1; try persistRecovery(); didEdit?() }
    }

    func restoreMissingFile(_ url: URL) throws {
        guard contains(url), let index = buffers.firstIndex(where: { $0.url == url }) else { throw ProjectFailure.outsideProject }
        let data = buffers[index].data
        // Never replace an item that has reappeared since the warning was shown.
        try data.write(to: url, options: .withoutOverwriting)
        buffers[index].savedData = data
        buffers[index].missingOnDisk = nil
        unavailableFiles.removeValue(forKey: url)
        revision &+= 1
        try persistRecovery(); try refresh(); didEdit?()
    }

    func conflictSnapshot(at url: URL) -> ProjectConflict? {
        guard let disk = conflicts[url], let buffer = buffers.first(where: { $0.url == url }) else { return nil }
        return ProjectConflict(url: url, disk: disk, localSource: buffer.source)
    }

    func resolveConflict(_ url: URL, source: String, expectedDisk: Data, expectedSource: String) throws {
        guard let index = buffers.firstIndex(where: { $0.url == url }), buffers[index].source == expectedSource else {
            throw ProjectFailure.externalChange(url.lastPathComponent)
        }
        let disk = try ProjectFileAccess.read(url) { try ProjectFileAccess.buffer($0) }
        guard disk.savedData == expectedDisk else { throw ProjectFailure.externalChange(url.lastPathComponent) }
        buffers[index] = disk
        buffers[index].source = source
        ProjectEdits.changes.send(ProjectEdits.Change(url: url, before: expectedSource, after: source))
        conflicts.removeValue(forKey: url)
        revision &+= 1
        try persistRecovery()
        didEdit?()
    }

    /// Move the item on disk, staging literal reference updates as recoverable unsaved edits.
    func move(_ input: URL, to destination: URL) throws {
        let old = input.standardizedFileURL.resolvingSymlinksInPath()
        let new = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard contains(old), contains(new), old != new, !new.path.hasPrefix(old.path + "/") else {
            throw ProjectFailure.outsideProject
        }
        guard !FileManager.default.fileExists(atPath: new.path) else { throw CocoaError(.fileWriteFileExists) }
        func mapped(_ url: URL) -> URL {
            if url == old { return new }
            if url.path.hasPrefix(old.path + "/") { return new.appendingPathComponent(String(url.path.dropFirst(old.path.count + 1))) }
            return url
        }
        func leaves(_ items: [ProjectFile]) -> [URL] {
            items.flatMap { item in item.children.map(leaves) ?? [item.url] }
        }
        try refresh()
        var staged = buffers
        for url in leaves(files) where url.pathExtension == "typ" && !staged.contains(where: { $0.url == url }) {
            var buffer = try ProjectFileAccess.read(url) { try ProjectFileAccess.buffer($0) }
            if let source = ProjectEdits.source(for: url) { buffer.source = source }
            staged.append(buffer)
        }
        let previous = Dictionary(uniqueKeysWithValues: staged.map { ($0.url, $0.source) })
        for index in staged.indices {
            let buffer = staged[index]
            if mapped(buffer.url) != buffer.url || buffer.url.pathExtension == "typ" {
                guard contains(buffer.url), (try? Data(contentsOf: buffer.url)) == buffer.savedData else {
                    throw ProjectFailure.externalChange(buffer.url.lastPathComponent)
                }
            }
            if buffer.url.pathExtension == "typ", let root {
                staged[index].source = ProjectReferences.rewrite(buffer.source, file: buffer.url,
                    newFile: mapped(buffer.url), root: root, map: mapped)
            }
            staged[index].url = mapped(buffer.url)
        }
        let openURLs = Set(buffers.map { mapped($0.url) })
        staged.removeAll { !openURLs.contains($0.url) && !$0.isDirty }
        // Persist the old edits before the filesystem operation; never discard user text on failure.
        try persistRecovery()
        try FileManager.default.moveItem(at: old, to: new)
        buffers = staged
        for buffer in staged {
            if let before = previous[buffer.url], before != buffer.source {
                ProjectEdits.changes.send(ProjectEdits.Change(url: buffer.url, before: before, after: buffer.source))
            }
        }
        activeURL = activeURL.map(mapped)
        mainURL = mainURL.map(mapped)
        history = history.map(mapped)
        conflicts = [:]
        unavailableFiles = [:]
        revision &+= 1
        didEdit?()
        try persistRecovery()
        try persistConfiguration()
        try refresh()
    }

    /// The caller moves the item to Trash first, after confirming any dirty buffers.
    func forgetRemovedItem(_ url: URL) throws {
        func removed(_ candidate: URL) -> Bool { candidate == url || candidate.path.hasPrefix(url.path + "/") }
        buffers.removeAll { removed($0.url) }
        conflicts = conflicts.filter { !removed($0.key) }
        unavailableFiles = unavailableFiles.filter { !removed($0.key) }
        if let mainURL, removed(mainURL) { self.mainURL = buffers.first { $0.url.pathExtension == "typ" }?.url }
        if let activeURL, removed(activeURL) { self.activeURL = buffers.last?.url }
        history = history.filter { !removed($0) }; historyIndex = history.count - 1
        revision &+= 1
        try persistRecovery(); try persistConfiguration(); try refresh()
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
                RecoveryBuffer(path: relativePath($0.url), source: $0.source, savedData: $0.savedData, hasBOM: $0.hasBOM, missingOnDisk: $0.missingOnDisk)
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
                                   active: activeURL.map(relativePath), history: history.map(relativePath), historyIndex: historyIndex)
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
            workspace.restoreHistory(config)
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
            var buffer = try await ProjectFileAccess.readAsync(url) { try ProjectFileAccess.buffer($0) }
            if let source = ProjectEdits.source(for: url) { buffer.source = source }
            if !buffers.contains(where: { $0.url == url }) { buffers.append(buffer); revision &+= 1 }
        }
        activeURL = url
        if !navigatingHistory, historyIndex < 0 || history[historyIndex] != url {
            history = Array(history.prefix(historyIndex + 1)) + [url]
            historyIndex = history.count - 1
        }
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
        let config = Configuration(main: mainURL.map(relativePath), tabs: buffers.map { relativePath($0.url) }, active: activeURL.map(relativePath), history: history.map(relativePath), historyIndex: historyIndex)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try await ProjectFileAccess.writeAsync(url) { try data.write(to: $0, options: .atomic) }
    }

}

/// Direct #include/#import/resource calls only; computed, aliased, and code-block paths need manual review.
enum ProjectReferences {
    static func rewrite(_ source: String, file: URL, newFile: URL, root: URL, map: (URL) -> URL) -> String {
        let text = source as NSString
        let pattern = #"(?:#(?:include|import)\s+|#(?:image|read|bibliography|csv|json|yaml|xml|cbor|toml)\s*\(\s*)$"#
        let expression = try! NSRegularExpression(pattern: pattern)
        var index = 0, blockDepth = 0, raw = 0
        var edits: [(NSRange, String)] = []
        var code = ""
        while index < text.length {
            let c = text.character(at: index)
            let next: unichar = index + 1 < text.length ? text.character(at: index + 1) : 0
            if raw > 0 {
                if c == 96 {
                    var end = index
                    while end < text.length && text.character(at: end) == 96 { end += 1 }
                    if end - index == raw { raw = 0 }
                    index = end
                } else { index += 1 }
                code = ""; continue
            }
            if blockDepth > 0 {
                if c == 47 && next == 42 { blockDepth += 1; index += 2 }
                else if c == 42 && next == 47 { blockDepth -= 1; index += 2 }
                else { index += 1 }
                continue
            }
            if c == 47 && next == 47 {
                while index < text.length && text.character(at: index) != 10 { index += 1 }
                code += " "; continue
            }
            if c == 47 && next == 42 { blockDepth = 1; index += 2; code += " "; continue }
            if c == 96 {
                raw = 1; index += 1
                while index < text.length && text.character(at: index) == 96 { raw += 1; index += 1 }
                code = ""; continue
            }
            if c == 34 {
                let start = index + 1
                index = start
                var escaped = false
                while index < text.length {
                    if text.character(at: index) == 92 { escaped = true; index += 2; continue }
                    if text.character(at: index) == 34 { break }
                    index += 1
                }
                guard index < text.length else { break }
                let range = NSRange(location: start, length: index - start)
                let path = text.substring(with: range)
                let suffix = text.substring(from: index + 1).drop(while: { $0 == " " || $0 == "\t" })
                let literalEnd = suffix.isEmpty || suffix.first.map { "\n\r),:;]}".contains($0) } == true
                if literalEnd, !escaped, !path.hasPrefix("@"), !path.contains("://"),
                   expression.firstMatch(in: code, range: NSRange(location: 0, length: (code as NSString).length)) != nil {
                    let absolute = path.hasPrefix("/")
                    let target = (absolute ? root : file.deletingLastPathComponent())
                        .appendingPathComponent(absolute ? String(path.dropFirst()) : path).standardizedFileURL
                    let moved = map(target)
                    if moved != target || file != newFile {
                        let base = absolute ? root : newFile.deletingLastPathComponent()
                        let a = base.pathComponents, b = moved.pathComponents
                        var common = 0
                        while common < min(a.count, b.count) && a[common] == b[common] { common += 1 }
                        let relative = (Array(repeating: "..", count: a.count - common) + b.dropFirst(common)).joined(separator: "/")
                        let replacement = (absolute ? "/" : "") + relative
                        if !replacement.contains("\""), !replacement.contains("\\") { edits.append((range, replacement)) }
                    }
                }
                code = ""; index += 1; continue
            }
            code += text.substring(with: NSRange(location: index, length: 1))
            if code.utf16.count > 512 { code = String(code.suffix(256)) }
            index += 1
        }
        let result = NSMutableString(string: source)
        for (range, replacement) in edits.reversed() { result.replaceCharacters(in: range, with: replacement) }
        return result as String
    }
}

@MainActor
enum ProjectEdits {
    struct Change {
        let url: URL
        let before: String
        let after: String
    }
    static let changes = PassthroughSubject<Change, Never>()
    private struct WeakProject { weak var value: ProjectWorkspace? }
    private struct WeakSource { weak var value: OpenSource? }
    private static var projects: [WeakProject] = []
    private static var documents: [WeakSource] = []
    static func register(_ project: ProjectWorkspace) {
        projects.removeAll { $0.value == nil }; projects.append(WeakProject(value: project))
    }
    static func register(_ source: OpenSource) {
        documents.removeAll { $0.value == nil || $0.value === source }; documents.append(WeakSource(value: source))
    }
    static func snapshots(in root: URL, includingProjects: Bool = true) -> [String: String] {
        var result: [String: String] = [:]
        for source in documents.compactMap({ $0.value }) {
            if let url = source.url, url.path.hasPrefix(root.path + "/") { result[url.path] = source.source }
        }
        for project in projects.compactMap({ $0.value }) where includingProjects {
            for buffer in project.buffers where buffer.isDirty && buffer.url.path.hasPrefix(root.path + "/") {
                result[buffer.url.path] = buffer.source
            }
        }
        return result
    }
    static func source(for url: URL) -> String? {
        let projectEdits = projects.compactMap { $0.value?.buffers.first { $0.url == url && $0.isDirty }?.source }
        let documentEdits = documents.compactMap { $0.value }.filter { $0.url == url }.map(\.source)
        let sources = Set(projectEdits.isEmpty ? documentEdits : projectEdits)
        return sources.count == 1 ? sources.first : nil
    }
}

@MainActor
final class OpenSource: ObservableObject {
    var url: URL?
    var source = ""
}
