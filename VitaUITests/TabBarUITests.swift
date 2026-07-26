import XCTest

/// M54 native tab bar behaviors against the real app (demo seed): the system
/// Liquid Glass bar switches views, the VITA_TAB deep-link flag still routes,
/// and chat input stays usable above the bar.
@MainActor
final class TabBarUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_VIAL_DEMO"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
    }

    /// Native bar exposes one button per Tab, labeled with the tab title.
    private func tab(_ title: String) -> XCUIElement {
        let bar = app.tabBars.firstMatch
        if bar.exists { return bar.buttons[title] }
        return app.buttons[title]
    }

    func testBarSwitchesViews() {
        app.launch()
        let stack = tab("Stack")
        XCTAssertTrue(stack.waitForExistence(timeout: 10), "system tab bar should be present")
        stack.tap()
        XCTAssertTrue(app.buttons["Add a peptide"].waitForExistence(timeout: 5),
                      "bar tap should switch to Stack")
        tab("Diary").tap()
        XCTAssertTrue(app.staticTexts["Diary"].waitForExistence(timeout: 5),
                      "bar tap should switch to Diary")
        tab("Today").tap()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 5),
                      "bar tap should switch back to Today regardless of dose state")
    }

    func testTabSelectionHasNoVerticalDrift() {
        app.launch()

        let stackTab = tab("Stack")
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

    /// The system bar owns selection motion now; the contract that remains ours
    /// is stability: the tapped tab's slot must not move or resize on selection.
    func testTabSwitchSlotStaysStationary() {
        app.launch()
        let chat = tab("Chat")
        XCTAssertTrue(chat.waitForExistence(timeout: 10))
        let before = chat.frame
        chat.tap()
        sleep(1)
        XCTAssertEqual(chat.frame.minX, before.minX, accuracy: 2,
                       "Chat slot must be stationary across selection")
        XCTAssertEqual(chat.frame.width, before.width, accuracy: 2,
                       "Slot width must not change on selection")
    }

    func testChatInputUsableAboveBar() {
        app.launchEnvironment["VITA_TAB"] = "chat"
        app.launch()
        let input = app.textFields.firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), "VITA_TAB=chat should land on Chat")
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard should appear")
        input.typeText("hi")
        app.buttons["Send"].firstMatch.tap()
        sleep(2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'hi'")).firstMatch.exists)
    }
}
