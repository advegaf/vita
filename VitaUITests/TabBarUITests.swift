import XCTest

/// M40 floating tab bar behaviors against the real app (demo seed): the
/// black-pill bar switches views, hides while the keyboard is up, and the
/// VITA_TAB deep-link flag still routes.
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
        XCTAssertTrue(app.staticTexts["Your plan today"].waitForExistence(timeout: 5),
                      "bar tap should switch back to Today (greeting header visible)")
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
