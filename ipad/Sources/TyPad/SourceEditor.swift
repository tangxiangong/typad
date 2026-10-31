import SwiftUI
import UIKit

struct IPadSourceEditor: UIViewRepresentable {
    @Binding var source: String
    var session: IPadEditorSession? = nil

    func makeCoordinator() -> Coordinator { Coordinator(source: $source, session: session) }

    func makeUIView(context: Context) -> UITextView {
        if let view = session?.view {
            if view.delegate != nil {
                session?.selection = view.selectedRange
                session?.offset = view.contentOffset
            }
            view.delegate = context.coordinator
            DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
                guard let view, let coordinator, view.delegate === coordinator else { return }
                coordinator.session?.restore(view)
            }
            return view
        }
        let view = IPadTextView()
        view.delegate = context.coordinator
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .monospacedSystemFont(ofSize: 16, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .systemBackground
        view.textColor = .label
        view.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.isFindInteractionEnabled = true
        view.keyboardDismissMode = .interactive
        view.accessibilityLabel = String(localized: "Typst source editor")
        view.accessibilityIdentifier = "typst.source-editor"
        view.text = source
        view.resetHistory()
        session?.view = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.source = $source
        // Never replace marked text while the user is composing Chinese or another IME.
        guard view.markedTextRange == nil, !view.text.utf16.elementsEqual(source.utf16) else { return }
        let selection = view.selectedRange
        view.text = source
        let length = (source as NSString).length
        let location = min(selection.location, length)
        view.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
        (view as? IPadTextView)?.resetHistory()
    }

    static func dismantleUIView(_ view: UITextView, coordinator: Coordinator) {
        guard view.delegate === coordinator else { return }
        coordinator.session?.selection = view.selectedRange
        coordinator.session?.offset = view.contentOffset
        view.delegate = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var source: Binding<String>
        let session: IPadEditorSession?
        init(source: Binding<String>, session: IPadEditorSession?) { self.source = source; self.session = session }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            (textView as? IPadTextView)?.recordChange()
            source.wrappedValue = textView.text
        }
        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? IPadTextView)?.recordSelection()
        }
    }
}

@MainActor
final class IPadEditorSession {
    var view: UITextView?
    var selection: NSRange?
    var offset: CGPoint?
    func restore(_ view: UITextView) {
        view.layoutIfNeeded()
        if let selection { view.selectedRange = selection }
        if let offset { view.setContentOffset(offset, animated: false) }
    }
}

@MainActor
final class IPadEditorSessions: ObservableObject {
    private var values: [URL: IPadEditorSession] = [:]
    private let standalone = IPadEditorSession()
    func session(for url: URL?) -> IPadEditorSession {
        guard let url else { return standalone }
        if let value = values[url] { return value }
        let value = IPadEditorSession()
        values[url] = value
        return value
    }
    func retain(_ urls: [URL]) { values = values.filter { urls.contains($0.key) } }
}

/// UITextView's default undo history follows the window; project tabs need separate histories.
/// Record committed text edits in the current tab's history.
private final class IPadTextView: UITextView {
    private struct State {
        var text: String
        var selection: NSRange
        var offset: CGPoint
    }
    private let history = TextUndoManager()
    private var committed: State?
    private var applyingHistory = false
    override var undoManager: UndoManager? { history }

    private var current: State { State(text: text ?? "", selection: selectedRange, offset: contentOffset) }
    func resetHistory() {
        history.resetEdits()
        history.beforeAction = { [weak self] in self?.finishComposition() }
        committed = current
    }
    private func finishComposition() {
        guard markedTextRange != nil else { return }
        unmarkText()
        recordChange()
        delegate?.textViewDidChange?(self)
    }
    func recordSelection() {
        guard !applyingHistory, markedTextRange == nil, committed?.text.utf16.elementsEqual((text ?? "").utf16) == true else { return }
        committed = current
    }
    func recordChange() {
        guard !applyingHistory, markedTextRange == nil else { return }
        let after = current
        if let before = committed, let change = TextChange(from: after.text, to: before.text) {
            register(change, selection: before.selection, offset: before.offset)
        }
        committed = after
    }
    private func register(_ change: TextChange, selection: NSRange, offset: CGPoint) {
        history.recordEdit(withTarget: self, name: String(localized: "Edit")) { view in
            view.restore(change, selection: selection, offset: offset)
        }
    }
    private func restore(_ change: TextChange, selection: NSRange, offset: CGPoint) {
        let inverse = change.inverse(in: text)
        let previousSelection = selectedRange
        let previousOffset = contentOffset
        let attributes = typingAttributes
        applyingHistory = true
        // Empty storage has no attributes to inherit when redo inserts text again.
        textStorage.replaceCharacters(in: change.range,
                                      with: NSAttributedString(string: change.replacement, attributes: attributes))
        selectedRange = selection
        typingAttributes = attributes
        layoutIfNeeded()
        setContentOffset(offset, animated: false)
        committed = current
        applyingHistory = false
        register(inverse, selection: previousSelection, offset: previousOffset)
        delegate?.textViewDidChange?(self)
    }
}
