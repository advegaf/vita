import XCTest
@testable import Vita

/// M49: the one-line Oura grounding sentence for chat.
final class OuraGroundingTests: XCTestCase {

    func testNilWhenNotConnectedOrEmpty() {
        XCTAssertNil(OuraGrounding.summaryLine(nil))
        XCTAssertNil(OuraGrounding.summaryLine(OuraDailySummary(
            readiness: [], sleepScore: [], temperatureDeviation: [])))
    }

    func testLineCarriesLatestNightValues() {
        let day = Calendar.current.startOfDay(for: .now)
        let summary = OuraDailySummary(
            readiness: [OuraDayScore(day: day, score: 82)],
            sleepScore: [OuraDayScore(day: day, score: 84)],
            temperatureDeviation: [OuraDayValue(day: day, value: 0.2)],
            vitals: VitalsSeries(hrvMs: [DatedValue(day: day, value: 58)],
                                 restingHR: [DatedValue(day: day, value: 52)],
                                 respiratoryRate: [DatedValue(day: day, value: 13.4)],
                                 sleepHours: [DatedValue(day: day, value: 7.9)]))
        let line = OuraGrounding.summaryLine(summary) ?? ""
        XCTAssertTrue(line.hasPrefix("Wearables (Oura, latest night): "), line)
        for expected in ["sleep 7.9 h", "HRV 58 ms", "resting HR 52 bpm",
                         "breath 13.4/min", "readiness 82/100", "sleep score 84/100",
                         "temp +0.2 C vs baseline"] {
            XCTAssertTrue(line.contains(expected), "missing \(expected) in: \(line)")
        }
        XCTAssertFalse(line.contains("\u{2014}"), "no em dashes in grounding text")
    }

    func testNegligibleTempDeviationOmitted() {
        let day = Calendar.current.startOfDay(for: .now)
        let summary = OuraDailySummary(
            readiness: [OuraDayScore(day: day, score: 80)],
            sleepScore: [],
            temperatureDeviation: [OuraDayValue(day: day, value: 0.0)])
        let line = OuraGrounding.summaryLine(summary) ?? ""
        XCTAssertFalse(line.contains("temp"), line)
        XCTAssertTrue(line.contains("readiness 80/100"), line)
    }
}
