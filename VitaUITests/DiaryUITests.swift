import XCTest

/// M50 regression: the Diary must scroll all the way to its last card. The old
/// NavigationStack { TimelineView { ScrollView } } nesting broke the bottom
/// safe-area inset and pinned the LabsCard under the floating tab bar.
@MainActor
final class DiaryUITests: XCTestCase {

    func testDiaryScrollsToLabsCard() {
        let app = XCUIApplication()
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
        app.launchEnvironment["VITA_DEMO_STACK"] = "1"
        app.launchEnvironment["VITA_DIARY_DEMO"] = "1"
        app.launchEnvironment["VITA_TAB"] = "diary"
        app.launch()

        XCTAssertTrue(app.staticTexts["Diary"].waitForExistence(timeout: 10))
        // Swipe until the Labs card is on screen (a few flicks cover the page).
        let labs = app.staticTexts["Labs."]
        for _ in 0..<6 where !labs.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(labs.waitForExistence(timeout: 3), "Labs card must exist")
        XCTAssertTrue(labs.isHittable,
                      "Labs card must scroll fully clear of the floating tab bar")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "diary-scrolled-to-labs"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
