import XCTest
import SwiftData
@testable import Vita

@MainActor
final class StreakServiceTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var today = cal.startOfDay(for: Date())
    private lazy var noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func dailyItem(_ c: ModelContext) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = "BPC"
        c.insert(item)                                   // insert before wiring the relationship
        let r = ScheduleRule(); r.frequencyRaw = "daily"; r.timeSlotsMinutes = [480]
        c.insert(r); item.schedule = r
        return item
    }

    private func eodItem(_ c: ModelContext) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = "CJC"
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "eod"; r.timeSlotsMinutes = [480]; r.anchorDate = today
        c.insert(r); item.schedule = r
        return item
    }

    private func addLog(_ c: ModelContext, _ item: ProtocolItem, daysAgo: Int, status: DoseStatus = .taken) {
        let day = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        let l = DoseLog()
        l.itemID = item.id; l.scheduledDayStart = cal.startOfDay(for: day)
        l.scheduledMinutes = 480; l.statusRaw = status.rawValue
        c.insert(l)
    }

    private func logs(_ c: ModelContext) -> [DoseLog] { (try? c.fetch(FetchDescriptor<DoseLog>())) ?? [] }

    func testConsecutiveDoneDays() {
        let c = ctx(); let item = dailyItem(c)
        addLog(c, item, daysAgo: 0); addLog(c, item, daysAgo: 1); addLog(c, item, daysAgo: 2)
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 3)
    }

    func testSkippedCountsAsDone() {
        let c = ctx(); let item = dailyItem(c)
        addLog(c, item, daysAgo: 0, status: .skipped); addLog(c, item, daysAgo: 1)
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 2)
    }

    func testUnactedPastDayBreaks() {
        let c = ctx(); let item = dailyItem(c)
        addLog(c, item, daysAgo: 0)                 // today done
        // yesterday MISSING
        addLog(c, item, daysAgo: 2)
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 1)
    }

    func testTodayIncompleteDoesNotBreak() {
        let c = ctx(); let item = dailyItem(c)
        // today NOT logged; yesterday + day-2 done
        addLog(c, item, daysAgo: 1); addLog(c, item, daysAgo: 2)
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 2)
    }

    func testRestDayHoldsStreak() {
        let c = ctx(); let item = eodItem(c)
        // EOD anchored today: today is due, yesterday is a rest day, day-2 is due (unlogged → break).
        addLog(c, item, daysAgo: 0)                 // today done
        let s = StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal)
        XCTAssertEqual(s, 2)                         // today (done) + yesterday (rest) → 2
    }

    func testNoLogsNoStreak() {
        let c = ctx(); let item = dailyItem(c)
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 0)
    }

    func testCycleOffBlockHoldsStreak() {
        let c = ctx(); let item = dailyItem(c)
        // 1 day on / 1 day off, anchored today: today is ON (due), yesterday is OFF (rest).
        let r = item.schedule!
        r.cycleOnDays = 1; r.cycleOffDays = 1; r.cycleUnitRaw = CycleUnit.days.rawValue
        r.anchorDate = today
        addLog(c, item, daysAgo: 0)                 // today (ON) logged
        // day-2 is ON again but unlogged → breaks. today(done) + yesterday(rest) = 2.
        XCTAssertEqual(StreakService.currentStreak(items: [item], logs: logs(c), asOf: noon, calendar: cal), 2)
    }
}
