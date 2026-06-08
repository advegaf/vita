import XCTest
import SwiftData
@testable import Vita

@MainActor
final class LabServiceTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    // MARK: computeFlag (pure)

    func testComputeFlagBothBounds() {
        XCTAssertEqual(LabService.computeFlag(value: 60, refLow: 70, refHigh: 99), .low)
        XCTAssertEqual(LabService.computeFlag(value: 85, refLow: 70, refHigh: 99), .normal)
        XCTAssertEqual(LabService.computeFlag(value: 104, refLow: 70, refHigh: 99), .high)
        XCTAssertEqual(LabService.computeFlag(value: 99, refLow: 70, refHigh: 99), .normal)  // == high bound is in range
    }

    func testComputeFlagSingleBound() {
        XCTAssertEqual(LabService.computeFlag(value: 35, refLow: 40, refHigh: nil), .low)     // floor only
        XCTAssertEqual(LabService.computeFlag(value: 45, refLow: 40, refHigh: nil), .normal)
        XCTAssertEqual(LabService.computeFlag(value: 138, refLow: nil, refHigh: 100), .high)  // ceiling only
        XCTAssertEqual(LabService.computeFlag(value: 90, refLow: nil, refHigh: 100), .normal)
    }

    func testComputeFlagUnknown() {
        XCTAssertEqual(LabService.computeFlag(value: 5, refLow: nil, refHigh: nil), .unknown)
    }

    // MARK: persistence + delta

    private func panelDTO(_ date: String?, glucose: Double, ldl: Double) -> LabPanelDTO {
        LabPanelDTO(panelDate: date, sourceLabName: "Lab",
                    values: [
                        .init(markerKey: "glucose_fasting", name: "Glucose", value: glucose, unit: "mg/dL", refLow: 70, refHigh: 99),
                        .init(markerKey: "ldl_cholesterol", name: "LDL", value: ldl, unit: "mg/dL", refLow: nil, refHigh: 100),
                    ],
                    summary: "s", disclaimer: "Educational, not medical advice.")
    }

    func testSavePanelComputesFlagsAndPersists() throws {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        // Model says flag_raw could be wrong; the app computes from value vs range.
        var dto = panelDTO("2026-05-20", glucose: 104, ldl: 90)
        dto.values[0].flagRaw = "L"   // wrong on purpose
        svc.savePanel(dto, scanData: nil, mediaType: nil)

        let panels = try ctx.fetch(FetchDescriptor<LabPanel>())
        XCTAssertEqual(panels.count, 1)
        let values = panels[0].values ?? []
        XCTAssertEqual(values.count, 2)
        let glucose = values.first { $0.markerKey == "glucose_fasting" }!
        XCTAssertEqual(glucose.flag, .high)            // computed, ignores flag_raw "L"
        let ldl = values.first { $0.markerKey == "ldl_cholesterol" }!
        XCTAssertEqual(ldl.flag, .normal)
    }

    func testDeltaVsPrevious() {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        let old = Date().addingTimeInterval(-90 * 86400)
        svc.savePanel(panelDTO(nil, glucose: 96, ldl: 122), scanData: nil, mediaType: nil, at: old)
        let recent = svc.savePanel(panelDTO("2026-05-20", glucose: 104, ldl: 90), scanData: nil, mediaType: nil)

        let all = svc.panels()
        let d = LabService.deltaVsPrevious(markerKey: "glucose_fasting", panel: recent, allPanels: all)
        XCTAssertEqual(d ?? 0, 8, accuracy: 1e-9)      // 104 - 96
        // a marker only in the recent panel → nil
        XCTAssertNil(LabService.deltaVsPrevious(markerKey: "tsh", panel: recent, allPanels: all))
    }

    func testPanelsNewestFirst() {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        svc.savePanel(panelDTO(nil, glucose: 96, ldl: 122), scanData: nil, mediaType: nil,
                      at: Date().addingTimeInterval(-90 * 86400))
        svc.savePanel(panelDTO("2026-05-20", glucose: 104, ldl: 90), scanData: nil, mediaType: nil)
        let panels = svc.panels()
        XCTAssertEqual(panels.count, 2)
        XCTAssertGreaterThan(panels[0].effectiveDate, panels[1].effectiveDate)
    }
}
