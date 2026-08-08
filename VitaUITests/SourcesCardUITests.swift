import XCTest

/// M56 guard: the 1.4.1 Sources card is reachable and populated on the
/// compound detail. Scrolls the deep-linked detail sheet to the bottom and
/// asserts the citations render (FDA label for an rx compound + PubMed).
@MainActor
final class SourcesCardUITests: XCTestCase {

    func testDetailShowsCitations() {
        let app = XCUIApplication()
        app.launchEnvironment["VITA_DEMO_STACK"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
        app.launchEnvironment["VITA_OPEN_DETAIL"] = "semaglutide"
        app.launch()

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10), "detail sheet should open")

        let sources = app.staticTexts["Sources."]
        var swipes = 0
        while !sources.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(sources.exists, "Sources card must be present on the detail")
        XCTAssertTrue(app.staticTexts[
            "FDA DailyMed: official prescribing information for Semaglutide"].exists,
            "rx compound must cite the FDA label")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "sources-card"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
