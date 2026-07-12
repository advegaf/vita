import XCTest

/// M39 card-navigation behaviors, verified against the REAL app (demo seed):
/// the header icon picker is the ONLY navigation (the glass tab bar is gone);
/// the card still expands from a passive-zone drag; the card survives dismiss
/// attempts; Chat's keyboard expands the card (and the faded header's picker
/// is not a target while expanded).
final class CardNavUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_VIAL_DEMO"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
    }

    /// Slow upward drag from a PASSIVE card zone (the hero card — not a button;
    /// drags that start on pressable controls belong to the control).
    private func dragCardUp(fromY y: CGFloat = 0.45) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: y))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func testSwitcherMenuChangesViews() {
        app.launch()
        let switcher = app.buttons["Switch view"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "the \u{21d5} switcher should sit on the photo header")
        switcher.tap()
        sleep(1)
        let stack = app.buttons.matching(NSPredicate(format: "label == 'Stack'")).allElementsBoundByIndex
            .first(where: { $0.isHittable })
        XCTAssertNotNil(stack, "menu should offer Stack")
        stack?.tap()
        XCTAssertTrue(app.buttons["Add a peptide"].waitForExistence(timeout: 5),
                      "menu pick should switch the card to Stack")
    }

    func testCardExpandsFromContentDragAndPickerFadesOut() {
        app.launch()
        let logDose = app.buttons["Log dose"]
        XCTAssertTrue(logDose.waitForExistence(timeout: 10))
        sleep(1)
        let yBefore = logDose.frame.minY

        dragCardUp()
        sleep(1)
        let yAfter = app.buttons["Log dose"].frame.minY
        XCTAssertLessThan(yAfter, yBefore - 100,
                          "a passive-zone drag should expand the card (\(yBefore) -> \(yAfter))")

        // The header (and its switcher) fades out at the expanded detent.
        let switcher = app.buttons["Switch view"]
        XCTAssertFalse(switcher.isHittable, "the faded header switcher must not be a target while expanded")
    }

    func testCardCannotBeDismissed() {
        app.launch()
        XCTAssertTrue(app.buttons["Log dose"].waitForExistence(timeout: 10))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(1)
        XCTAssertTrue(app.buttons["Log dose"].exists, "the card must never dismiss")
    }

    /// The card does NOT jump detents for the keyboard (the sheet controller
    /// drops detent changes during keyboard presentation — verified; the system
    /// keeps the input above the keyboard instead). The visible header stays
    /// usable while typing.
    func testChatKeyboardTypingWorksAndHeaderStaysUsable() {
        app.launchEnvironment["VITA_TAB"] = "chat"
        app.launch()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        sleep(1)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard should appear")
        XCTAssertTrue(app.buttons["Switch view"].isHittable,
                      "the header switcher stays available while typing at rest")
        input.typeText("hi")
        app.buttons["Send"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'hi'")).firstMatch.exists)
    }
}
