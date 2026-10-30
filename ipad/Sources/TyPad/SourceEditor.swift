import SwiftUI
import UIKit

struct IPadSourceEditor: UIViewRepresentable {
    @Binding var source: String

    func makeCoordinator() -> Coordinator { Coordinator(source: $source) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
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
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.source = $source
        // Never replace marked text while the user is composing Chinese or another IME.
        guard view.markedTextRange == nil, view.text != source else { return }
        let selection = view.selectedRange
        view.text = source
        let length = (source as NSString).length
        let location = min(selection.location, length)
        view.selectedRange = NSRange(location: location, length: min(selection.length, length - location))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var source: Binding<String>
        init(source: Binding<String>) { self.source = source }
        func textViewDidChange(_ textView: UITextView) {
            guard textView.markedTextRange == nil else { return }
            source.wrappedValue = textView.text
        }
    }
}
