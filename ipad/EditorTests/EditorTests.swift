import XCTest
import SwiftUI
import UIKit
@testable import EditorTestHost

@MainActor
final class EditorTests: XCTestCase {
    @MainActor private final class Source {
        var text: String
        init(_ text: String) { self.text = text }
        var binding: Binding<String> { Binding(get: { self.text }, set: { self.text = $0 }) }
    }

    private var window: UIWindow!
    private var previousRoot: UIViewController?
    private var originalClipboard: [[String: Any]] = []
    private var testClipboardChange: Int?
    private var testClipboardItems: [[String: Any]]?

    override func setUp() async throws {
        window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first { $0.isKeyWindow })
        previousRoot = window.rootViewController
        testClipboardChange = nil
        testClipboardItems = nil
    }

    override func tearDown() async throws {
        if testClipboardChange != nil, ownsClipboard {
            UIPasteboard.general.setItems(originalClipboard, options: [.localOnly: true])
        }
        window.rootViewController = previousRoot
        window = nil
        previousRoot = nil
    }

    private func show(_ source: Source, _ session: IPadEditorSession) async throws -> UITextView {
        let host = UIHostingController(rootView: IPadSourceEditor(source: source.binding, session: session))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        for _ in 0..<30 where session.view == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        let view = try XCTUnwrap(session.view)
        // Flush the representable's asynchronous selection/offset restoration.
        await Task.yield()
        XCTAssertTrue(view.becomeFirstResponder())
        return view
    }

    private var ownsClipboard: Bool {
        guard let expected = testClipboardChange else { return false }
        return UIPasteboard.general.changeCount == expected ||
            (testClipboardItems.map { NSArray(array: UIPasteboard.general.items).isEqual(to: $0) } ?? false)
    }

    private func paste(_ text: String, into view: UITextView) async throws {
        if testClipboardChange == nil {
            // Snapshot immediately before the first write, after focus/clipboard synchronization.
            originalClipboard = UIPasteboard.general.items
        } else if !ownsClipboard {
            XCTFail("Clipboard changed outside the test; preserving the new contents")
            throw CocoaError(.userCancelled)
        }
        UIPasteboard.general.setItems([["public.utf8-plain-text": Data(text.utf8)]], options: [.localOnly: true])
        testClipboardChange = UIPasteboard.general.changeCount
        testClipboardItems = UIPasteboard.general.items
        view.paste(nil) // UIKit's actual Paste action, without synthetic keyboard events.
        for _ in 0..<50 {
            await Task.yield()
            if view.text.contains(text) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("UIKit paste did not insert the fixture")
    }

    func testConsecutivePasteUndoRedoAndTabIsolation() async throws {
        let a = Source("A\n"), b = Source("B\n")
        let sessionA = IPadEditorSession(), sessionB = IPadEditorSession()
        let viewA = try await show(a, sessionA)
        viewA.selectedRange = NSRange(location: 2, length: 0)
        let first = "中文 English $1 + 2 = 3$\n"
        let second = "第二次 🧪 e\u{301}\n"
        try await paste(first, into: viewA)
        try await paste(second, into: viewA)
        XCTAssertEqual(a.text, "A\n" + first + second)
        let viewB = try await show(b, sessionB)
        XCTAssertFalse(try XCTUnwrap(viewB.undoManager).canUndo)
        viewB.selectedRange = NSRange(location: 2, length: 0)
        try await paste("B only\n", into: viewB)
        let historyB = try XCTUnwrap(viewB.undoManager)
        historyB.undo()
        XCTAssertEqual(b.text, "B\n")
        XCTAssertEqual(a.text, "A\n" + first + second)
        historyB.redo()
        XCTAssertEqual(b.text, "B\nB only\n")

        let restoredA = try await show(a, sessionA)
        XCTAssertTrue(restoredA === viewA)
        let historyA = try XCTUnwrap(restoredA.undoManager)
        historyA.undo()
        XCTAssertEqual(a.text, "A\n" + first)
        historyA.undo()
        XCTAssertEqual(a.text, "A\n")
        XCTAssertFalse(historyA.canUndo)
        XCTAssertEqual(b.text, "B\nB only\n")
        historyA.redo()
        XCTAssertEqual(a.text, "A\n" + first)
        historyA.redo()
        XCTAssertEqual(a.text, "A\n" + first + second)
        XCTAssertFalse(historyA.canRedo)
    }

    func testReplacementSelectionAndRedoInvalidation() async throws {
        let source = Source("start 中文 🧪 end")
        let view = try await show(source, IPadEditorSession())
        let original = source.text
        let selection = (original as NSString).range(of: "中文 🧪")
        view.selectedRange = selection
        try await paste("替换 English", into: view)
        XCTAssertEqual(source.text, "start 替换 English end")
        let history = try XCTUnwrap(view.undoManager)
        history.undo()
        XCTAssertEqual(source.text, original)
        XCTAssertEqual(view.selectedRange, selection)
        history.redo()
        XCTAssertEqual(source.text, "start 替换 English end")
        history.undo()
        try await paste("新分支", into: view)
        XCTAssertEqual(source.text, "start 新分支 end")
        XCTAssertFalse(history.canRedo)
    }

    func testEmptyDocumentUndoRedoPreservesTypography() async throws {
        let source = Source("")
        let view = try await show(source, IPadEditorSession())
        let font = try XCTUnwrap(view.font)
        let color = try XCTUnwrap(view.textColor)
        try await paste("中文 English", into: view)
        let history = try XCTUnwrap(view.undoManager)
        history.undo()
        XCTAssertEqual(source.text, "")
        history.redo()
        XCTAssertEqual(source.text, "中文 English")
        XCTAssertEqual(view.textStorage.attribute(.font, at: 0, effectiveRange: nil) as? UIFont, font)
        XCTAssertEqual(view.textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor, color)
        XCTAssertEqual(view.typingAttributes[.font] as? UIFont, font)
    }

    func testTextInputAPIAndMarkedComposition() async throws {
        let source = Source("")
        let view = try await show(source, IPadEditorSession())
        // UITextInput integration, not a keyboard/IME end-to-end test.
        view.insertText("abc")
        view.insertText("中文🧪")
        XCTAssertEqual(source.text, "abc中文🧪")
        let history = try XCTUnwrap(view.undoManager)
        history.undo()
        XCTAssertEqual(source.text, "abc")
        history.undo()
        XCTAssertEqual(source.text, "")
        history.redo()
        history.redo()
        XCTAssertEqual(source.text, "abc中文🧪")
        view.setMarkedText("拼", selectedRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(source.text, "abc中文🧪", "Uncommitted composition must not reach the source")
        view.insertText("拼音")
        XCTAssertEqual(source.text, "abc中文🧪拼音")
        history.undo()
        XCTAssertEqual(source.text, "abc中文🧪")
        history.redo()
        XCTAssertEqual(source.text, "abc中文🧪拼音")
    }
}
