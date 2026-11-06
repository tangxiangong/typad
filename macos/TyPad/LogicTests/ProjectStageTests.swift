import Foundation

@main
struct ProjectStageTests {
    @MainActor
    static func main() async throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = temporary.appendingPathComponent("project")
        let recovery = temporary.appendingPathComponent("recovery")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let main = root.appendingPathComponent("main.typ")
        let child = root.appendingPathComponent("child.typ")
        let asset = root.appendingPathComponent("plot.svg")
        try Data("#include \"child.typ\"\n#include \"/child.typ\"\n// #include \"child.typ\"\n```typ\n#include \"child.typ\"\n```".utf8).write(to: main)
        try Data("#image(\"plot.svg\")\n中文😀".utf8).write(to: child)
        try Data("<svg/>".utf8).write(to: asset)
        let examples = "Please include \"child.typ\".\n#image(\"child.typ\" + suffix)\n/* #include \"child.typ\" */"
        precondition(ProjectReferences.rewrite(examples, file: main, newFile: main, root: root,
            map: { $0 == child ? root.appendingPathComponent("renamed.typ") : $0 }) == examples,
            "Prose, comments and computed expressions must never be rewritten")
        let project = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        try project.open(child)
        project.edit("#image(\"plot.svg\")\n未保存😀", at: child)
        let nested = root.appendingPathComponent("chapters")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let moved = nested.appendingPathComponent("renamed.typ")
        try project.move(child, to: moved)
        precondition(project.activeURL == moved)
        precondition(project.main?.source.hasPrefix("#include \"chapters/renamed.typ\"\n#include \"/chapters/renamed.typ\"") == true)
        precondition(project.main?.source.contains("// #include \"child.typ\"") == true)
        precondition(project.main?.source.contains("```typ\n#include \"child.typ\"\n```") == true)
        precondition(project.active?.source == "#image(\"../plot.svg\")\n未保存😀")
        precondition(project.active?.isDirty == true)
        let movedDisk = try String(contentsOf: moved, encoding: .utf8)
        precondition(movedDisk == "#image(\"plot.svg\")\n中文😀", "Move must retain the old saved baseline until Save")
        let restored = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(restored.snapshots == project.snapshots, "Moved dirty buffers and references must recover together")
        try project.saveAll()
        let savedMain = try String(contentsOf: main, encoding: .utf8)
        precondition(savedMain.contains("chapters/renamed.typ"))
        do { try project.move(moved, to: main); preconditionFailure("Existing destination must not be overwritten") }
        catch CocoaError.fileWriteFileExists { }
        do { try project.move(moved, to: temporary.appendingPathComponent("escape.typ")); preconditionFailure("Move must stay inside project") }
        catch ProjectFailure.outsideProject { }
        let renamedDir = root.appendingPathComponent("sections")
        try project.move(nested, to: renamedDir)
        let renamed = renamedDir.appendingPathComponent("renamed.typ")
        precondition(project.activeURL == renamed && project.main?.source.contains("sections/renamed.typ") == true)
        try project.saveAll()
        try Data("external clean".utf8).write(to: renamed)
        try project.reconcileExternalChanges()
        precondition(project.active?.source == "external clean" && !project.active!.isDirty)
        project.edit("local edit", at: renamed)
        try Data("external conflict".utf8).write(to: renamed)
        try project.reconcileExternalChanges()
        precondition(project.active?.source == "local edit")
        let conflict = project.conflicts[renamed]!
        try Data("external changed again".utf8).write(to: renamed)
        do { try project.resolveConflict(renamed, source: "merged", expectedDisk: conflict.savedData, expectedSource: "local edit"); preconditionFailure("Stale conflict cannot be accepted") }
        catch ProjectFailure.externalChange { }
        try project.reconcileExternalChanges()
        try project.resolveConflict(renamed, source: "merged", expectedDisk: project.conflicts[renamed]!.savedData, expectedSource: "local edit")
        precondition(project.active?.source == "merged" && project.active!.isDirty)
        try project.saveAll()
        let savedMerge = try String(contentsOf: renamed, encoding: .utf8)
        precondition(savedMerge == "merged")
        try project.open(main)
        try project.goBack()
        precondition(project.activeURL == renamed)
        try project.goForward()
        precondition(project.activeURL == main)
        try project.goBack()
        try project.open(asset)
        precondition(!project.canGoForward, "Opening a new item truncates forward history")
        let peer = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("peerRecovery"))
        try peer.open(renamed)
        project.edit("shared unsaved", at: renamed)
        precondition(peer.active?.source == "shared unsaved", "Other project views receive unsaved source changes")
        let disk = try String(contentsOf: renamed, encoding: .utf8)
        precondition(disk == "merged", "Cross-window synchronization must not implicitly save")
        try FileManager.default.removeItem(at: renamed)
        try project.reconcileExternalChanges()
        precondition(project.unavailableFiles[renamed] != nil)
        let missingRecovery = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(missingRecovery.buffers.first { $0.url == renamed }?.source == "shared unsaved",
                     "Externally deleted buffers must remain recoverable")
        try project.restoreMissingFile(renamed)
        let recreated = try String(contentsOf: renamed, encoding: .utf8)
        precondition(recreated == "shared unsaved")
        do { try project.restoreMissingFile(renamed); preconditionFailure("Recreate must not overwrite a reappeared file") }
        catch CocoaError.fileWriteFileExists { }
        try FileManager.default.removeItem(at: renamed)
        try project.forgetRemovedItem(renamed)
        precondition(project.buffers.allSatisfy { $0.url != renamed })
        precondition(project.snapshots[renamed.path] == nil)
        try await project.refreshExternalChanges()
        let resourceRevision = project.revision
        try Data("<svg>changed</svg>".utf8).write(to: asset)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3)], ofItemAtPath: asset.path)
        try await project.refreshExternalChanges()
        precondition(project.revision > resourceRevision, "Resource changes must invalidate the preview")
        let standalone = root.appendingPathComponent("standalone.typ")
        try Data("saved".utf8).write(to: standalone)
        let openSource = OpenSource()
        openSource.url = standalone; openSource.source = "unsaved in standalone window"
        ProjectEdits.register(openSource)
        let beforeShared = project.revision
        ProjectEdits.changes.send(ProjectEdits.Change(url: standalone, before: "saved", after: openSource.source))
        precondition(project.revision > beforeShared && project.snapshots[standalone.path] == openSource.source,
                     "Unopened project files must compile the standalone window's current text")
        try project.open(standalone)
        precondition(project.active?.source == openSource.source && project.active!.isDirty)
        try project.goBack()
        let historyRestore = try ProjectWorkspace(root: root, recoveryDirectory: recovery)
        precondition(historyRestore.history == project.history && historyRestore.historyIndex == project.historyIndex)
        try await checkConflictSnapshots(in: temporary)
        try checkSymlinkReplacement(in: temporary)
        try checkReferenceSynchronization(in: temporary)
        print("PASS: file/directory moves, literal references, recovery, conflicts/merge, navigation history, shared edits, removed buffers")
    }
    @MainActor
    static func checkConflictSnapshots(in temporary: URL) async throws {
        let root = temporary.appendingPathComponent("merge-review")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let main = root.appendingPathComponent("main.typ")
        try Data("base".utf8).write(to: main)
        let project = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("merge-recovery"))
        project.edit("local", at: main)
        try Data("disk one".utf8).write(to: main)
        try project.reconcileExternalChanges()
        let snapshot = project.conflictSnapshot(at: main)!
        try Data("disk two".utf8).write(to: main)
        try await project.refreshExternalChanges()
        precondition(snapshot.disk.source == "disk one", "An open merge must keep its original disk snapshot")
        do {
            try project.resolveConflict(main, source: "stale merge", expectedDisk: snapshot.disk.savedData, expectedSource: snapshot.localSource)
            preconditionFailure("Changing disk while the merge is open must reject its result")
        } catch ProjectFailure.externalChange { }
        let fresh = project.conflictSnapshot(at: main)!
        project.edit("new local edit", at: main)
        do {
            try project.resolveConflict(main, source: "stale merge", expectedDisk: fresh.disk.savedData, expectedSource: fresh.localSource)
            preconditionFailure("Changing local text while the merge is open must reject its result")
        } catch ProjectFailure.externalChange { }
        precondition(project.main?.source == "new local edit")
        let peer = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("merge-peer"))
        let latest = project.conflictSnapshot(at: main)!
        try project.resolveConflict(main, source: "accepted merge", expectedDisk: latest.disk.savedData, expectedSource: latest.localSource)
        precondition(peer.main?.source == "accepted merge", "Accepted merges must synchronize peer buffers")
        precondition(peer.isDirty && project.isDirty)
        let disk = try String(contentsOf: main, encoding: .utf8)
        precondition(disk == "disk two", "Merging does not implicitly save")
        print("PASS: frozen conflict snapshots, concurrent local-edit protection and merged-text synchronization")
    }

    @MainActor
    static func checkSymlinkReplacement(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("link-review")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let main = root.appendingPathComponent("main.typ")
        let outside = temporary.appendingPathComponent("private.typ")
        try Data("original".utf8).write(to: main)
        try Data("outside content".utf8).write(to: outside)
        let project = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("link-recovery"))
        try FileManager.default.removeItem(at: main)
        try FileManager.default.createSymbolicLink(at: main, withDestinationURL: outside)
        try project.reconcileExternalChanges()
        precondition(project.main?.source == "original", "Polling must not import a substituted symlink target")
        precondition(project.unavailableFiles[main] != nil)
        print("PASS: external symlink substitution retains the original buffer")
    }

    @MainActor
    static func checkReferenceSynchronization(in temporary: URL) throws {
        let root = temporary.appendingPathComponent("reference-review")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let main = root.appendingPathComponent("main.typ")
        let child = root.appendingPathComponent("child.typ")
        try Data("#include \"child.typ\"".utf8).write(to: main)
        try Data("saved".utf8).write(to: child)
        let project = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("reference-recovery"))
        let peer = try ProjectWorkspace(root: root, recoveryDirectory: temporary.appendingPathComponent("reference-peer"))
        try project.open(child)
        project.edit("unsaved child", at: child)
        precondition(ProjectEdits.snapshots(in: root)[child.path] == "unsaved child",
                     "Standalone compilation must include dirty project buffers")
        try project.move(child, to: root.appendingPathComponent("renamed.typ"))
        precondition(peer.main?.source == "#include \"renamed.typ\"",
                     "Reference rewrites must reach other windows viewing the referencing file")
        print("PASS: dirty project snapshots and reference rewrite synchronization")
    }

}
