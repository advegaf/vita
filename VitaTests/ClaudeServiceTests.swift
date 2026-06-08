import XCTest
@testable import Vita

final class ClaudeServiceTests: XCTestCase {

    // A small catalog the validator maps against.
    private let catalog: [CatalogSummary] = [
        CatalogSummary(slug: "bpc-157", name: "BPC-157", categoryRaw: "muscleRecovery",
                       rxStatusRaw: "nonRx", doseUnitRaw: "mcg",
                       typicalDoseLow: 200, typicalDoseHigh: 500, route: "subcutaneous",
                       defaultScheduleTypeRaw: "daily"),
        CatalogSummary(slug: "semaglutide", name: "Semaglutide", categoryRaw: "weightLoss",
                       rxStatusRaw: "rx", doseUnitRaw: "mg",
                       typicalDoseLow: 0.25, typicalDoseHigh: 2.0, route: "subcutaneous",
                       defaultScheduleTypeRaw: "weekly"),
    ]

    // MARK: - DTO decode

    func testDecodeFixture() throws {
        let json = """
        {"disclaimer":"Educational, not medical advice.",
         "items":[{"compound_slug":"bpc-157","dose_amount":300,"dose_unit":"mcg",
                   "frequency":"daily","weekdays":[],"times_minutes":[480],
                   "rationale":"recovery"}]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(ProtocolDTO.self, from: json)
        XCTAssertEqual(dto.items.count, 1)
        XCTAssertEqual(dto.items[0].compoundSlug, "bpc-157")
        XCTAssertEqual(dto.items[0].doseAmount, 300, accuracy: 1e-9)
    }

    func testDecodeTolerantOfMissingArrays() throws {
        let json = """
        {"disclaimer":"x","items":[{"compound_slug":"bpc-157","dose_amount":300,
          "dose_unit":"mcg","frequency":"daily"}]}
        """.data(using: .utf8)!
        let dto = try JSONDecoder().decode(ProtocolDTO.self, from: json)
        XCTAssertEqual(dto.items[0].weekdays, [])
        XCTAssertEqual(dto.items[0].timesMinutes, [])
        XCTAssertNil(dto.items[0].rationale)
    }

    // MARK: - Validation + mapping

    func testClampsDoseIntoRange() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "bpc-157", doseAmount: 5000, doseUnit: "mcg",
                  frequency: "daily", timesMinutes: [480]),
        ])
        let drafts = ClaudeService.buildDrafts(from: dto, catalog: catalog)
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts[0].doseAmount, 500, accuracy: 1e-9)   // clamped to high
    }

    func testDropsUnknownSlug() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "not-a-real-slug", doseAmount: 1, doseUnit: "mg", frequency: "daily"),
            .init(compoundSlug: "bpc-157", doseAmount: 300, doseUnit: "mcg",
                  frequency: "daily", timesMinutes: [480]),
        ])
        let drafts = ClaudeService.buildDrafts(from: dto, catalog: catalog)
        XCTAssertEqual(drafts.map(\.compoundSlug), ["bpc-157"])
    }

    func testDedupesRepeatedSlug() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "bpc-157", doseAmount: 300, doseUnit: "mcg", frequency: "daily"),
            .init(compoundSlug: "bpc-157", doseAmount: 400, doseUnit: "mcg", frequency: "daily"),
        ])
        XCTAssertEqual(ClaudeService.buildDrafts(from: dto, catalog: catalog).count, 1)
    }

    func testIdentityComesFromCatalogNotModel() {
        // Model lies about unit/category; validator trusts the catalog.
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "semaglutide", doseAmount: 1, doseUnit: "mcg", frequency: "weekly", weekdays: [3]),
        ])
        let d = ClaudeService.buildDrafts(from: dto, catalog: catalog)[0]
        XCTAssertEqual(d.doseUnit, .mg)                       // from catalog, not "mcg"
        XCTAssertEqual(d.rxStatusRaw, "rx")
        XCTAssertEqual(d.displayName, "Semaglutide")
        XCTAssertEqual(d.frequency, .weekly)
        XCTAssertEqual(d.weekdays, [3])
    }

    func testWeeklyWithoutWeekdaysGetsDefault() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "semaglutide", doseAmount: 1, doseUnit: "mg", frequency: "weekly", weekdays: []),
        ])
        let d = ClaudeService.buildDrafts(from: dto, catalog: catalog)[0]
        XCTAssertFalse(d.weekdays.isEmpty)
    }

    func testNonPrnEmptyTimesGetsMorningDefault() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "bpc-157", doseAmount: 300, doseUnit: "mcg", frequency: "daily", timesMinutes: []),
        ])
        let d = ClaudeService.buildDrafts(from: dto, catalog: catalog)[0]
        XCTAssertEqual(d.times, [DayBlock.morning.defaultMinutes])
    }

    func testPrnHasNoTimesOrWeekdays() {
        let dto = ProtocolDTO(disclaimer: "x", items: [
            .init(compoundSlug: "bpc-157", doseAmount: 300, doseUnit: "mcg", frequency: "prn",
                  weekdays: [2], timesMinutes: [480]),
        ])
        let d = ClaudeService.buildDrafts(from: dto, catalog: catalog)[0]
        XCTAssertEqual(d.frequency, .prn)
        XCTAssertTrue(d.times.isEmpty)
        XCTAssertTrue(d.weekdays.isEmpty)
    }

    func testEmptyDTOProducesNoDrafts() {
        let dto = ProtocolDTO(disclaimer: "x", items: [])
        XCTAssertTrue(ClaudeService.buildDrafts(from: dto, catalog: catalog).isEmpty)
    }

    // MARK: - Stub service

    func testStubReturnsGroundedProtocol() async throws {
        let input = ProtocolInput(goals: [.recoveryHealing], pickedSlugs: [],
                                  catalog: catalog, profile: ProfileInput(), health: nil)
        let dto = try await StubClaudeService().generateProtocol(input)
        XCTAssertFalse(dto.disclaimer.isEmpty)
        // recoveryHealing → bpc-157 + tb-500; only bpc-157 is in this test catalog,
        // so the stub (which maps against the catalog) drops tb-500.
        XCTAssertEqual(dto.items.map(\.compoundSlug), ["bpc-157"])
    }
}
