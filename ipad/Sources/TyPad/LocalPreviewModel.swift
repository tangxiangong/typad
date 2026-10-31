import CoreText
import Foundation
import TyPadCore

// fontdb does not discover iOS fonts; CoreText provides sandbox-accessible font URLs.
private let platformFonts: Void = {
    let collection = CTFontCollectionCreateFromAvailableFonts(nil)
    let descriptors = CTFontCollectionCreateMatchingFontDescriptors(collection) as? [CTFontDescriptor] ?? []
    let paths = Set(descriptors.compactMap { descriptor -> String? in
        guard let url = CTFontDescriptorCopyAttribute(descriptor, kCTFontURLAttribute) as? URL,
              url.isFileURL else { return nil }
        return url.path
    }).sorted()
    let bundled = ["NotoSansSC-Regular", "NotoSansSC-Bold"].compactMap {
        Bundle.main.url(forResource: $0, withExtension: "otf", subdirectory: "Fonts")?.path
    }
    initializeFonts(paths: bundled + paths)
}()

/// Serializes native compilation across windows to bound peak memory usage.
private let compilationQueue = DispatchQueue(label: "com.tangxiangong.typad.compile", qos: .userInitiated)

@MainActor
final class LocalPreviewModel: ObservableObject {
    @Published private(set) var pdf: Data?
    @Published private(set) var diagnostics: [CompileDiagnostic] = []
    @Published private(set) var status = String(localized: "Waiting to compile")
    @Published private(set) var isCompiling = false
    @Published private(set) var isStale = true
    @Published private(set) var previewRevision: UInt64 = 0
    private var revision: UInt64 = 0
    private var debounce: Task<Void, Never>?
    private var pending: Snapshot?

    private struct Snapshot {
        let source: String
        let url: URL?
        let resourceFolder: URL?
        let files: [String: String]
        let projectRoot: URL?
        let revision: UInt64
    }

    func update(source: String, url: URL?, resourceFolder: URL?, automatic: Bool, immediate: Bool = false, projectRoot: URL? = nil, files: [String: String] = [:]) {
        revision &+= 1
        isStale = true
        diagnostics = []
        debounce?.cancel()
        pending = nil
        guard automatic || immediate else {
            status = String(localized: "Auto compile paused")
            return
        }
        let snapshot = Snapshot(source: source, url: url, resourceFolder: resourceFolder, files: files, projectRoot: projectRoot, revision: revision)
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

    func stop() {
        revision &+= 1
        debounce?.cancel()
        pending = nil
    }

    func waitForMainDocument() {
        stop()
        pdf = nil
        diagnostics = []
        isStale = true
        status = String(localized: "Choose a main Typst document")
    }

    private func startNext() {
        guard !isCompiling, let snapshot = pending else { return }
        pending = nil
        isCompiling = true
        status = String(localized: "Compiling…")
        Task { [weak self] in
            let output: CompileOutput = await withCheckedContinuation { continuation in
                compilationQueue.async {
                    _ = platformFonts
                    // Keep Files-provider access alive until Rust finishes reading resources.
                    let fileAccess = snapshot.url?.startAccessingSecurityScopedResource() ?? false
                    let folderAccess = snapshot.resourceFolder?.startAccessingSecurityScopedResource() ?? false
                    defer {
                        if fileAccess { snapshot.url?.stopAccessingSecurityScopedResource() }
                        if folderAccess { snapshot.resourceFolder?.stopAccessingSecurityScopedResource() }
                    }
                    if let root = snapshot.projectRoot, let url = snapshot.url {
                        continuation.resume(returning: compileProject(source: snapshot.source, path: url.path,
                            root: root.path, files: snapshot.files, revision: snapshot.revision, reader: CoordinatedProjectReader()))
                    } else {
                        continuation.resume(returning: compileDocument(source: snapshot.source,
                            path: snapshot.url?.path, revision: snapshot.revision))
                    }
                }
            }
            guard let self else { return }
            if snapshot.revision == revision {
                diagnostics = output.diagnostics
                if let bytes = output.pdf {
                    pdf = Data(bytes)
                    previewRevision = snapshot.revision
                    isStale = false
                    status = String(localized: "Compiled in \(output.elapsedMs) ms")
                } else {
                    status = String(localized: "Compilation failed")
                }
            }
            isCompiling = false
            startNext()
        }
    }
}

/// Rust calls this on the compilation queue for each disk dependency, including images.
private final class CoordinatedProjectReader: ProjectFileReader, @unchecked Sendable {
    func readFile(path: String) -> ProjectFileContents {
        let url = URL(fileURLWithPath: path)
        do {
            let data = try ProjectFileAccess.read(url) { coordinatedURL in
                return try Data(contentsOf: coordinatedURL)
            }
            return ProjectFileContents(bytes: data, error: "")
        } catch { return ProjectFileContents(bytes: nil, error: error.localizedDescription) }
    }
}
