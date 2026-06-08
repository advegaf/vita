import XCTest
@testable import Vita

@MainActor
final class DiaryGroundingTests: XCTestCase {

    private func day(_ ago: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -ago, to: Calendar.current.startOfDay(for: Date()))!
    }
    private func entry(_ ago: Int, e: Int, s: Int, m: Int, l: Int) -> DiaryEntry {
        let x = DiaryEntry(); x.dayStart = day(ago)
        x.energy = e; x.sleep = s; x.mood = m; x.libido = l; return x
    }
    private func weight(_ ago: Int, _ kg: Double) -> BodyMetric {
        let w = BodyMetric(); w.kindRaw = BodyMetricKind.weight.rawValue
        w.valueCanonical = kg; w.measuredAt = day(ago); return w
    }

    func testAveragesAndWeightInLb() {
        let entries = [entry(0, e: 4, s: 6, m: 5, l: 7), entry(1, e: 4, s: 6, m: 5, l: 7)]
        // 84 kg → ~185.2 lb; 86.5 → start; current 84 → down ~5.5 lb
        let metrics = [weight(29, 86.5), weight(0, 84.0)]
        let line = DiaryGrounding.summaryLine(entries: entries, metrics: metrics, weightUnit: .lb)
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("energy 4/10"))
        XCTAssertTrue(line!.contains("sleep 6/10"))
        XCTAssertTrue(line!.contains("down"))
        XCTAssertTrue(line!.contains("lb"))
    }

    func testNilWhenEmpty() {
        XCTAssertNil(DiaryGrounding.summaryLine(entries: [], metrics: [], weightUnit: .lb))
    }

    func testWeightOnlySteady() {
        let metrics = [weight(0, 80.0)]   // single sample → no delta
        let line = DiaryGrounding.summaryLine(entries: [], metrics: metrics, weightUnit: .kg)
        XCTAssertNotNil(line)
        XCTAssertFalse(line!.contains("down"))
        XCTAssertFalse(line!.contains("up"))
        XCTAssertTrue(line!.contains("kg"))
    }
}
