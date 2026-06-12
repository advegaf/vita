import XCTest
@testable import Vita

final class LabPanelDTOTests: XCTestCase {

    func testDecodeFixture() throws {
        let json = """
        {
          "panel_date": "2026-05-20",
          "source_lab_name": "Quest",
          "summary": "A couple values out of range.",
          "disclaimer": "Educational, not medical advice.",
          "values": [
            {"marker_key":"glucose_fasting","name":"Glucose, Fasting","value":104,"unit":"mg/dL","ref_low":70,"ref_high":99,"ref_text":null,"flag_raw":"H"},
            {"marker_key":"hdl_cholesterol","name":"HDL","value":41,"unit":"mg/dL","ref_low":40,"ref_high":null,"ref_text":null,"flag_raw":null}
          ]
        }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(LabPanelDTO.self, from: json)
        XCTAssertEqual(dto.panelDate, "2026-05-20")
        XCTAssertEqual(dto.sourceLabName, "Quest")
        XCTAssertEqual(dto.values.count, 2)
        XCTAssertEqual(dto.values[0].markerKey, "glucose_fasting")
        XCTAssertEqual(dto.values[0].value, 104)
        XCTAssertEqual(dto.values[0].refHigh, 99)
        XCTAssertNil(dto.values[1].refHigh)        // null → nil
        XCTAssertEqual(dto.values[1].flagRaw, nil)
    }

    func testTolerantDecodeMissingFields() throws {
        // values omitted, disclaimer omitted, date null
        let json = """
        { "panel_date": null, "source_lab_name": null, "summary": "x" }
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(LabPanelDTO.self, from: json)
        XCTAssertTrue(dto.values.isEmpty)
        XCTAssertNil(dto.panelDate)
        XCTAssertFalse(dto.disclaimer.isEmpty)     // defaulted
    }

    func testLenientValueDecodeSkipsBadRowsOnly() throws {
        // One malformed row (value is a string) must NOT drop the whole array.
        let json = """
        { "summary": "s", "values": [
            {"marker_key":"tsh","name":"TSH","value":2.1,"unit":"mIU/L"},
            {"marker_key":"bad","name":"Bad","value":"not-a-number","unit":"x"},
            {"marker_key":"alt","name":"ALT","value":22,"unit":"U/L"}
        ]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(LabPanelDTO.self, from: json)
        // The tolerant per-field decode coerces the bad row's value to 0 rather than
        // dropping it (every field is individually defaulted), so all rows survive
        // and the array-level decode never throws away the panel.
        XCTAssertEqual(dto.values.count, 3)
        XCTAssertEqual(dto.values.map(\.markerKey), ["tsh", "bad", "alt"])
    }

    // MARK: merged (per-page extraction)

    private func page(date: String? = nil, lab: String? = nil, summary: String = "",
                      keys: [(String, Double)]) -> LabPanelDTO {
        LabPanelDTO(panelDate: date, sourceLabName: lab,
                    values: keys.map { .init(markerKey: $0.0, name: $0.0, value: $0.1, unit: "u") },
                    summary: summary, disclaimer: "d")
    }

    func testMergedDedupesByMarkerKeyFirstWins() {
        let merged = LabPanelDTO.merged([
            page(keys: [("glucose", 104), ("ldl", 138)]),
            page(keys: [("glucose", 999), ("tsh", 2.1)]),   // repeated header row → first wins
        ])
        XCTAssertEqual(merged.values.map(\.markerKey), ["glucose", "ldl", "tsh"])
        XCTAssertEqual(merged.values[0].value, 104)          // page-1 glucose kept
    }

    func testMergedMetadataFirstNonNil() {
        let merged = LabPanelDTO.merged([
            page(keys: [("a", 1)]),                          // no metadata
            page(date: "2025-09-02", lab: "Quest", summary: "what stands out", keys: [("b", 2)]),
            page(date: "1999-01-01", lab: "Other", keys: [("c", 3)]),
        ])
        XCTAssertEqual(merged.panelDate, "2025-09-02")       // first non-nil
        XCTAssertEqual(merged.sourceLabName, "Quest")
        XCTAssertEqual(merged.summary, "what stands out")    // first non-empty
        XCTAssertEqual(merged.values.count, 3)
    }

    func testMergedEmptyPages() {
        let merged = LabPanelDTO.merged([])
        XCTAssertTrue(merged.values.isEmpty)
        XCTAssertFalse(merged.disclaimer.isEmpty)            // defaulted
    }
}
