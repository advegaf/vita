import XCTest
import SwiftData
@testable import Vita

@MainActor
final class TodayRingsTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var today = cal.startOfDay(for: Date())
    private lazy var noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    /// Daily item with morning (8:00) + evening (20:00) slots.
    private func twoSlotItem(_ c: ModelContext) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = "BPC"
        c.insert(item)                                   // insert before wiring the relationship
        let r = ScheduleRule(); r.frequencyRaw = "daily"; r.timeSlotsMinutes = [480, 1200]
        c.insert(r); item.schedule = r
        return item
    }

    private func prnItem(_ c: ModelContext) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = "MT"
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "prn"
        c.insert(r); item.schedule = r
        return item
    }

    private func addLog(_ c: ModelContext, _ item: ProtocolItem, daysAgo: Int, minutes: Int = 480,
                        status: DoseStatus = .taken) {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        let l = DoseLog()
        l.itemID = item.id; l.scheduledDayStart = cal.startOfDay(for: day)
        l.scheduledMinutes = minutes; l.statusRaw = status.rawValue
        c.insert(l)
    }

    private func logs(_ c: ModelContext) -> [DoseLog] { (try? c.fetch(FetchDescriptor<DoseLog>())) ?? [] }

    func testCountsActedAndOverdue() {
        let c = ctx(); let item = twoSlotItem(c)
        addLog(c, item, daysAgo: 0, minutes: 480)        // morning logged
        // evening slot (20:00) is later than noon → due, not overdue
        let s = TodayRings.snapshot(items: [item], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s.dosesTotal, 2)
        XCTAssertEqual(s.dosesActed, 1)
        XCTAssertEqual(s.overdueCount, 0)
        XCTAssertEqual(s.headline, "On track.")
        XCTAssertEqual(s.remainingLine, "One dose left.")
    }

    func testOverdueDrivesCatchUpHeadline() {
        let c = ctx(); let item = twoSlotItem(c)
        // nothing logged: at noon the 8:00 slot is overdue, 20:00 still due
        let s = TodayRings.snapshot(items: [item], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s.overdueCount, 1)
        XCTAssertEqual(s.headline, "One to catch up.")
    }

    func testAllDone() {
        let c = ctx(); let item = twoSlotItem(c)
        addLog(c, item, daysAgo: 0, minutes: 480)
        addLog(c, item, daysAgo: 0, minutes: 1200)
        let s = TodayRings.snapshot(items: [item], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s.dosesActed, 2)
        XCTAssertEqual(s.headline, "All done.")
        XCTAssertEqual(s.doseProgress, 1)
        XCTAssertEqual(s.remainingLine, "All done for today.")
    }

    func testRestDayReadsComplete() {
        let c = ctx()
        let s = TodayRings.snapshot(items: [prnItem(c)], logs: [], asOf: noon, calendar: cal)
        XCTAssertEqual(s.dosesTotal, 0)
        XCTAssertEqual(s.headline, "Rest day.")
        XCTAssertEqual(s.doseProgress, 1, "a rest day is a kept promise, not an empty ring")
        XCTAssertEqual(s.weekProgress, 1)
    }

    func testSkippedCountsAsActed() {
        let c = ctx(); let item = twoSlotItem(c)
        addLog(c, item, daysAgo: 0, minutes: 480, status: .skipped)
        let s = TodayRings.snapshot(items: [item], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s.dosesActed, 1)
    }

    func testWeekAggregatesAcrossItemsAndExcludesPRN() {
        let c = ctx()
        let item = twoSlotItem(c)
        let prn = prnItem(c)
        // 6 past days fully acted (the unresolved today is excluded by Adherence).
        for d in 1...6 { addLog(c, item, daysAgo: d) }
        addLog(c, prn, daysAgo: 2)                       // PRN log must not affect the denominator
        let s = TodayRings.snapshot(items: [item, prn], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s.weekScheduled, 6)
        XCTAssertEqual(s.weekLogged, 6)
        XCTAssertEqual(s.weekProgress, 1)
    }

    func testStreakProgressCapsAtWeek() {
        var s = TodayRingsSnapshot()
        s.streakDays = 21
        XCTAssertEqual(s.streakProgress, 1)
        s.streakDays = 3
        XCTAssertEqual(s.streakProgress, 3.0 / 7.0, accuracy: 0.001)
    }
}
