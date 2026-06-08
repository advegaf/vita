import XCTest
import SwiftData
@testable import Vita

@MainActor
final class DiaryServiceTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    func testUpsertTodayOncePerDay() throws {
        let ctx = makeContext()
        let svc = DiaryService(context: ctx)
        svc.upsertToday(energy: 5, sleep: 5, mood: 5, libido: 5, sideEffects: [], note: "")
        svc.upsertToday(energy: 8, sleep: 7, mood: 9, libido: 6, sideEffects: [.fatigue], note: "ok")

        let all = try ctx.fetch(FetchDescriptor<DiaryEntry>())
        XCTAssertEqual(all.count, 1)                       // one row per day
        XCTAssertEqual(all.first?.energy, 8)               // flipped in place
        XCTAssertEqual(all.first?.sideEffectsRaw, ["fatigue"])
    }

    func testUpsertAcrossTwoDays() throws {
        let ctx = makeContext()
        let svc = DiaryService(context: ctx)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        svc.upsertToday(energy: 5, sleep: 5, mood: 5, libido: 5, sideEffects: [], note: "", on: yesterday)
        svc.upsertToday(energy: 6, sleep: 6, mood: 6, libido: 6, sideEffects: [], note: "")
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<DiaryEntry>()).count, 2)
    }

    func testHasAnyRating() {
        let ctx = makeContext()
        let svc = DiaryService(context: ctx)
        let e = svc.upsertToday(energy: 0, sleep: 0, mood: 0, libido: 0, sideEffects: [], note: "")
        XCTAssertFalse(e.isLogged)
        let e2 = svc.upsertToday(energy: 7, sleep: 0, mood: 0, libido: 0, sideEffects: [], note: "")
        XCTAssertTrue(e2.isLogged)
    }

    func testAddBodyMetricAppends() throws {
        let ctx = makeContext()
        let svc = DiaryService(context: ctx)
        svc.addBodyMetric(.weight, valueCanonical: 84)
        svc.addBodyMetric(.weight, valueCanonical: 83.5)
        let all = try ctx.fetch(FetchDescriptor<BodyMetric>())
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(DiarySeries.latest(.weight, metrics: all), 83.5)
    }

    func testMergeHealthWeightsIsIdempotent() throws {
        let ctx = makeContext()
        let svc = DiaryService(context: ctx)
        let now = Date()
        let samples = [
            (uuid: "a", kg: 84.0, date: now),
            (uuid: "b", kg: 83.8, date: now.addingTimeInterval(-86400)),
            (uuid: "c", kg: 83.6, date: now.addingTimeInterval(-2 * 86400)),
        ]
        svc.mergeHealthWeights(samples)
        svc.mergeHealthWeights(samples)                    // re-import: no dupes
        let health = try ctx.fetch(FetchDescriptor<BodyMetric>())
        XCTAssertEqual(health.count, 3)

        // A same-day manual entry coexists (not deduped against Health).
        svc.addBodyMetric(.weight, valueCanonical: 90)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<BodyMetric>()).count, 4)
    }
}
