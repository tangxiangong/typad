import SwiftUI

@main
struct TyPadIPadApp: App {
    var body: some Scene {
        if #available(iOS 18.0, *) {
            DocumentGroupLaunchScene("TyPad") { IPadLaunchActions() }
        }
        DocumentGroup(newDocument: TypstDocument()) { file in
            IPadEditorView(document: file.$document, fileURL: file.fileURL)
        }
        WindowGroup("Projects", id: "projects") { IPadProjectsView() }
    }
}

@available(iOS 18.0, *)
private struct IPadLaunchActions: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        NewDocumentButton("New document", for: TypstDocument.self)
        Button("Projects") { openWindow(id: "projects") }
    }
}
