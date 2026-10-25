import SwiftUI

@main
struct TyPadApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: TypstDocument()) { file in
            EditorView(document: file.$document)
        }
    }
}
