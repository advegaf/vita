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

    func testQualitativeValueIsUnknownNotLow() throws {
        let ctx = makeContext()
        let svc = LabService(context: ctx)
        // A qualitative result ("Negative") decodes value=0 but must NOT flag LOW
        // against a positive ref-low; the word is preserved for display.
        var dto = LabPanelDTO(panelDate: "2026-05-20", sourceLabName: "Lab",
                              values: [.init(markerKey: "hiv_ab", name: "HIV Antibody", value: 0, unit: "",
                                             refLow: 0.5, refHigh: nil,
                                             hasNumericValue: false, qualitative: "Negative")],
                              summary: "s", disclaimer: "Educational, not medical advice.")
        dto.values[0].flagRaw = "N"
        svc.savePanel(dto, scanData: nil, mediaType: nil)

        let value = try ctx.fetch(FetchDescriptor<LabValue>()).first { $0.markerKey == "hiv_ab" }!
        XCTAssertEqual(value.flag, .unknown)               // not .low despite 0 < 0.5
        XCTAssertEqual(value.qualitativeText, "Negative")
        XCTAssertEqual(value.valueDisplay, "Negative")     // shows the word, not "0"
    }

    func testQualitativeDecodesFromJSON() throws {
        // The DTO marks a non-numeric "value" as qualitative end-to-end.
        let json = """
        {"panel_date":null,"source_lab_name":null,"summary":"s","disclaimer":"d",
         "values":[{"marker_key":"hiv_ab","name":"HIV Antibody","value":"Negative","unit":"","ref_low":0.5}]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(LabPanelDTO.self, from: json)
        XCTAssertEqual(dto.values.count, 1)
        XCTAssertFalse(dto.values[0].hasNumericValue)
        XCTAssertEqual(dto.values[0].qualitative, "Negative")
        XCTAssertEqual(dto.values[0].value, 0)
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
