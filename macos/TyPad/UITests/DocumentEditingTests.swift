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

        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        editor.typeText("Z")
        let edited = original + "Z"
        waitForValue(edited, in: editor)
        app.typeKey("z", modifierFlags: .command)
        waitForValue(original, in: editor)
        app.typeKey("z", modifierFlags: [.command, .shift])
        waitForValue(edited, in: editor)
    }

    private func waitForValue(_ value: String, in editor: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
