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
}
