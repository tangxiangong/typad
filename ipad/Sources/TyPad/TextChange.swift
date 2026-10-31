import Foundation

/// A reversible UTF-16 edit; keeps undo memory proportional to the changed text.
struct TextChange {
    let range: NSRange
    let replacement: String

    init(range: NSRange, replacement: String) {
        self.range = range
        self.replacement = replacement
    }

    init?(from source: String, to target: String) {
        let source = source as NSString
        let target = target as NSString
        var prefix = 0
        while prefix < min(source.length, target.length), source.character(at: prefix) == target.character(at: prefix) {
            prefix += 1
        }
        guard prefix != source.length || prefix != target.length else { return nil }
        // A shared high surrogate is not a complete scalar; include it in the edit.
        if prefix > 0, (prefix < source.length && Self.isLowSurrogate(source.character(at: prefix)))
            || (prefix < target.length && Self.isLowSurrogate(target.character(at: prefix))) { prefix -= 1 }
        var suffix = 0
        while suffix < min(source.length, target.length) - prefix,
              source.character(at: source.length - suffix - 1) == target.character(at: target.length - suffix - 1) {
            suffix += 1
        }
        if suffix > 0, Self.isLowSurrogate(source.character(at: source.length - suffix))
            || Self.isLowSurrogate(target.character(at: target.length - suffix)) { suffix -= 1 }
        range = NSRange(location: prefix, length: source.length - prefix - suffix)
        replacement = target.substring(with: NSRange(location: prefix, length: target.length - prefix - suffix))
    }

    func inverse(in source: String) -> TextChange {
        TextChange(range: NSRange(location: range.location, length: (replacement as NSString).length),
                   replacement: (source as NSString).substring(with: range))
    }

    func applying(to source: String) -> String {
        (source as NSString).replacingCharacters(in: range, with: replacement)
    }

    private static func isLowSurrogate(_ value: unichar) -> Bool { (0xdc00...0xdfff).contains(value) }
}

/// UIKit may leave native groups open. Keep app edits in a separate, explicitly grouped engine.
final class TextUndoManager: UndoManager {
    private let edits = UndoManager()
    var beforeAction: (() -> Void)?

    override init() {
        super.init()
        edits.groupsByEvent = false
        levelsOfUndo = 1 // Native registrations are unused; retain at most their latest group.
    }
    override var canUndo: Bool { edits.canUndo }
    override var canRedo: Bool { edits.canRedo }
    override var undoActionName: String { edits.undoActionName }
    override var redoActionName: String { edits.redoActionName }

    func recordEdit<T: AnyObject>(withTarget target: T, name: String, handler: @escaping (T) -> Void) {
        let startedGroup = edits.groupingLevel == 0
        if startedGroup { edits.beginUndoGrouping() }
        edits.registerUndo(withTarget: target, handler: handler)
        edits.setActionName(name)
        if startedGroup { edits.endUndoGrouping() }
        NotificationCenter.default.post(name: .NSUndoManagerDidCloseUndoGroup, object: self)
    }
    func resetEdits() {
        edits.removeAllActions()
        super.removeAllActions()
        NotificationCenter.default.post(name: .NSUndoManagerCheckpoint, object: self)
    }
    override func undo() {
        beforeAction?()
        guard edits.canUndo else { return }
        edits.undo()
        NotificationCenter.default.post(name: .NSUndoManagerDidUndoChange, object: self)
    }
    override func undoNestedGroup() { undo() }
    override func redo() {
        beforeAction?()
        guard edits.canRedo else { return }
        edits.redo()
        NotificationCenter.default.post(name: .NSUndoManagerDidRedoChange, object: self)
    }
}
