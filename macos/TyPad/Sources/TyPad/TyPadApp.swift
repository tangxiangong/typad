import AppKit
import SwiftUI

@main
struct TyPadApp: App {
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Welcome to TyPad", id: "welcome") {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        DocumentGroup(newDocument: TypstDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            TextEditingCommands()
            CommandGroup(after: .windowArrangement) {
                Button("Show Welcome Window") { openWindow(id: "welcome") }
                    .keyboardShortcut("t", modifiers: [.control, .command])
            }
            CommandGroup(after: .textEditing) {
                Button("Find…") {
                    let item = NSMenuItem()
                    item.tag = NSTextFinder.Action.showFindInterface.rawValue
                    NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}
