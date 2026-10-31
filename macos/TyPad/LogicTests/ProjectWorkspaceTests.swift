import Foundation
import CryptoKit

@main
struct ProjectWorkspaceTests {
    @MainActor
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temporary.appendingPathComponent("project")
        let recovery = temporary.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let main = root.appendingPathComponent("main.typ")
        let child = root.appendingPathComponent("child.typ")
        try Data("#include \"child.typ\"".utf8).write(to: main)
        let original = Data([0xef, 0xbb, 0xbf]) + Data("中文\r\n😀".utf8)
        try original.write(to: child)
        let project = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(project.mainURL == main)
        do { try project.close(main); preconditionFailure("Pinned main must remain open") }
        catch ProjectFailure.mainDocumentOpen { }
        let asset = root.appendingPathComponent("asset.bin")
        try Data([0xff, 0x00, 0x80]).write(to: asset)
        do { try project.open(asset); preconditionFailure("Binary files must not be edited as UTF-8") }
        catch ProjectFailure.unsupportedFile { }
        let outside = temporary.appendingPathComponent("outside.typ")
        try Data("outside".utf8).write(to: outside)
        let link = root.appendingPathComponent("link.typ")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        do { try project.open(link); preconditionFailure("Symlinks must not escape the project") }
        catch ProjectFailure.outsideProject { }
        try project.open(child)
        precondition(project.mainURL == main && project.activeURL == child)
        precondition(project.active?.source == "中文\r\n😀")
        project.edit("Unsaved 中文\r\n😀", at: child)
        precondition(project.isDirty && project.snapshots[child.path] == "Unsaved 中文\r\n😀")
        let onDisk = try Data(contentsOf: child)
        precondition(onDisk == original)
        try project.persistRecovery()
        let restored = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(restored.active?.source == "Unsaved 中文\r\n😀" && restored.isDirty)
        try restored.saveAll()
        precondition(!restored.isDirty)
        let untouched = try Data(contentsOf: asset)
        precondition(untouched == Data([0xff, 0x00, 0x80]), "Saving must preserve unrelated assets")
        let saved = try Data(contentsOf: child)
        precondition(saved == Data([0xef, 0xbb, 0xbf]) + Data("Unsaved 中文\r\n😀".utf8))
        let reopened = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(reopened.mainURL == main && reopened.activeURL == child && !reopened.isDirty)
        reopened.edit("local edit", at: child)
        try Data("external edit".utf8).write(to: child)
        do { try reopened.saveAll(); preconditionFailure("Must reject an external edit") }
        catch ProjectFailure.externalChange { }
        precondition(reopened.active?.source == "local edit")
        let external = try String(contentsOf: child, encoding: .utf8)
        precondition(external == "external edit")
        do { try reopened.open(temporary.appendingPathComponent("outside.typ")); preconditionFailure("Must reject outside paths") }
        catch ProjectFailure.outsideProject { }
        try reopened.close(child)
        precondition(reopened.activeURL == main && reopened.snapshots[child.path] == nil)
        try project.clearRecovery()
        let freshRoot = temporary.appendingPathComponent("fresh")
        try FileManager.default.createDirectory(at: freshRoot, withIntermediateDirectories: false)
        let freshMain = freshRoot.appendingPathComponent("main.typ")
        try Data("Fresh project".utf8).write(to: freshMain)
        let fresh = try await ProjectWorkspace.loadAsync(root: freshRoot, recoveryDirectory: recovery)
        precondition(fresh.mainURL == freshMain, "First open must work without .typad.json")
        let asyncProject = try await ProjectWorkspace.loadAsync(root: root, recoveryDirectory: recovery)
        let ranOnMain = try await ProjectFileAccess.readAsync(root) { _ in Thread.isMainThread }
        precondition(!ranOnMain, "Files coordination must not wait on the main thread")
        try await asyncProject.openAsync(child)
        asyncProject.edit("Async save 中文", at: child)
        try await asyncProject.saveAllAsync()
        let asyncSaved = try String(contentsOf: child, encoding: .utf8)
        precondition(asyncSaved == "Async save 中文" && !asyncProject.isDirty)
        asyncProject.edit("Async local conflict", at: child)
        try asyncProject.persistRecovery()
        try Data("Async external edit".utf8).write(to: child)
        do { try await asyncProject.saveAllAsync(); preconditionFailure("Async saves must reject external edits") }
        catch ProjectFailure.externalChange { }
        let asyncRestored = try await ProjectWorkspace.loadAsync(root: root, recoveryDirectory: recovery)
        precondition(asyncRestored.active?.source == "Async local conflict")
        try await asyncRestored.setMainAsync(child)
        precondition(asyncRestored.mainURL == child)
        try await asyncRestored.closeAsync(main)
        precondition(asyncRestored.snapshots[main.path] == nil)
        try asyncProject.clearRecovery()
        try asyncRestored.clearRecovery()
        let oldContainer = temporary.appendingPathComponent("containers/old")
        let newContainer = temporary.appendingPathComponent("containers/new")
        let oldRoot = oldContainer.appendingPathComponent("Documents/paper")
        let newRoot = newContainer.appendingPathComponent("Documents/paper")
        let movingRecovery = temporary.appendingPathComponent("moving-recovery")
        try FileManager.default.createDirectory(at: oldRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newRoot.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oldMain = oldRoot.appendingPathComponent("main.typ")
        try Data("Saved original".utf8).write(to: oldMain)
        let moving = try ProjectWorkspace(root: oldRoot, recoveryDirectory: movingRecovery, container: oldContainer)
        moving.edit("Unsaved after container relocation 中文", at: oldMain)
        try moving.persistRecovery()
        let legacyBuffers = moving.buffers
        try FileManager.default.copyItem(at: oldRoot, to: newRoot)
        let relocated = try await ProjectWorkspace.loadAsync(root: newRoot, recoveryDirectory: movingRecovery, container: newContainer)
        precondition(relocated.projectIdentity == moving.projectIdentity)
        precondition(relocated.main?.source == "Unsaved after container relocation 中文")
        precondition(relocated.mainURL == newRoot.appendingPathComponent("main.typ"))
        precondition(relocated.recoveredEdits && relocated.error == nil, "Recovery is a success notice, not an error")
        precondition(ProjectLocation.identity(for: newContainer.appendingPathComponent("Documents/other"), container: newContainer) != relocated.projectIdentity)
        moving.edit("e\u{301}", at: oldMain)
        moving.edit("é", at: oldMain)
        precondition(moving.main!.source.utf16.elementsEqual("é".utf16), "Canonical Unicode normalization is still a source edit")
        try moving.clearRecovery()
        try relocated.clearRecovery()
        let legacyKey = SHA256.hash(data: Data(oldRoot.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let legacyURL = movingRecovery.appendingPathComponent(legacyKey + ".json")
        try JSONEncoder().encode(legacyBuffers).write(to: legacyURL)
        let migrated = try ProjectWorkspace(root: newRoot, recoveryDirectory: movingRecovery,
                                            container: newContainer, legacyRoots: [oldRoot])
        precondition(migrated.main?.source == "Unsaved after container relocation 中文")
        precondition(!FileManager.default.fileExists(atPath: legacyURL.path), "Legacy snapshot migrates only after writing the new format")
        try migrated.clearRecovery()
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: movingRecovery, includingPropertiesForKeys: nil)
        precondition(recoveryFiles.isEmpty, "Discard must not resurrect a legacy snapshot")
        print("PASS: project main selection, buffers, BOM/CRLF, atomic save, recovery, conflicts, containment async Files operations and container relocation recovery")
    }
}
