import PDFKit
import SwiftUI

enum PreviewScale: String, CaseIterable {
    case fit = "Fit Page"
    case actual = "Actual Size"
    case large = "150%"
}

struct PDFPreview: NSViewRepresentable {
    let data: Data
    let revision: UInt64
    let scale: PreviewScale

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.setAccessibilityLabel(String(localized: "Typeset PDF preview"))
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if context.coordinator.revision != revision, context.coordinator.data != data {
            // Keep the last rendered frame visible while PDFKit replaces its tiled layers.
            // The cover belongs to this PDFView and never intercepts input.
            let cover = context.coordinator.cover(view)
            let destination = view.currentDestination
            let oldPage = destination?.page.flatMap { view.document?.index(for: $0) } ?? 0
            let oldScale = view.scaleFactor
            let wasAuto = view.autoScales
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            view.document = PDFDocument(data: data)
            if let document = view.document, document.pageCount > 0,
               let page = document.page(at: min(oldPage, document.pageCount - 1)) {
                if let destination {
                    view.go(to: PDFDestination(page: page, at: destination.point))
                } else {
                    view.go(to: page)
                }
            }
            if context.coordinator.revision != nil, !wasAuto {
                view.autoScales = false
                view.scaleFactor = oldScale
            }
            view.layoutDocumentView()
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            CATransaction.commit()
            context.coordinator.revision = revision
            context.coordinator.data = data
            DispatchQueue.main.async { [weak view, weak cover] in
                view?.displayIfNeeded()
                // Let PDFKit's scheduled tile update finish before exposing the new frame.
                DispatchQueue.main.async { cover?.removeFromSuperview() }
            }
        }
        if context.coordinator.scale != scale {
            switch scale {
            case .fit: view.autoScales = true
            case .actual: view.autoScales = false; view.scaleFactor = 1
            case .large: view.autoScales = false; view.scaleFactor = 1.5
            }
            context.coordinator.scale = scale
        }
    }

    final class Coordinator {
        var data: Data?
        var revision: UInt64?

        func cover(_ view: PDFView) -> NSView? {
            guard view.document != nil, view.window != nil,
                  let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let image = NSImage(size: view.bounds.size)
            image.addRepresentation(bitmap)
            let cover = PreviewCover(frame: view.bounds)
            cover.image = image
            cover.imageScaling = .scaleAxesIndependently
            cover.autoresizingMask = [.width, .height]
            view.addSubview(cover, positioned: .above, relativeTo: nil)
            return cover
        }
        var scale: PreviewScale?
    }
}

private final class PreviewCover: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
