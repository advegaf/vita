import XCTest
import SwiftData
@testable import Vita

@MainActor
final class AdherenceTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var today = cal.startOfDay(for: Date())
    private lazy var noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func dailyItem(_ c: ModelContext, addedDaysAgo: Int = 60) -> ProtocolItem {
        let item = ProtocolItem(); item.displayName = "BPC"
        item.addedAt = cal.date(byAdding: .day, value: -addedDaysAgo, to: today)!
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "daily"; r.timeSlotsMinutes = [480]
        c.insert(r); item.schedule = r
        return item
    }

    private func log(_ c: ModelContext, _ item: ProtocolItem, daysAgo: Int,
                     status: DoseStatus = .taken) -> DoseLog {
        let l = DoseLog()
        l.itemID = item.id
        l.scheduledDayStart = cal.date(byAdding: .day, value: -daysAgo, to: today)!
        l.scheduledMinutes = 480
        l.statusRaw = status.rawValue
        c.insert(l)
        return l
    }

    private func logs(_ c: ModelContext) -> [DoseLog] { (try? c.fetch(FetchDescriptor<DoseLog>())) ?? [] }

    func testTakenSkippedMissedDays() {
        let c = ctx(); let item = dailyItem(c)
        _ = log(c, item, daysAgo: 1)                       // yesterday taken
        _ = log(c, item, daysAgo: 2, status: .skipped)     // day-2 skipped
        // day-3 unlogged → missed
        let states = Adherence.dayStates(item: item, logs: logs(c), days: 5, asOf: noon, calendar: cal)
        // oldest-first: [day-4, day-3, day-2, day-1, today]
        XCTAssertEqual(states[1], .missed)
        XCTAssertEqual(states[2], .skipped)
        XCTAssertEqual(states[3], .taken)
    }

    func testTodayInProgressNeverMissed() {
        let c = ctx(); let item = dailyItem(c)
        let unacted = Adherence.dayStates(item: item, logs: [], days: 3, asOf: noon, calendar: cal)
        XCTAssertEqual(unacted.last, .notScheduled)        // today unacted = in progress
        _ = log(c, item, daysAgo: 0)
        let acted = Adherence.dayStates(item: item, logs: logs(c), days: 3, asOf: noon, calendar: cal)
        XCTAssertEqual(acted.last, .taken)
    }

    func testRestAndCycleOffDaysNotScheduled() {
        let c = ctx()
        let item = ProtocolItem(); item.addedAt = cal.date(byAdding: .day, value: -10, to: today)!
        c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "eod"; r.timeSlotsMinutes = [480]; r.anchorDate = today
        c.insert(r); item.schedule = r
        let states = Adherence.dayStates(item: item, logs: [], days: 4, asOf: noon, calendar: cal)
        // EOD anchored today: day-3 due(missed), day-2 rest, day-1 due(missed)... wait —
        // parity: today due, yesterday rest, day-2 due, day-3 rest (abs % 2).
        XCTAssertEqual(states[0], .notScheduled)           // day-3 rest
        XCTAssertEqual(states[1], .missed)                 // day-2 due, unlogged
        XCTAssertEqual(states[2], .notScheduled)           // yesterday rest
    }

    func testAddedMidWindowHasNoPhantomMisses() {
        let c = ctx(); let item = dailyItem(c, addedDaysAgo: 2)
        _ = log(c, item, daysAgo: 1)
        let states = Adherence.dayStates(item: item, logs: logs(c), days: 10, asOf: noon, calendar: cal)
        // Days before addedAt (older than day-2) must be notScheduled, not missed.
        XCTAssertTrue(states.prefix(7).allSatisfy { $0 == .notScheduled })
        XCTAssertEqual(states[8], .taken)                  // yesterday
    }

    func testSummaryCountsActedOverScheduled() {
        let c = ctx(); let item = dailyItem(c)
        _ = log(c, item, daysAgo: 1)
        _ = log(c, item, daysAgo: 2, status: .skipped)
        // day-3, day-4 missed; today unresolved (excluded from denominator)
        let s = Adherence.summary(item: item, logs: logs(c), days: 5, asOf: noon, calendar: cal)
        XCTAssertEqual(s.scheduled, 4)                     // 4 past scheduled days
        XCTAssertEqual(s.logged, 2)                        // taken + skipped both count as acted
    }

    func testPRNCountAndDays() {
        let c = ctx()
        let item = ProtocolItem(); item.addedAt = today; c.insert(item)
        let r = ScheduleRule(); r.frequencyRaw = "prn"; c.insert(r); item.schedule = r
        for daysAgo in [0, 0, 3] {
            let l = DoseLog(); l.itemID = item.id; l.isPRN = true
            l.loggedAt = cal.date(byAdding: .day, value: -daysAgo, to: noon)!
            c.insert(l)
        }
        XCTAssertEqual(Adherence.prnCount(item: item, logs: logs(c), days: 30, asOf: noon, calendar: cal), 3)
        let days = Adherence.prnDays(item: item, logs: logs(c), days: 5, asOf: noon, calendar: cal)
        XCTAssertEqual(days[1], .taken)                    // day-3 used
        XCTAssertEqual(days[4], .taken)                    // today used (twice → one dot)
        XCTAssertEqual(days[3], .notScheduled)             // yesterday unused
    }
}
