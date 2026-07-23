import XCTest

/// M53 regression: tapping a dose-reminder notification must open the app
/// WITHOUT crashing, both when the tap cold-launches the process and when it
/// resumes a backgrounded one. The M47 fix gated only on scenePhase, which
/// reports .active before the root view is in the window on cold launch; these
/// tests drive the real Springboard banner, which no unit test can reach.
@MainActor
final class NotificationTapUITests: XCTestCase {

    private var app: XCUIApplication!
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_DEMO_STACK"] = "1"
        app.launchEnvironment["VITA_CLAUDE_STUB"] = "1"
        app.launchEnvironment["VITA_NOTIF_TEST_SECONDS"] = "15"
    }

    /// First launch may show the notification-permission alert; allow it.
    private func allowNotificationsIfAsked() {
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }

    /// The delivered banner on Springboard. Identifier varies by iOS release,
    /// so match the short-look view first and fall back to a label search.
    private func banner() -> XCUIElement {
        let shortLook = springboard.otherElements["Notification"].firstMatch
        if shortLook.exists { return shortLook }
        let byClass = springboard.otherElements["NotificationShortLookView"].firstMatch
        if byClass.exists { return byClass }
        return springboard.otherElements
            .matching(NSPredicate(format: "label CONTAINS[c] 'time'")).firstMatch
    }

    private func waitForBannerAndTap() {
        let deadline = Date().addingTimeInterval(40)
        while Date() < deadline {
            let b = banner()
            if b.exists && b.isHittable { b.tap(); return }
            RunLoop.current.run(until: Date().addingTimeInterval(1))
        }
        XCTFail("dose-reminder banner never appeared on Springboard")
    }

    private func assertAppAliveWithDetail() {
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10),
                      "tap must foreground the app")
        // The deep-linked compound detail sheet shows a Done toolbar button.
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10),
                      "notification tap should present the compound detail sheet")
        // The crash reproduces as an immediate termination: hold a beat and
        // re-assert the process is still foreground and responsive.
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground, "app must survive the presentation")
    }

    func testColdLaunchNotificationTapOpensDetail() {
        app.launch()
        allowNotificationsIfAsked()
        sleep(2)                       // let the debug reminder get scheduled
        app.terminate()                // cold: the tap must START the process
        waitForBannerAndTap()
        assertAppAliveWithDetail()
    }

    func testWarmResumeNotificationTapOpensDetail() {
        app.launch()
        allowNotificationsIfAsked()
        sleep(2)
        XCUIDevice.shared.press(.home) // warm: app stays resident in background
        waitForBannerAndTap()
        assertAppAliveWithDetail()
    }
}
