import AppKit
import XCTest

final class DocumentEditingTests: XCTestCase {
    func testNewDocumentSupportsEditingUndoAndRedo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }

        let newDocument = app.buttons["welcome.new-document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.click()
        let editor = app.textViews["typst.source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "New must create a document editor")
        let original = try XCTUnwrap(editor.value as? String)
        XCTAssertEqual(original, "", "New documents start with a blank Typst source")
        XCTAssertTrue(app.descendants(matching: .any)["typst.pdf-preview"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)

        let pasteboard = NSPasteboard.general
        let savedItems = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
        let edited = """
        #set page(width: 150mm, height: 120mm, margin: 12mm)
        中文渲染测试：你好，世界。

        English rendering test: Hello, world.

        $ 1 + 2 = 3 $

        $ x^2 + y^2 = z^2 $
        """
        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.setString(edited, forType: .string))
        let changeCount = pasteboard.changeCount
        defer {
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
                if !savedItems.isEmpty { pasteboard.writeObjects(savedItems) }
            }
        }

        app.textViews["typst.source-editor"].firstMatch.click()
        clickEditAction("Paste", "粘贴", in: app)
        waitForValue(edited, in: app)
        waitForRenderedContent(in: app)
        clickEditAction("Undo", "撤销", in: app)
        waitForValue(original, in: app)
        clickEditAction("Redo", "重做", in: app)
        waitForValue(edited, in: app)
        waitForRenderedContent(in: app)
    }

    private func clickEditAction(_ english: String, _ chinese: String, in app: XCUIApplication) {
        let editMenu = app.menuBars.menuBarItems.matching(
            NSPredicate(format: "title == %@ OR title == %@", "Edit", "编辑")
        ).firstMatch
        XCTAssertTrue(editMenu.waitForExistence(timeout: 5), app.debugDescription)
        editMenu.click()
        let action = app.menuItems.matching(
            NSPredicate(format: "title BEGINSWITH %@ OR title BEGINSWITH %@", english, chinese)
        ).firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertTrue(action.isEnabled)
        action.click()
    }

    private func waitForValue(_ value: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let editor = app.textViews["typst.source-editor"].firstMatch
                return editor.exists && editor.value as? String == value
            }, object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    private func waitForRenderedContent(in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                let preview = app.descendants(matching: .any)["typst.pdf-preview"].firstMatch
                guard preview.exists else { return false }
                let text = ((preview.value as? String) ?? "").filter { !$0.isWhitespace }
                return text.contains("中文渲染测试：你好，世界。")
                    && text.contains("Englishrenderingtest:Hello,world.")
                    && text.contains("1+2=3")
            }, object: app
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, app.debugDescription)
    }
}
