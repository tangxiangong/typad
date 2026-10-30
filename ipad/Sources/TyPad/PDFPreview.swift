import PDFKit
import SwiftUI

struct IPadPDFPreview: UIViewRepresentable {
    let data: Data
    let revision: UInt64

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.accessibilityLabel = String(localized: "Typeset PDF preview")
        view.accessibilityIdentifier = "typst.pdf-preview"
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard context.coordinator.revision != revision else { return }
        let destination = view.currentDestination
        let pageIndex = destination?.page.flatMap { view.document?.index(for: $0) } ?? 0
        let scale = view.scaleFactor
        let autoScales = view.autoScales
        view.document = PDFDocument(data: data)
        if let document = view.document, document.pageCount > 0,
           let page = document.page(at: min(pageIndex, document.pageCount - 1)) {
            if let destination { view.go(to: PDFDestination(page: page, at: destination.point)) }
            else { view.go(to: page) }
        }
        if context.coordinator.revision != nil, !autoScales {
            view.autoScales = false
            view.scaleFactor = scale
        }
        context.coordinator.revision = revision
    }

    final class Coordinator { var revision: UInt64? }
}
