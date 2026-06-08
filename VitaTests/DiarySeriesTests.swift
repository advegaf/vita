import XCTest
@testable import Vita

/// Pure series/averages/trend derivations — no container needed (build model
/// objects directly; @Model instances work unsaved for read-only computation).
@MainActor
final class DiarySeriesTests: XCTestCase {

    private func cal() -> Calendar { Calendar.current }
    private func day(_ ago: Int) -> Date {
        cal().date(byAdding: .day, value: -ago, to: cal().startOfDay(for: Date()))!
    }

    private func entry(_ ago: Int, energy: Int) -> DiaryEntry {
        let e = DiaryEntry(); e.dayStart = day(ago); e.energy = energy; return e
    }
    private func weight(_ ago: Int, _ kg: Double, at: TimeInterval = 0) -> BodyMetric {
        let m = BodyMetric(); m.kindRaw = BodyMetricKind.weight.rawValue
        m.valueCanonical = kg; m.measuredAt = day(ago).addingTimeInterval(at); return m
    }

    func testRatingSeriesOrderedOldestFirstWithNils() {
        let entries = [entry(0, energy: 8), entry(2, energy: 4)]   // day 1 missing
        let s = DiarySeries.series(.energy, entries: entries, metrics: [], days: 3, asOf: Date())
        XCTAssertEqual(s.count, 3)
        XCTAssertTrue(s[0].day < s[1].day && s[1].day < s[2].day)  // oldest first
        XCTAssertEqual(s[0].value, 4)      // 2 days ago
        XCTAssertNil(s[1].value)           // yesterday missing
        XCTAssertEqual(s[2].value, 8)      // today
    }

    func testWeightSeriesLatestPerDay() {
        // two samples same day → latest measuredAt wins
        let metrics = [weight(0, 84.0, at: 100), weight(0, 83.0, at: 5000)]
        let s = DiarySeries.series(.weight, entries: [], metrics: metrics, days: 1, asOf: Date())
        XCTAssertEqual(s.last?.value, 83.0)
    }

    func testLatest() {
        let metrics = [weight(3, 85), weight(1, 83)]
        XCTAssertEqual(DiarySeries.latest(.weight, metrics: metrics), 83)
        XCTAssertNil(DiarySeries.latest(.waist, metrics: metrics))
    }

    func testRecentAveragesIgnoreUnset() {
        let entries = [entry(0, energy: 8), entry(1, energy: 0), entry(2, energy: 4)]  // 0 ignored
        let avgs = DiarySeries.recentAverages(entries: entries, days: 7, asOf: Date())
        XCTAssertEqual(avgs[.energy] ?? 0, 6, accuracy: 1e-9)   // (8+4)/2
        XCTAssertNil(avgs[.mood])                               // never rated
    }

    func testWeightTrendDelta() {
        let metrics = [weight(20, 86), weight(0, 83)]
        let t = DiarySeries.weightTrend(metrics: metrics, days: 30, asOf: Date())
        XCTAssertEqual(t.currentKg ?? 0, 83, accuracy: 1e-9)
        XCTAssertEqual(t.deltaKg ?? 0, -3, accuracy: 1e-9)     // down 3 kg
    }

    func testEmptyInputsNoCrash() {
        XCTAssertTrue(DiarySeries.recentAverages(entries: [], days: 7, asOf: Date()).isEmpty)
        let t = DiarySeries.weightTrend(metrics: [], days: 30, asOf: Date())
        XCTAssertNil(t.currentKg); XCTAssertNil(t.deltaKg)
    }

    func testTrendDomainNeverEdgeHugging() {
        let d = TrendDomain.padded(min: 177.5, max: 185.2, minSpan: 6)
        XCTAssertLessThan(d.lowerBound, 177.5)          // bottom clears the lowest point
        XCTAssertGreaterThan(d.upperBound, 185.2)       // top clears the highest point
        let frac = (185.2 - 177.5) / (d.upperBound - d.lowerBound)
        XCTAssertEqual(frac, 0.6, accuracy: 0.001)      // data fills the middle ~60%
    }

    func testTrendDomainFlatSeriesGetsRoom() {
        let d = TrendDomain.padded(min: 80, max: 80, minSpan: 6)
        XCTAssertLessThan(d.lowerBound, 80)
        XCTAssertGreaterThan(d.upperBound, 80)
        XCTAssertEqual(d.upperBound - d.lowerBound, 6 / 0.6, accuracy: 1e-6)  // floor applied
        XCTAssertEqual((d.lowerBound + d.upperBound) / 2, 80, accuracy: 1e-6) // centered
    }
}
