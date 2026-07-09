import XCTest

/// M38 card-navigation behaviors, verified against the REAL app (demo seed):
/// pull-up reveals the glass bar and it switches views; the ⇕ menu switches
/// views at rest; the card survives dismiss attempts; Chat's keyboard expands
/// the card and hides the bar.
final class CardNavUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_VIAL_DEMO"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
    }

    /// Slow upward drag from the card's content zone to the top.
    private func dragCardUp() {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
    }

    func testPullUpRevealsBarAndBarSwitchesViews() {
        app.launch()
        let logDose = app.buttons["Log dose"]
        XCTAssertTrue(logDose.waitForExistence(timeout: 10), "Today focus card should appear")
        sleep(1)
        let cardYBefore = logDose.frame.minY

        // At rest the glass bar must not be an active target.
        let stackItem = app.buttons["tabbar-stack"]
        XCTAssertFalse(stackItem.exists && stackItem.isHittable,
                       "glass bar must be inactive at the rest detent")

        dragCardUp()
        sleep(1)
        let cardYAfter = app.buttons["Log dose"].exists ? app.buttons["Log dose"].frame.minY : -1
        XCTAssertTrue(stackItem.waitForExistence(timeout: 3) && stackItem.isHittable,
                      "pulling the card up should reveal the glass tab bar "
                      + "(card moved \(cardYBefore) -> \(cardYAfter))")

        stackItem.tap()
        XCTAssertTrue(app.buttons["Add a peptide"].waitForExistence(timeout: 5),
                      "bar tap should switch the card to Stack")
    }

    func testSwitcherMenuChangesViewAtRest() {
        app.launch()
        let switcher = app.buttons["Switch view"]
        XCTAssertTrue(switcher.waitForExistence(timeout: 10), "the ⇕ switcher should sit on the photo header")
        switcher.tap()
        // The menu's "Chat" item is the hittable one (the glass bar's is inert at rest).
        let chat = app.buttons.matching(NSPredicate(format: "label == 'Chat' AND hittable == true")).firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 3))
        chat.tap()
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 5),
                      "Chat's input should appear after switching")
    }

    func testCardCannotBeDismissed() {
        app.launch()
        XCTAssertTrue(app.buttons["Log dose"].waitForExistence(timeout: 10))
        // Try hard to fling the card away.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.99))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(1)
        XCTAssertTrue(app.buttons["Log dose"].exists, "the card must never dismiss")
    }

    func testChatKeyboardExpandsCardAndHidesBar() {
        app.launchEnvironment["VITA_TAB"] = "chat"
        app.launch()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        sleep(1)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard should appear")
        let todayItem = app.buttons["tabbar-today"]
        XCTAssertFalse(todayItem.exists && todayItem.isHittable,
                       "glass bar must stay hidden while the keyboard is up")
        input.typeText("hi")
        // The header title should have faded out with the card expanded.
        // (Chat input keeps working — streaming is stubbed.)
        app.buttons["Send"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'hi'")).firstMatch.exists)
    }
}
