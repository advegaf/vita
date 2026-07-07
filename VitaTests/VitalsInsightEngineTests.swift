import XCTest
@testable import Vita

/// Pure vitals analysis (M38): baselines, rule thresholds, persistence damping, and
/// protocol-correlation anchoring with add-date honesty.
final class VitalsInsightEngineTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var now = cal.startOfDay(for: Date())

    /// Builds a series of `days` daily values ending today, newest last.
    private func series(_ days: Int, _ value: (Int) -> Double) -> [DatedValue] {
        (0..<days).map { i in
            let back = days - 1 - i
            return DatedValue(day: cal.date(byAdding: .day, value: -back, to: now)!, value: value(back))
        }
    }

    // MARK: Baseline

    func testBaselineExcludesRecentWindow() {
        // Baseline (days 8..37 back) = 50; recent 7 days = 40.
        let s = series(40) { back in back < 7 ? 40 : 50 }
        XCTAssertEqual(VitalsInsightEngine.baseline(s, asOf: now)!, 50, accuracy: 0.01)
        XCTAssertEqual(VitalsInsightEngine.recentAverage(s, asOf: now)!, 40, accuracy: 0.01)
    }

    func testBaselineNilBelowMinSamples() {
        // Only 5 days of data → fewer than the 10-sample baseline minimum.
        let s = series(40) { back in back < 5 ? 45 : Double.nan }.filter { !$0.value.isNaN }
        XCTAssertNil(VitalsInsightEngine.baseline(s, asOf: now))
    }

    // MARK: Rules + persistence

    func testHRVDropFiresAttentionWhenPersistent() {
        // HRV 52 baseline, last 10 days at 38 (>10% drop, persistent).
        let hrv = series(40) { back in back < 10 ? 38 : 52 }
        let out = VitalsInsightEngine.insights(VitalsSeries(hrvMs: hrv), asOf: now)
        XCTAssertTrue(out.contains { $0.metric == .hrv && $0.tone == .attention })
    }

    func testHRVDropSuppressedWithoutPersistence() {
        // Only the single most-recent day dips → fails the 3-of-5 persistence gate.
        let hrv = series(40) { back in back == 0 ? 30 : 52 }
        let out = VitalsInsightEngine.insights(VitalsSeries(hrvMs: hrv), asOf: now)
        XCTAssertFalse(out.contains { $0.metric == .hrv && $0.tone == .attention })
    }

    func testSteadyProducesPositive() {
        let flat = series(40) { _ in 50 }
        let out = VitalsInsightEngine.insights(VitalsSeries(hrvMs: flat, restingHR: flat), asOf: now)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out.first?.tone, .positive)
    }

    func testAttentionCappedAtOne() {
        // Both HRV down and resting HR up, persistently → still only one attention.
        let hrv = series(40) { back in back < 10 ? 38 : 52 }
        let rhr = series(40) { back in back < 10 ? 66 : 58 }
        let out = VitalsInsightEngine.insights(VitalsSeries(hrvMs: hrv, restingHR: rhr), asOf: now)
        XCTAssertEqual(out.filter { $0.tone == .attention }.count, 1)
        XCTAssertLessThanOrEqual(out.count, 2)
    }

    // MARK: Correlation

    func testCorrelationAnchorsToStartWithRealStart() {
        // Resting HR ~58 before a compound start 20 days ago, ~64 after.
        let anchor = cal.date(byAdding: .day, value: -20, to: now)!
        let rhr = series(40) { back in back >= 20 ? 58 : 64 }
        let w = CompoundWindow(name: "Retatrutide", startDate: anchor, addedDate: anchor)
        let out = VitalsInsightEngine.insights(VitalsSeries(restingHR: rhr), windows: [w], asOf: now)
        let corr = out.first { $0.isCorrelation }
        XCTAssertNotNil(corr)
        XCTAssertTrue(corr!.headline.contains("Retatrutide started"))
        XCTAssertTrue(corr!.detail.contains("correlation, not causation"))
    }

    func testCorrelationHedgesToAddedWhenNoRealStart() {
        let anchor = cal.date(byAdding: .day, value: -20, to: now)!
        let rhr = series(40) { back in back >= 20 ? 58 : 64 }
        // startDate nil → only the add-date is known, so copy must say "you added".
        let w = CompoundWindow(name: "Retatrutide", startDate: nil, addedDate: anchor)
        let out = VitalsInsightEngine.insights(VitalsSeries(restingHR: rhr), windows: [w], asOf: now)
        let corr = out.first { $0.isCorrelation }
        XCTAssertNotNil(corr)
        XCTAssertTrue(corr!.headline.contains("you added Retatrutide"))
        XCTAssertFalse(corr!.headline.contains("started"))
    }

    func testNoCorrelationWhenAnchorOutsideWindow() {
        // Anchor 90 days ago → outside the 30-day data window, no correlation.
        let anchor = cal.date(byAdding: .day, value: -90, to: now)!
        let rhr = series(40) { _ in 60 }
        let w = CompoundWindow(name: "Old", startDate: anchor, addedDate: anchor)
        let out = VitalsInsightEngine.insights(VitalsSeries(restingHR: rhr), windows: [w], asOf: now)
        XCTAssertFalse(out.contains { $0.isCorrelation })
    }

    // MARK: Grounding

    func testGroundingLineFormatAndNilWhenEmpty() {
        let hrv = series(40) { back in back < 7 ? 40 : 52 }
        let line = VitalsInsightEngine.groundingLine(VitalsSeries(hrvMs: hrv), asOf: now)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("HRV 7d 40 ms vs 30d 52 ms"))
        XCTAssertNil(VitalsInsightEngine.groundingLine(VitalsSeries(), asOf: now))
    }
}
