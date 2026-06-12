import XCTest
import SwiftData
@testable import Vita

/// Pure marker-over-time derivations (M11). Panels are built through
/// LabService.savePanel so relationships are wired the supported way (insert
/// before relating) and stored flags are computed exactly as in production.
@MainActor
final class LabSeriesTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private var context: ModelContext!
    private lazy var now = Date()

    override func setUp() {
        super.setUp()
        container = VitaContainer.make(inMemory: true)
        context = container.mainContext
    }

    private func seedPanel(daysAgo: Int, lab: String = "Quest",
                           values: [LabPanelDTO.Value]) {
        LabService(context: context).savePanel(
            LabPanelDTO(panelDate: nil, sourceLabName: lab, values: values,
                        summary: "s", disclaimer: "d"),
            scanData: nil, mediaType: nil,
            at: Calendar.current.date(byAdding: .day, value: -daysAgo, to: now)!)
    }

    private func panels() -> [LabPanel] { (try? context.fetch(FetchDescriptor<LabPanel>())) ?? [] }

    private func glucose(_ v: Double, unit: String = "mg/dL") -> LabPanelDTO.Value {
        .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: v,
              unit: unit, refLow: 70, refHigh: 99)
    }

    // MARK: series

    func testSeriesOldestFirstInLatestUnit() {
        seedPanel(daysAgo: 184, values: [glucose(92)])
        seedPanel(daysAgo: 92, values: [glucose(96)])
        seedPanel(daysAgo: 0, values: [glucose(104)])
        let s = LabSeries.series(markerKey: "glucose_fasting", panels: panels())
        XCTAssertEqual(s.points.map(\.value), [92, 96, 104])      // oldest first
        XCTAssertEqual(s.unit, "mg/dL")
        XCTAssertEqual(s.skippedCount, 0)
        XCTAssertTrue(s.points[0].date < s.points[2].date)
    }

    func testSeriesUnitFilterAndSkipCount() {
        seedPanel(daysAgo: 184, values: [glucose(92)])
        seedPanel(daysAgo: 92, values: [glucose(5.3, unit: "mmol/L")])  // different unit → skipped
        seedPanel(daysAgo: 0, values: [glucose(104, unit: " MG/DL ")])  // normalizes to match
        let s = LabSeries.series(markerKey: "glucose_fasting", panels: panels())
        XCTAssertEqual(s.points.map(\.value), [92, 104])
        XCTAssertEqual(s.skippedCount, 1)
    }

    func testSeriesOutOfRangeFromStoredFlag() {
        seedPanel(daysAgo: 92, values: [glucose(85)])
        seedPanel(daysAgo: 0, values: [
            glucose(104),                                              // above 99 → high
            .init(markerKey: "ldl_cholesterol", name: "LDL", value: 138,
                  unit: "mg/dL", refLow: nil, refHigh: 100),           // one-sided → high
        ])
        let g = LabSeries.series(markerKey: "glucose_fasting", panels: panels())
        XCTAssertEqual(g.points.map(\.isOutOfRange), [false, true])
        let l = LabSeries.series(markerKey: "ldl_cholesterol", panels: panels())
        XCTAssertTrue(l.points.last!.isOutOfRange)
    }

    func testSeriesMissingMarkerEmpty() {
        seedPanel(daysAgo: 0, values: [glucose(104)])
        let s = LabSeries.series(markerKey: "nope", panels: panels())
        XCTAssertTrue(s.points.isEmpty)
        XCTAssertEqual(s.skippedCount, 0)
    }

    // MARK: trendedMarkers

    func testTrendedVsSingleSplit() {
        seedPanel(daysAgo: 92, values: [
            glucose(96),
            .init(markerKey: "ferritin", name: "Ferritin", value: 180, unit: "nmol/L"),  // unit mismatch ↓
        ])
        seedPanel(daysAgo: 0, values: [
            glucose(104),
            .init(markerKey: "ferritin", name: "Ferritin", value: 80, unit: "ng/mL"),
            .init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
        ])
        let m = LabSeries.trendedMarkers(panels: panels())
        XCTAssertEqual(m.trended.map(\.markerKey), ["glucose_fasting"])
        // ferritin has 2 raw results but mismatched units → 1 plottable point → single, no delta.
        let single = m.single.first { $0.markerKey == "ferritin" }
        XCTAssertEqual(single?.pointCount, 1)
        XCTAssertNil(single?.delta)
        XCTAssertTrue(m.single.contains { $0.markerKey == "tsh" })
    }

    func testIndexSortedOutOfRangeFirstThenName() {
        seedPanel(daysAgo: 92, values: [
            glucose(104),                                                       // → high (clay)
            .init(markerKey: "tsh", name: "TSH", value: 2.0, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
            .init(markerKey: "alt", name: "ALT", value: 22, unit: "U/L", refLow: 7, refHigh: 56),
        ])
        seedPanel(daysAgo: 0, values: [
            glucose(110),
            .init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
            .init(markerKey: "alt", name: "ALT", value: 25, unit: "U/L", refLow: 7, refHigh: 56),
        ])
        let m = LabSeries.trendedMarkers(panels: panels())
        XCTAssertEqual(m.trended.map(\.name), ["Glucose, Fasting", "ALT", "TSH"])  // flagged first, then name
    }

    func testSummaryDeltaAndNewestName() {
        seedPanel(daysAgo: 92, values: [
            .init(markerKey: "tsh", name: "TSH", value: 1.7, unit: "mIU/L", refLow: 0.4, refHigh: 4.0)])
        seedPanel(daysAgo: 0, values: [
            .init(markerKey: "tsh", name: "Thyroid Stimulating Hormone", value: 2.1,
                  unit: "mIU/L", refLow: 0.4, refHigh: 4.0)])
        let m = LabSeries.trendedMarkers(panels: panels())
        let tsh = m.trended.first { $0.markerKey == "tsh" }
        XCTAssertEqual(tsh?.name, "Thyroid Stimulating Hormone")   // newest printed name wins
        XCTAssertEqual(tsh!.delta!, 0.4, accuracy: 0.0001)
        XCTAssertEqual(tsh?.latestValue, 2.1)
        XCTAssertEqual(tsh?.pointCount, 2)
    }

    func testEmptyPanelsAreSafe() {
        let m = LabSeries.trendedMarkers(panels: [])
        XCTAssertTrue(m.trended.isEmpty)
        XCTAssertTrue(m.single.isEmpty)
        XCTAssertTrue(LabSeries.series(markerKey: "x", panels: []).points.isEmpty)
    }

    // MARK: domains

    func testDateDomainPadding() {
        seedPanel(daysAgo: 0, values: [glucose(104)])
        let single = LabSeries.series(markerKey: "glucose_fasting", panels: panels()).points
        let d1 = LabSeries.dateDomain(for: single)
        XCTAssertGreaterThanOrEqual(
            d1.upperBound.timeIntervalSince(d1.lowerBound), 13.9 * 86400)   // ≥ ~14-day span for one point

        seedPanel(daysAgo: 92, values: [glucose(96)])
        let two = LabSeries.series(markerKey: "glucose_fasting", panels: panels()).points
        let d2 = LabSeries.dateDomain(for: two)
        XCTAssertTrue(d2.lowerBound < two.first!.date)                      // strictly contains, padded
        XCTAssertTrue(d2.upperBound > two.last!.date)
    }

    func testYDomainIncludesBandAndFlatSeries() {
        seedPanel(daysAgo: 92, values: [
            .init(markerKey: "testosterone_total", name: "T", value: 612, unit: "ng/dL",
                  refLow: 264, refHigh: 916)])
        let pts = LabSeries.series(markerKey: "testosterone_total", panels: panels()).points
        let y = LabSeries.yDomain(points: pts, refLow: 264, refHigh: 916)
        XCTAssertTrue(y.lowerBound < 264 && y.upperBound > 916)             // band fully inside

        // Flat series at a small magnitude still gets a non-degenerate span.
        let flat = [LabTrendPoint(id: UUID(), date: now, value: 2.1, unit: "mIU/L",
                                  refLow: nil, refHigh: nil, flag: .normal)]
        let y2 = LabSeries.yDomain(points: flat, refLow: nil, refHigh: nil)
        XCTAssertGreaterThan(y2.upperBound - y2.lowerBound, 0.4)
    }
}
