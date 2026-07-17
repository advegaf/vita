import XCTest

/// M40 floating tab bar behaviors against the real app (demo seed): the
/// black-pill bar switches views, hides while the keyboard is up, and the
/// VITA_TAB deep-link flag still routes.
@MainActor
final class TabBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_VIAL_DEMO"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
    }

    func testBarSwitchesViews() {
        app.launch()
        let stack = app.buttons["tab-stack"]
        XCTAssertTrue(stack.waitForExistence(timeout: 10), "floating bar should be present")
        stack.tap()
        XCTAssertTrue(app.buttons["Add a peptide"].waitForExistence(timeout: 5),
                      "bar tap should switch to Stack")
        app.buttons["tab-diary"].tap()
        XCTAssertTrue(app.staticTexts["Diary"].waitForExistence(timeout: 5),
                      "bar tap should switch to Diary")
        app.buttons["tab-today"].tap()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 5),
                      "bar tap should switch back to Today regardless of dose state")
    }

    func testTabSelectionHasNoVerticalDrift() {
        app.launch()

        let stackTab = app.buttons["tab-stack"]
        XCTAssertTrue(stackTab.waitForExistence(timeout: 10))
        stackTab.tap()

        let addButton = app.buttons["Add a peptide"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5), "Stack should be ready immediately")
        let firstY = addButton.frame.minY
        sleep(1)
        XCTAssertEqual(addButton.frame.minY, firstY, accuracy: 1,
                       "Stack content must not settle vertically after tab selection")

        let initial = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: initial)
        attachment.name = "tab-selection-stack-settled"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Captures mid-flight frames of the Today -> Chat pill glide so the equal-slot
    /// contract can be reviewed visually: icons must stay stationary and the bar's
    /// edges must not move while the ink pill travels to the end slot.
    func testTabSwitchPillGlideFrames() {
        app.launch()
        let chat = app.buttons["tab-chat"]
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        let barWidthBefore = chat.frame // slot frame before the switch
        chat.tap()
        for i in 0..<4 {
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "glide-frame-\(i)"
            shot.lifetime = .keepAlways
            add(shot)
            usleep(90_000)
        }
        // The slot itself must not have moved: fixed slots, constant bar width.
        XCTAssertEqual(chat.frame.minX, barWidthBefore.minX, accuracy: 1,
                       "Chat slot must be stationary; only the pill may travel")
        XCTAssertEqual(chat.frame.width, barWidthBefore.width, accuracy: 1,
                       "Slot width must not change on selection")
    }

    func testKeyboardHidesBar() {
        app.launchEnvironment["VITA_TAB"] = "chat"
        app.launch()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), "VITA_TAB=chat should land on Chat")
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard should appear")
        sleep(1)
        // Only meaningful when the SOFTWARE keyboard is actually on screen — a
        // hardware-keyboard sim shows only the input assistant strip, so
        // keyboardWillShow never fires and the bar rightly stays.
        if app.keyboards.firstMatch.frame.height > 150 {
            let bars = app.buttons.matching(identifier: "tab-today").allElementsBoundByIndex
            XCTAssertTrue(bars.allSatisfy { !$0.isHittable }, "bar must hide while typing")
        }
        input.typeText("hi")
        app.buttons["Send"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'hi'")).firstMatch.exists)
    }
}
