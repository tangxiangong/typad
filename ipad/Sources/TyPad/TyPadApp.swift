import SwiftUI

@main
struct TyPadIPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TypstDocument()) { file in
            IPadEditorView(document: file.$document, fileURL: file.fileURL)
        }
    }
}
