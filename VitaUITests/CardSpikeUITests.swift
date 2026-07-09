import XCTest

/// M38 spike verification (see SpikeCardView). Empirically answers, on iOS 26:
///  A. Do programmatic detent changes animate, and does `onGeometryChange`
///     stream PER-FRAME minY samples during the transition? (drives all the
///     photo/header/bar chrome)
///  B. Does a real (slow, coordinate-based) drag on the sheet's non-scroll
///     chrome move the sheet interactively, with per-frame samples?
///  C. Does an upward drag on inner SwiftUI scroll content expand the sheet
///     (Maps-style handoff), or does content scroll in place? (informational —
///     run 1/2 showed flick-swipes never move the sheet; this is the decider
///     for what the drag affordance must be)
final class CardSpikeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["VITA_SPIKE_CARD"] = "1"
    }

    /// Parses "y=612 n=37 t=..." from the probe label.
    private func probe() -> (y: Int, n: Int) {
        let text = app.staticTexts["spike-probe"].label
        var y = 0, n = 0
        for part in text.split(separator: " ") {
            if part.hasPrefix("y=") { y = Int(part.dropFirst(2)) ?? 0 }
            if part.hasPrefix("n=") { n = Int(part.dropFirst(2)) ?? 0 }
        }
        return (y, n)
    }

    func testDetentMechanics() {
        app.launch()
        let probeLabel = app.staticTexts["spike-probe"]
        XCTAssertTrue(probeLabel.waitForExistence(timeout: 10))
        sleep(2)
        let rest = probe()
        XCTAssertGreaterThan(rest.y, 200, "rest detent should leave the photo area visible")

        // A) Programmatic detent change animates + streams per-frame geometry.
        app.buttons["Expand"].tap()
        sleep(1)
        let expanded = probe()
        XCTAssertLessThan(expanded.y, rest.y - 120, "programmatic detent change should expand the sheet")
        // Learning from run 3: programmatic detent animations report ENDPOINTS only
        // (SwiftUI geometry reflects model values, not CA presentation frames), so
        // chrome must animate discrete progress jumps itself. Per-frame streaming
        // is asserted below for the INTERACTIVE drag, where it actually matters.
        NSLog("SPIKE-RESULT programmatic expand: samples \(rest.n) -> \(expanded.n)")

        app.buttons["Rest"].tap()
        sleep(1)
        let backToRest = probe()
        XCTAssertEqual(backToRest.y, rest.y, accuracy: 30, "sheet should return to the rest detent")

        // B) Slow coordinate drag on non-scroll chrome (nav bar) moves the sheet.
        let navBar = app.navigationBars.firstMatch
        XCTAssertTrue(navBar.exists)
        let start = navBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        start.press(forDuration: 0.15, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        let dragged = probe()
        XCTAssertLessThan(dragged.y, rest.y - 120,
                          "a slow drag on the sheet's chrome should expand the sheet interactively")
        XCTAssertGreaterThan(dragged.n, backToRest.n + 12,
                             "interactive drag should stream per-frame samples")

        // Drag back down from the nav bar to the rest position.
        let downStart = navBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let downEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.62))
        downStart.press(forDuration: 0.15, thenDragTo: downEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        NSLog("SPIKE-RESULT after chrome drag down: y=\(probe().y) (rest was \(rest.y))")

        // C) Informational: slow upward drag on scroll CONTENT from the rest
        //    detent — does the sheet expand (handoff) or does content scroll?
        app.buttons["Rest"].tap()
        sleep(1)
        let preContentDrag = probe()
        let rowStart = app.staticTexts["Row 2"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let rowEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.10))
        rowStart.press(forDuration: 0.15, thenDragTo: rowEnd, withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        let postContentDrag = probe()
        NSLog("SPIKE-RESULT content drag: y \(preContentDrag.y) -> \(postContentDrag.y) — "
              + (postContentDrag.y < preContentDrag.y - 120
                 ? "SCROLL-EXPAND HANDOFF WORKS" : "content scrolls in place (no handoff)"))
    }
}
