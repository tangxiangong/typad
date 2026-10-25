import AppKit

/// Line numbers follow text layout, including wrapped lines and the final empty line.
final class SourceRuler: NSRulerView {
    private weak var editor: NSTextView?
    private var starts = [0]
    override var isFlipped: Bool { true }

    init(scrollView: NSScrollView, editor: NSTextView) {
        self.editor = editor
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = editor
        ruleThickness = 34
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        updateLines()
    }
    required init(coder: NSCoder) { fatalError("SourceRuler is created programmatically") }
    deinit { NotificationCenter.default.removeObserver(self) }

    func updateLines() {
        guard let editor else { return }
        starts = [0]
        for (offset, unit) in editor.string.utf16.enumerated() where unit == 10 { starts.append(offset + 1) }
        ruleThickness = max(34, CGFloat(String(starts.count).count) * 8 + 20)
        needsDisplay = true
    }
    @objc private func scrolled() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let editor, let manager = editor.layoutManager, let container = editor.textContainer else { return }
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        let origin = editor.textContainerOrigin
        let visible = editor.visibleRect.offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = manager.glyphRange(forBoundingRect: visible, in: container)
        let first = glyphs.location < manager.numberOfGlyphs ? manager.characterIndexForGlyph(at: glyphs.location) : 0
        var low = 0, high = starts.count
        while low < high {
            let mid = (low + high) / 2
            if starts[mid] <= first { low = mid + 1 } else { high = mid }
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let length = (editor.string as NSString).length
        for line in max(0, low - 1)..<starts.count {
            let start = starts[line]
            let fragment: NSRect
            if start < length {
                let glyph = manager.glyphIndexForCharacter(at: start)
                fragment = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else { fragment = manager.extraLineFragmentRect }
            let point = convert(NSPoint(x: 0, y: fragment.minY + origin.y), from: editor)
            if point.y > bounds.maxY { break }
            if point.y + fragment.height < bounds.minY { continue }
            let number = "\(line + 1)" as NSString
            number.draw(at: NSPoint(x: ruleThickness - number.size(withAttributes: attributes).width - 10, y: point.y + 3), withAttributes: attributes)
        }
    }
}
