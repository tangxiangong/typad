import PDFKit
import SwiftUI

enum PreviewScale: String, CaseIterable {
    case fit = "Fit Page"
    case width = "Fit Width"
    case actual = "Actual Size"
    case large = "150%"
}

enum PreviewPages: String, CaseIterable {
    case continuous = "Continuous", single = "Single Page", two = "Two Pages"
    var mode: PDFDisplayMode {
        switch self { case .continuous: return .singlePageContinuous; case .single: return .singlePage; case .two: return .twoUpContinuous }
    }
}

struct PDFPageRequest {
    let id = UUID()
    let page: Int
}

struct PDFPreview: NSViewRepresentable {
    let data: Data
    let revision: UInt64
    let scale: PreviewScale
    let pages: PreviewPages
    @Binding var requestedPage: PDFPageRequest?
    let storageKey: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PDFView {
        let view = WidthPDFView()
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.displaysPageBreaks = true
        view.autoScales = true
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.group)
        view.setAccessibilityLabel(String(localized: "Typeset PDF preview"))
        view.setAccessibilityIdentifier("typst.pdf-preview")
        context.coordinator.observe(view, key: storageKey)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        context.coordinator.key = storageKey
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        if view.displayMode != pages.mode { view.displayMode = pages.mode }
        (view as? WidthPDFView)?.fitWidth = scale == .width
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
            view.setAccessibilityValue(view.document?.string ?? "")
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
            case .width: (view as? WidthPDFView)?.resizeToWidth()
            case .actual: view.autoScales = false; view.scaleFactor = 1
            case .large: view.autoScales = false; view.scaleFactor = 1.5
            }
            context.coordinator.scale = scale
        }
        if !context.coordinator.restored, let document = view.document {
            context.coordinator.restored = true
            if let key = storageKey, let state = UserDefaults.standard.dictionary(forKey: key),
               let index = state["page"] as? Int, let page = document.page(at: max(0, min(index, document.pageCount - 1))) {
                if let zoom = state["zoom"] as? Double, state["auto"] as? Bool == false, scale != .width {
                    view.autoScales = false; view.scaleFactor = zoom
                }
                view.go(to: PDFDestination(page: page, at: CGPoint(x: state["x"] as? Double ?? 0, y: state["y"] as? Double ?? 0)))
            }
        }
        context.coordinator.observeScroll(view)
        if let request = requestedPage, context.coordinator.pageRequestID != request.id {
            context.coordinator.pageRequestID = request.id
            if request.page > 0, let page = view.document?.page(at: request.page - 1) { view.go(to: page) }
            DispatchQueue.main.async {
                if requestedPage?.id == request.id { requestedPage = nil }
            }
        }
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) { coordinator.persist(view) }

    final class Coordinator {
        var updating = false
        var restored = false
        var pageRequestID: UUID?
        var key: String?
        var observers: [NSObjectProtocol] = []
        weak var clip: NSClipView?
        var scrollObserver: NSObjectProtocol?
        deinit {
            for token in observers { NotificationCenter.default.removeObserver(token) }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
        }
        func observe(_ view: PDFView, key: String?) {
            self.key = key
            for name in [Notification.Name.PDFViewPageChanged, .PDFViewScaleChanged] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: view, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        if let self, let view, !self.updating { self.persist(view) }
                    }
                })
            }
        }
        func observeScroll(_ view: PDFView) {
            guard let content = view.documentView?.enclosingScrollView?.contentView, content !== clip else { return }
            if let scrollObserver { NotificationCenter.default.removeObserver(scrollObserver) }
            clip = content
            content.postsBoundsChangedNotifications = true
            scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                object: content, queue: .main) { [weak self, weak view] _ in
                MainActor.assumeIsolated {
                    if let self, let view, !self.updating { self.persist(view) }
                }
            }
        }
        func persist(_ view: PDFView) {
            guard let key, let destination = view.currentDestination, let page = destination.page,
                  let index = view.document?.index(for: page), index != NSNotFound else { return }
            UserDefaults.standard.set(["page": index, "x": Double(destination.point.x),
                                       "y": Double(destination.point.y), "zoom": Double(view.scaleFactor), "auto": view.autoScales], forKey: key)
        }
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

private final class WidthPDFView: PDFView {
    var fitWidth = false
    override func layout() { super.layout(); if fitWidth { resizeToWidth() } }
    func resizeToWidth() {
        guard bounds.width > 20, let page = currentPage ?? document?.page(at: 0) else { return }
        let box = page.bounds(for: displayBox)
        let rotated = abs(page.rotation) % 180 != 0
        let width = rotated ? box.height : box.width
        guard width > 0 else { return }
        let columns: CGFloat = displayMode == .twoUpContinuous || displayMode == .twoUp ? 2 : 1
        let factor = (bounds.width - 20) / (columns * width)
        autoScales = false
        if abs(scaleFactor - factor) > 0.001 { scaleFactor = factor }
    }
}
