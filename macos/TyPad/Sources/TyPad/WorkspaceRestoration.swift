import AppKit
import CoreServices
import PDFKit
import SwiftUI

/// AppKit persists divider positions; SwiftUI owns which panes are present.
struct WorkspaceRestoration: NSViewRepresentable {
    let key: String?
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.key = key; view.configure() }

    final class Anchor: NSView {
        var key: String?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configure() }
        func configure() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let key = self.key, let content = self.window?.contentView else { return }
                var index = 0
                func visit(_ view: NSView) {
                    guard !(view is PDFView), !(view is NSScrollView) else { return }
                    if let split = view as? NSSplitView {
                        let name = NSSplitView.AutosaveName("\(key):\(index)")
                        index += 1
                        if split.autosaveName != name { split.autosaveName = name }
                    }
                    for child in view.subviews { visit(child) }
                }
                visit(content)
            }
        }
    }
}

@MainActor
final class ProjectSessionDelegate: NSObject, NSApplicationDelegate {
    private static var terminatingProjects: [String]?
    private static var originalQuitHandler: AEEventHandlerUPP?
    private static var originalQuitRefcon: UnsafeMutableRawPointer?
    private static var ignoresRestoration: Bool { UserDefaults.standard.bool(forKey: "ApplePersistenceIgnoreState") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.observeQuitEvents()
        guard !Self.ignoresRestoration else { return }
        let paths = UserDefaults.standard.stringArray(forKey: "openProjectFolders") ?? []
        for path in paths where FileManager.default.fileExists(atPath: path) {
            ProjectDocument.openFolder(URL(fileURLWithPath: path))
        }
    }
    private static func observeQuitEvents() {
        var handler: AEEventHandlerUPP?
        var refcon: UnsafeMutableRawPointer?
        guard originalQuitHandler == nil,
              AEGetEventHandler(AEEventClass(kCoreEventClass), AEEventID(kAEQuitApplication), &handler, &refcon, false) == noErr,
              let handler else { return }
        originalQuitHandler = handler
        originalQuitRefcon = refcon
        // Dock and session-ending requests enter through Apple Events before SwiftUI's
        // save review. Keep the original handler and all of its reply/suspension behavior.
        let status = AEInstallEventHandler(AEEventClass(kCoreEventClass), AEEventID(kAEQuitApplication), { event, reply, _ in
            MainActor.assumeIsolated {
                ProjectSessionDelegate.beginTermination()
                guard let original = ProjectSessionDelegate.originalQuitHandler else { return OSErr(errAEEventNotHandled) }
                let result = original(event, reply, ProjectSessionDelegate.originalQuitRefcon)
                if result == userCanceledErr { ProjectSessionDelegate.cancelTermination() }
                return result
            }
        }, nil, false)
        if status != noErr { originalQuitHandler = nil }
    }

    static func beginTermination() {
        if terminatingProjects == nil { terminatingProjects = openProjects }
    }
    static func cancelTermination() { terminatingProjects = nil; persist() }

    func applicationWillTerminate(_ notification: Notification) {
        guard !Self.ignoresRestoration else { return }
        UserDefaults.standard.set(Self.terminatingProjects ?? Self.openProjects, forKey: "openProjectFolders")
    }
    private static var openProjects: [String] {
        NSDocumentController.shared.documents.compactMap { ($0 as? ProjectDocument)?.workspace.root?.path }
    }
    static func persist() {
        // Closing documents during quit must not erase the session captured before save review.
        guard !ignoresRestoration, terminatingProjects == nil else { return }
        UserDefaults.standard.set(openProjects, forKey: "openProjectFolders")
    }
}

// SwiftUI reviews and closes edited documents before forwarding termination to its
// delegate. Capture the open projects at the application entry point instead.
@objc(TyPadApplication)
final class TyPadApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        ProjectSessionDelegate.beginTermination()
        super.terminate(sender)
    }
    override func reply(toApplicationShouldTerminate shouldTerminate: Bool) {
        if !shouldTerminate { ProjectSessionDelegate.cancelTermination() }
        super.reply(toApplicationShouldTerminate: shouldTerminate)
    }
}
