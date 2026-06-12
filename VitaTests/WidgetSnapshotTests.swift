import XCTest
import SwiftData
@testable import Vita

@MainActor
final class WidgetSnapshotTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var today = cal.startOfDay(for: Date())
    private lazy var noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func dailyItem(_ c: ModelContext, name: String, times: [Int]) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = name
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "daily"; r.timeSlotsMinutes = times
        c.insert(r); item.schedule = r
        return item
    }

    func testSnapshotBuildsTodayAndTomorrow() {
        let c = ctx()
        let bpc = dailyItem(c, name: "BPC-157", times: [480, 1260])
        _ = dailyItem(c, name: "CJC", times: [1320])
        let log = DoseLog(); log.itemID = bpc.id; log.scheduledDayStart = today
        log.scheduledMinutes = 480; log.statusRaw = "taken"; c.insert(log)

        let snap = WidgetBridge.snapshot(
            items: (try? c.fetch(FetchDescriptor<ProtocolItem>())) ?? [],
            logs: [log], now: noon, calendar: cal)

        XCTAssertEqual(snap.days.count, 2)
        XCTAssertEqual(snap.days[0].slots.count, 3)                       // 8:00, 21:00, 22:00 today
        XCTAssertEqual(snap.days[0].slots.map(\.minutes), [480, 1260, 1320])  // sorted
        XCTAssertTrue(snap.days[0].slots[0].acted)                        // 8:00 logged
        XCTAssertFalse(snap.days[1].slots.contains { $0.acted })          // tomorrow untouched
    }

    func testStateDerivation() {
        let snap = WidgetSnapshot(generatedAt: noon, days: [
            .init(day: today, slots: [
                .init(name: "BPC-157", minutes: 480, acted: true),
                .init(name: "Semaglutide", minutes: 540, acted: false),
                .init(name: "CJC", minutes: 1260, acted: false),
            ]),
        ])
        let s = snap.state(at: noon, calendar: cal)!
        XCTAssertEqual(s.logged, 1)
        XCTAssertEqual(s.total, 3)
        XCTAssertEqual(s.nextName, "Semaglutide")                         // first un-acted (even if past)
        XCTAssertEqual(s.nextMinutes, 540)
        XCTAssertFalse(s.allDone)

        // Unknown day (snapshot stale past tomorrow) → nil, NEVER a fake rest day:
        // the widget invites opening the app instead of saying "don't dose".
        let inAWeek = cal.date(byAdding: .day, value: 7, to: noon)!
        XCTAssertNil(snap.state(at: inAWeek, calendar: cal))
    }

    func testAllDoneAndRestDay() {
        let done = WidgetSnapshot(generatedAt: noon, days: [
            .init(day: today, slots: [.init(name: "X", minutes: 480, acted: true)])])
        XCTAssertTrue(done.state(at: noon, calendar: cal)!.allDone)

        let rest = WidgetSnapshot(generatedAt: noon, days: [.init(day: today, slots: [])])
        XCTAssertTrue(rest.state(at: noon, calendar: cal)!.isRestDay)    // a REAL same-day empty schedule
    }

    // MARK: v2 (streak · adherence · interactive ledger)

    func testV1JSONStillDecodes() throws {
        // A v1 snapshot on disk (no streak/adherence/itemID) must keep parsing.
        let v1 = """
        {"generatedAt":"2026-06-10T12:00:00Z","days":[
          {"day":"2026-06-10T05:00:00Z","slots":[{"name":"BPC-157","minutes":480,"acted":true}]}]}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let snap = try dec.decode(WidgetSnapshot.self, from: Data(v1.utf8))
        XCTAssertNil(snap.streak)
        XCTAssertNil(snap.adherence)
        XCTAssertNil(snap.days[0].slots[0].itemID)
    }

    func testAdherenceCodes() {
        let c = ctx()
        let item = dailyItem(c, name: "BPC-157", times: [480])
        item.addedAt = cal.date(byAdding: .day, value: -2, to: today)!   // tracking for 3 days
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        let log = DoseLog(); log.itemID = item.id
        log.scheduledDayStart = yesterday; log.scheduledMinutes = 480
        log.statusRaw = "taken"; c.insert(log)

        let codes = WidgetBridge.adherenceCodes(
            items: (try? c.fetch(FetchDescriptor<ProtocolItem>())) ?? [],
            logs: [log], asOf: noon, calendar: cal)

        XCTAssertEqual(codes.count, 30)
        XCTAssertEqual(codes[26], 0)   // before addedAt → rest, never "missed"
        XCTAssertEqual(codes[27], 3)   // tracked, past, un-acted → missed
        XCTAssertEqual(codes[28], 1)   // yesterday fully acted
        XCTAssertEqual(codes[29], 0)   // today un-acted but in progress → never missed
    }

    func testLedgerRoundTripAndReconcile() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("vita-ledger-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let c = ctx()
        let item = dailyItem(c, name: "BPC-157", times: [480])
        let key = WidgetSnapshot.dayKey(for: today)
        WidgetActions.append(.init(itemID: item.id, dayKey: key, minutes: 480, loggedAt: noon),
                             directory: dir)
        XCTAssertEqual(WidgetActions.read(directory: dir).count, 1)

        WidgetBridge.reconcilePendingLogs(context: c, directory: dir)
        var logs = try c.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(logs.count, 1)                       // a REAL DoseLog landed
        XCTAssertEqual(logs[0].statusRaw, "taken")
        XCTAssertTrue(WidgetActions.read(directory: dir).isEmpty)   // ledger cleared

        // Replay the same tap (e.g. stale ledger write): the upsert keeps ONE log.
        WidgetActions.append(.init(itemID: item.id, dayKey: key, minutes: 480, loggedAt: noon),
                             directory: dir)
        WidgetBridge.reconcilePendingLogs(context: c, directory: dir)
        logs = try c.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(logs.count, 1)
    }

    func testTimeTextAndCodableRoundTrip() throws {
        XCTAssertEqual(WidgetSnapshot.timeText(minutes: 0), "12:00 AM")
        XCTAssertEqual(WidgetSnapshot.timeText(minutes: 545), "9:05 AM")
        XCTAssertEqual(WidgetSnapshot.timeText(minutes: 1260), "9:00 PM")

        let snap = WidgetSnapshot(generatedAt: noon, days: [
            .init(day: today, slots: [.init(name: "BPC-157", minutes: 480, acted: false)])])
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let round = try dec.decode(WidgetSnapshot.self, from: try enc.encode(snap))
        XCTAssertEqual(round, snap)
    }
}
