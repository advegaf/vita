import XCTest
import SwiftData
@testable import Vita

@MainActor
final class LabGroundingTests: XCTestCase {

    private var container: ModelContainer!
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    func testNilWhenNoPanels() {
        XCTAssertNil(LabGrounding.summaryLine(panels: []))
    }

    func testLatestOutOfRangeLine() {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        // older, in-range panel
        svc.savePanel(LabPanelDTO(panelDate: nil, sourceLabName: "A",
            values: [.init(markerKey: "tsh", name: "TSH", value: 2.0, unit: "mIU/L", refLow: 0.4, refHigh: 4.0)],
            summary: "", disclaimer: "x"),
            scanData: nil, mediaType: nil, at: Date().addingTimeInterval(-90 * 86400))
        // recent panel with two out-of-range
        svc.savePanel(LabPanelDTO(panelDate: "2026-05-20", sourceLabName: "B",
            values: [
                .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: 104, unit: "mg/dL", refLow: 70, refHigh: 99),
                .init(markerKey: "vitamin_d", name: "Vitamin D", value: 22, unit: "ng/mL", refLow: 30, refHigh: 100),
                .init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
            ],
            summary: "", disclaimer: "x"),
            scanData: nil, mediaType: nil)

        let line = LabGrounding.summaryLine(panels: svc.panels())
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.contains("Glucose, Fasting 104 mg/dL (high)"))
        XCTAssertTrue(line!.contains("Vitamin D 22 ng/mL (low)"))
        XCTAssertFalse(line!.contains("TSH"))      // in range, excluded
    }

    func testNilWhenAllInRange() {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        svc.savePanel(LabPanelDTO(panelDate: "2026-05-20", sourceLabName: "B",
            values: [.init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0)],
            summary: "", disclaimer: "x"),
            scanData: nil, mediaType: nil)
        XCTAssertNil(LabGrounding.summaryLine(panels: svc.panels()))
    }

    func testStackReviewPrompt() {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        // All-normal panel → the calm phrasing (still a valid ask).
        svc.savePanel(LabPanelDTO(panelDate: "2026-05-20", sourceLabName: "B",
            values: [.init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0)],
            summary: "", disclaimer: "x"),
            scanData: nil, mediaType: nil)
        XCTAssertTrue(LabGrounding.stackReviewPrompt(panels: svc.panels()).contains("in range"))

        // A flagged panel → the prompt carries the flagged markers + the ask.
        svc.savePanel(LabPanelDTO(panelDate: "2026-06-01", sourceLabName: "B",
            values: [.init(markerKey: "glucose", name: "Glucose", value: 104, unit: "mg/dL", refLow: 70, refHigh: 99)],
            summary: "", disclaimer: "x"),
            scanData: nil, mediaType: nil)
        let p = LabGrounding.stackReviewPrompt(panels: svc.panels())
        XCTAssertTrue(p.contains("Glucose"))
        XCTAssertTrue(p.contains("Review my current stack"))
    }
}
