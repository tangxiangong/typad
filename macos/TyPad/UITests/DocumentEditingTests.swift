import XCTest

final class DocumentEditingTests: XCTestCase {
    func testNewDocumentSupportsEditingUndoAndRedo() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        // Launch now opens the welcome window. Synchronize with the menu before
        // invoking the document command rather than sending keys during startup.
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let fileMenu = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(fileMenu.waitForExistence(timeout: 15))
        fileMenu.click()
        let newDocument = app.menuItems["newDocument:"]
        XCTAssertTrue(newDocument.waitForExistence(timeout: 5))
        XCTAssertTrue(newDocument.isEnabled, "New must be enabled from the welcome window")
        // Keep the keyboard shortcut under test as well as menu availability.
        app.typeKey(.escape, modifierFlags: [])
        app.typeKey("n", modifierFlags: .command)
        let editor = app.textViews["typst.source-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 15), "New must create a document editor\n\(app.debugDescription)")
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
