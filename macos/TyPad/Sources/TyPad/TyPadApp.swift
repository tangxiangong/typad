import AppKit
import SwiftUI

@main
@MainActor
enum TyPadEntryPoint {
    static func main() {
        EditorPreferences.migrate()
        _ = TyPadApplication.shared
        TyPadApp.main()
    }
}

struct TyPadApp: App {
    @NSApplicationDelegateAdaptor(ProjectSessionDelegate.self) private var sessionDelegate
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        Window("Welcome to TyPad", id: "welcome") {
            WelcomeView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Settings { EditorSettingsView() }

        DocumentGroup(newDocument: TypstDocument()) { file in
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            TextEditingCommands()
            CommandGroup(after: .newItem) {
                Button("New Project…") { ProjectDocument.createFolder() }
                Menu("New Project from Template") {
                    ForEach(ProjectTemplate.allCases, id: \.self) { template in
                        Button(LocalizedStringKey(template.rawValue)) { ProjectDocument.createFolder(template: template) }
                    }
                }
                Button("Open Project…") { ProjectDocument.chooseFolder() }
                    .keyboardShortcut("o", modifiers: [.command, .option])
            }
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
