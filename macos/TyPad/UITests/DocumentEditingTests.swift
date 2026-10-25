import XCTest

final class DocumentEditingTests: XCTestCase {
    func testNewDocumentSupportsEditingUndoAndRedo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES"]
        app.launch()
        defer { app.terminate() }

        // DocumentGroup can initially show the system document picker.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        let editor = app.textViews["typst.source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "New must create a document editor")
        let original = try XCTUnwrap(editor.value as? String)
        XCTAssertTrue(original.contains("= Untitled"), "The new document comes from the Rust service")

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
