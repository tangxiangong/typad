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

    func testNewShortcutWorksAcrossDocumentWindowsAndAfterWelcomeCloses() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ApplePersistenceIgnoreState", "YES",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }

        let welcome = app.windows["welcome"]
        XCTAssertTrue(welcome.waitForExistence(timeout: 15))
        app.menuBars.menuBarItems["File"].click()
        XCTAssertEqual(app.menuItems.matching(identifier: "New").count, 1,
                       "There must be exactly one New command")
        app.typeKey(.escape, modifierFlags: [])

        let editors = app.textViews.matching(identifier: "typst.source-editor")
        for expectedCount in 1...2 {
            app.typeKey("n", modifierFlags: .command)
            let created = XCTNSPredicateExpectation(
                predicate: NSPredicate { _, _ in editors.count == expectedCount }, object: nil
            )
            XCTAssertEqual(XCTWaiter.wait(for: [created], timeout: 15), .completed)
        }

        welcome.buttons["_XCUI:CloseWindow"].click()
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: welcome
        )
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        app.activate()
        app.typeKey("n", modifierFlags: .command)
        let created = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in editors.count == 3 }, object: nil
        )
        XCTAssertEqual(XCTWaiter.wait(for: [created], timeout: 15), .completed)
    }

    private func waitForValue(_ value: String, in editor: XCUIElement) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: editor
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }
}
