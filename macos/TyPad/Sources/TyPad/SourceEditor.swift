import AppKit
import SwiftUI

struct SourceSelection: Equatable {
    let id = UUID()
    let offset: Int
}

/// Retains the native editor while a project tab is inactive, including undo and viewport.
@MainActor
final class SourceEditorSession {
    var scrollView: NSScrollView?
    let undoManager = UndoManager()
    var selectedRanges: [NSValue]?
    var scrollOrigin: NSPoint?
    var selectionID: UUID?

    func capture(_ scroll: NSScrollView) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        selectedRanges = editor.selectedRanges
        scrollOrigin = scroll.contentView.bounds.origin
    }

    func restore(_ scroll: NSScrollView) {
        guard let editor = scroll.documentView as? NSTextView else { return }
        scroll.layoutSubtreeIfNeeded()
        if let container = editor.textContainer { editor.layoutManager?.ensureLayout(for: container) }
        if let selectedRanges { editor.selectedRanges = selectedRanges }
        if let scrollOrigin {
            scroll.contentView.scroll(to: scrollOrigin)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

@MainActor
final class SourceEditorSessions: ObservableObject {
    private var values: [URL: SourceEditorSession] = [:]
    func session(for url: URL) -> SourceEditorSession {
        if let value = values[url] { return value }
        let value = SourceEditorSession()
        values[url] = value
        return value
    }
    func remove(_ url: URL) { values.removeValue(forKey: url) }
}

/// AppKit supplies native undo, IME composition and the standard find/replace bar.
@MainActor
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    let selection: SourceSelection?
    @Binding var cursor: Int
    let replacement: SourceReplacement?
    @ObservedObject var language: LanguageModel
    @Binding var assistanceVisible: Bool
    let requestCompletion: (Int) -> Void
    let acceptCompletion: (WorkerCompletion) -> Void
    var session: SourceEditorSession? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        if let scroll = session?.scrollView, let editor = scroll.documentView as? NSTextView {
            context.coordinator.selectionID = session?.selectionID
            editor.delegate = context.coordinator
            let offset = editor.selectedRange().location
            DispatchQueue.main.async { context.coordinator.parent.cursor = offset }
            return scroll
        }
        let scroll = SourceTextView.scrollableTextView()
        session?.scrollView = scroll
        guard let editor = scroll.documentView as? NSTextView else { return scroll }
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        (editor as? SourceTextView)?.projectUndo = session?.undoManager
        editor.allowsUndo = true
        editor.usesFindBar = true
        editor.isIncrementalSearchingEnabled = true
        editor.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        editor.textColor = .textColor
        editor.backgroundColor = .textBackgroundColor
        editor.textContainerInset = NSSize(width: 4, height: 6)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes[.paragraphStyle] = paragraph
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
        editor.string = text
        context.coordinator.highlight(editor)
        editor.delegate = context.coordinator
        editor.setAccessibilityLabel(String(localized: "Typst source"))
        editor.setAccessibilityIdentifier("typst.source-editor")
        scroll.borderType = .noBorder
        scroll.automaticallyAdjustsContentInsets = false
        scroll.hasVerticalScroller = true
        scroll.verticalRulerView = SourceRuler(scrollView: scroll, editor: editor)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? NSTextView else { return }
        if editor.string != text, !editor.hasMarkedText() {
            let oldSelection = editor.selectedRange()
            editor.string = text
            context.coordinator.highlight(editor)
            (scroll.verticalRulerView as? SourceRuler)?.updateLines()
            editor.setSelectedRange(NSRange(location: min(oldSelection.location, (text as NSString).length), length: 0))
        }
        if let replacement, context.coordinator.replacementID != replacement.id, !editor.hasMarkedText() {
            context.coordinator.replacementID = replacement.id
            let edits = replacement.edits.sorted { $0.start > $1.start }
            let length = (editor.string as NSString).length
            var boundary = length
            let valid = edits.allSatisfy { edit in
                guard edit.start >= 0, edit.length >= 0, edit.start <= boundary,
                      edit.length <= boundary - edit.start else { return false }
                boundary = edit.start
                return true
            }
            if editor.string == replacement.source, valid, !edits.isEmpty {
                DispatchQueue.main.async { [weak editor] in
                    guard let editor, editor.string == replacement.source, !editor.hasMarkedText() else { return }
                    editor.undoManager?.beginUndoGrouping()
                    for edit in edits {
                        editor.insertText(edit.text, replacementRange: NSRange(location: edit.start, length: edit.length))
                    }
                    editor.undoManager?.endUndoGrouping()
                    editor.window?.makeFirstResponder(editor)
                }
            }
        }
        if !context.coordinator.didFocus, editor.window != nil {
            context.coordinator.didFocus = true
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak editor, weak coordinator] in
                guard let editor, let coordinator, editor.delegate === coordinator, editor.window != nil else { return }
                editor.window?.makeFirstResponder(editor)
                coordinator.parent.session?.restore(scroll)
                if let selection = coordinator.pendingSelection {
                    let offset = min(selection.offset, (editor.string as NSString).length)
                    let range = NSRange(location: max(0, offset), length: 0)
                    editor.setSelectedRange(range)
                    editor.scrollRangeToVisible(range)
                }
                coordinator.parent.cursor = editor.selectedRange().location
            }
        }
        context.coordinator.updateAssistance(editor)
        if let selection, context.coordinator.selectionID != selection.id, !editor.hasMarkedText() {
            context.coordinator.selectionID = selection.id
            context.coordinator.pendingSelection = selection
            session?.selectionID = selection.id
            let range = NSRange(location: min(selection.offset, (text as NSString).length), length: 0)
            editor.setSelectedRange(range)
            editor.scrollRangeToVisible(range)
            editor.window?.makeFirstResponder(editor)
        }
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.completionTask?.cancel()
        coordinator.popover.close()
        if let editor = nsView.documentView as? NSTextView, editor.delegate === coordinator {
            coordinator.parent.session?.capture(nsView)
            editor.delegate = nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        var selectionID: UUID?
        var pendingSelection: SourceSelection?
        var replacementID: UUID?
        let popover = CompletionWindow()
        weak var editor: NSTextView?
        var selected = 0
        var labels: [String] = []
        var didFocus = false
        var completionTask: Task<Void, Never>?
        private var eventMonitor: Any?
        init(_ parent: SourceEditor) {
            self.parent = parent
            super.init()
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
                guard let self, self.popover.isShown, event.window !== self.popover else { return event }
                self.popover.close()
                self.parent.assistanceVisible = false
                return event
            }
            NotificationCenter.default.addObserver(self, selector: #selector(deactivate), name: NSApplication.didResignActiveNotification, object: nil)
        }
        deinit {
            if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
            NotificationCenter.default.removeObserver(self)
        }
        @objc private func deactivate() {
            popover.close()
            parent.assistanceVisible = false
        }
        func updateAssistance(_ editor: NSTextView) {
            self.editor = editor
            guard parent.assistanceVisible, !editor.hasMarkedText(), editor.window != nil else {
                if popover.isShown { popover.close() }
                return
            }
            guard !parent.language.busy else { return }
            let next = parent.language.completions.map(\.label)
            if labels != next { selected = 0; labels = next }
            renderPanel()
            let screen = editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil)
            guard let window = editor.window else { return }
            let anchor = editor.convert(window.convertFromScreen(screen), from: nil)
            guard editor.visibleRect.intersects(anchor) else { popover.close(); return }
            popover.show(below: screen, attachedTo: window)
        }
        private func renderPanel() {
            let model = parent.language
            let panel = CompletionPanel(items: model.completions, selected: selected,
                documentation: model.documentation, status: model.status, busy: model.busy) { [weak self] index in
                    self?.accept(index)
                }
            let controller = NSHostingController(rootView: panel)
            popover.contentViewController = controller
            controller.view.layoutSubtreeIfNeeded()
            popover.setContentSize(controller.view.fittingSize)
            if popover.isShown, let editor, let window = editor.window {
                popover.show(below: editor.firstRect(forCharacterRange: editor.selectedRange(), actualRange: nil), attachedTo: window)
            }
        }
        private func accept(_ index: Int) {
            guard parent.language.completions.indices.contains(index), editor?.string == parent.language.source else { return }
            parent.acceptCompletion(parent.language.completions[index])
            popover.close()
        }
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard !textView.hasMarkedText() else { return false }
            if commandSelector == #selector(NSTextView.complete(_:)) {
                parent.requestCompletion(textView.selectedRange().location)
                return true
            }
            guard popover.isShown else { return false }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                popover.close(); return true
            }
            let count = parent.language.completions.count
            guard count > 0 else { return false }
            if commandSelector == #selector(NSResponder.moveDown(_:)) {
                selected = min(count - 1, selected + 1); renderPanel(); return true
            }
            if commandSelector == #selector(NSResponder.moveUp(_:)) {
                selected = max(0, selected - 1); renderPanel(); return true
            }
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                accept(selected); return true
            }
            return false
        }
        func undoManager(for view: NSTextView) -> UndoManager? {
            parent.session?.undoManager ?? view.window?.undoManager
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            editor.needsDisplay = true
            let offset = editor.selectedRange().location
            DispatchQueue.main.async { [weak self] in self?.parent.cursor = offset }
        }
        // Lightweight syntax colors; this does not change the source or undo history.
        func highlight(_ editor: NSTextView) {
            guard !editor.hasMarkedText(), let storage = editor.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            let rules: [(String, NSColor)] = [
                (#"(?m)^={1,6}\s+.*$"#, .systemPurple),
                (#"#[\p{L}_][\p{L}\p{N}_-]*"#, .systemBlue),
                (#"\b[0-9]+(?:\.[0-9]+)?(?:pt|mm|cm|em|%)?"#, .systemOrange),
                (#""(?:[^"\\]|\\.)*""#, .systemRed),
                (#"(?m)//.*$"#, .secondaryLabelColor)
            ]
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: full)
            for (pattern, color) in rules {
                guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                for match in regex.matches(in: editor.string, range: full) {
                    storage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
            storage.endEditing()
            editor.typingAttributes[.foregroundColor] = NSColor.textColor
        }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            editor.needsDisplay = true
            parent.text = editor.string
            highlight(editor)
            completionTask?.cancel()
            let source = editor.string
            let offset = editor.selectedRange().location
            let prefix = (source as NSString).substring(to: min(offset, (source as NSString).length))
            if !editor.hasMarkedText(), prefix.range(of: #"(?:#|\.)[\p{L}_][\p{L}\p{N}_-]*$"#, options: .regularExpression) != nil {
                completionTask = Task { [weak self, weak editor] in
                    do { try await Task.sleep(nanoseconds: 180_000_000) } catch { return }
                    guard let self, let editor, editor.string == source,
                          editor.selectedRange().location == offset, !editor.hasMarkedText() else { return }
                    self.parent.requestCompletion(offset)
                }
            }
            (editor.enclosingScrollView?.verticalRulerView as? SourceRuler)?.updateLines()
        }
    }
}

/// Paint behind the text and selection without changing text attributes or undo history.
@MainActor
final class SourceTextView: NSTextView {
    weak var projectUndo: UndoManager?
    override var undoManager: UndoManager? { projectUndo ?? super.undoManager }
    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard selectedRange().length == 0,
              let manager = layoutManager, let container = textContainer else { return }
        manager.ensureLayout(for: container)
        let length = (string as NSString).length
        let offset = min(selectedRange().location, length)
        let fragment: NSRect
        if offset == length, manager.extraLineFragmentTextContainer != nil {
            fragment = manager.extraLineFragmentRect
        } else if length > 0 {
            let glyph = manager.glyphIndexForCharacter(at: min(offset, length - 1))
            fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        } else {
            fragment = NSRect(x: 0, y: 0, width: 0,
                height: manager.defaultLineHeight(for: font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)))
        }
        let line = NSRect(x: bounds.minX, y: fragment.minY + textContainerOrigin.y,
                          width: bounds.width, height: fragment.height)
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        line.intersection(rect).fill()
    }
}

/// A non-activating suggestion list keeps keyboard input in the source editor.
@MainActor
final class CompletionWindow: NSPanel {
    var isShown: Bool { isVisible }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hasShadow = true
        backgroundColor = .clear
        isOpaque = false
        hidesOnDeactivate = true
        isFloatingPanel = true
    }

    func show(below caret: NSRect, attachedTo owner: NSWindow) {
        let available = owner.screen?.visibleFrame ?? owner.frame
        var point = NSPoint(x: caret.minX - 28, y: caret.minY - frame.height - 2)
        point.x = max(available.minX, min(point.x, available.maxX - frame.width))
        if point.y < available.minY { point.y = caret.maxY + 2 }
        setFrameOrigin(point)
        if parent !== owner { owner.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    override func close() {
        parent?.removeChildWindow(self)
        orderOut(nil)
    }
}
