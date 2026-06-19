import XCTest
@testable import Vita

final class ScheduleServiceTests: XCTestCase {

    // MARK: Block boundaries

    func testBlockBoundaries() {
        XCTAssertEqual(DayBlock.from(minutes: 0), .morning)
        XCTAssertEqual(DayBlock.from(minutes: 11 * 60 + 59), .morning)   // 11:59
        XCTAssertEqual(DayBlock.from(minutes: 12 * 60), .midday)      // 12:00
        XCTAssertEqual(DayBlock.from(minutes: 16 * 60 + 59), .midday) // 16:59
        XCTAssertEqual(DayBlock.from(minutes: 17 * 60), .night)        // 17:00
        XCTAssertEqual(DayBlock.from(minutes: 23 * 60 + 59), .night)
    }

    func testDefaultMinutesLandInTheirBlock() {
        XCTAssertEqual(DayBlock.from(minutes: DayBlock.morning.defaultMinutes), .morning)
        XCTAssertEqual(DayBlock.from(minutes: DayBlock.midday.defaultMinutes), .midday)
        XCTAssertEqual(DayBlock.from(minutes: DayBlock.night.defaultMinutes), .night)
    }

    // MARK: Frequency due-day logic

    private func rule(_ f: Frequency, anchor: Date = Date(timeIntervalSince1970: 0),
                      weekdays: [Int] = []) -> ScheduleRule {
        let r = ScheduleRule()
        r.frequencyRaw = f.rawValue
        r.anchorDate = anchor
        r.weekdays = weekdays
        r.timeSlotsMinutes = [8 * 60]
        return r
    }

    func testDailyAlwaysDue() {
        let r = rule(.daily)
        for offset in 0..<5 {
            let d = Calendar.current.date(byAdding: .day, value: offset, to: Date())!
            XCTAssertTrue(ScheduleService.isDueDay(r, on: d))
        }
    }

    func testPrnNeverDue() {
        let r = rule(.prn)
        XCTAssertFalse(ScheduleService.isDueDay(r, on: Date()))
    }

    func testEodAlternates() {
        let cal = Calendar.current
        let anchor = cal.startOfDay(for: Date())
        let r = rule(.eod, anchor: anchor)
        XCTAssertTrue(ScheduleService.isDueDay(r, on: anchor))                                   // day 0
        XCTAssertFalse(ScheduleService.isDueDay(r, on: cal.date(byAdding: .day, value: 1, to: anchor)!)) // day 1
        XCTAssertTrue(ScheduleService.isDueDay(r, on: cal.date(byAdding: .day, value: 2, to: anchor)!))  // day 2
        XCTAssertTrue(ScheduleService.isDueDay(r, on: cal.date(byAdding: .day, value: -2, to: anchor)!)) // symmetric back
    }

    func testWeeklyOnlyOnChosenDays() {
        // Pick "Sunday" (weekday 1). Find a known Sunday + a known Monday.
        let cal = Calendar.current
        let r = rule(.weekly, weekdays: [1]) // Sunday
        // 2024-01-07 is a Sunday, 2024-01-08 a Monday.
        let sunday = DateComponents(calendar: cal, year: 2024, month: 1, day: 7).date!
        let monday = DateComponents(calendar: cal, year: 2024, month: 1, day: 8).date!
        XCTAssertTrue(ScheduleService.isDueDay(r, on: sunday))
        XCTAssertFalse(ScheduleService.isDueDay(r, on: monday))
    }

    // MARK: Occurrences

    func testMultiBlockProducesMultiplePins() {
        let item = ProtocolItem()
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = [8 * 60, 21 * 60]   // AM + PM
        item.schedule = r
        let occ = ScheduleService.occurrences(for: item, on: Date())
        XCTAssertEqual(occ.count, 2)
        XCTAssertEqual(occ.map(\.block).sorted { $0.rawValue < $1.rawValue }, [.morning, .night])
    }

    func testPrnProducesNoOccurrences() {
        let item = ProtocolItem()
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.prn.rawValue
        r.timeSlotsMinutes = [8 * 60]
        item.schedule = r
        XCTAssertTrue(ScheduleService.occurrences(for: item, on: Date()).isEmpty)
    }

    func testCadenceLabel() {
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = [8 * 60, 21 * 60]
        XCTAssertEqual(ScheduleService.cadenceLabel(for: r), "Daily at 8:00 AM, 9:00 PM")

        let w = ScheduleRule()
        w.frequencyRaw = Frequency.weekly.rawValue
        w.weekdays = [1, 5]              // Sun, Thu
        w.timeSlotsMinutes = [9 * 60]
        XCTAssertEqual(ScheduleService.cadenceLabel(for: w), "Weekly on Sun, Thu at 9:00 AM")
    }

    // MARK: - M9 cycles + titration

    private var cal: Calendar { .current }
    private var cycleStart: Date { cal.startOfDay(for: Date(timeIntervalSince1970: 1_600_000_000)) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cycleStart)! }

    private func cycledRule(onDays: Int, offDays: Int, unit: CycleUnit, start: Date) -> ScheduleRule {
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = [8 * 60]
        r.anchorDate = start
        r.cycleOnDays = onDays
        r.cycleOffDays = offDays
        r.cycleUnitRaw = unit.rawValue
        return r
    }

    private func titratingItem(starts: [Int], doses: [Double], base: Double, start: Date) -> ProtocolItem {
        let it = ProtocolItem()
        it.doseAmount = base
        it.doseUnitRaw = DoseUnit.mg.rawValue
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.weekly.rawValue
        r.anchorDate = start
        r.titrationDayStarts = starts
        r.titrationDoses = doses
        it.schedule = r
        return it
    }

    func testCycleGateDays() {
        let r = cycledRule(onDays: 5, offDays: 2, unit: .days, start: cycleStart)
        for d in 0..<5 { XCTAssertFalse(ScheduleService.isResting(r, on: day(d)), "day \(d) should be ON") }
        XCTAssertTrue(ScheduleService.isResting(r, on: day(5)))
        XCTAssertTrue(ScheduleService.isResting(r, on: day(6)))
        XCTAssertFalse(ScheduleService.isResting(r, on: day(7)))          // next period ON
        XCTAssertTrue(ScheduleService.isDueDay(r, on: day(4)))
        XCTAssertFalse(ScheduleService.isDueDay(r, on: day(5)))           // off-block → nothing due
    }

    func testCycleGateWeeks() {
        let r = cycledRule(onDays: 14, offDays: 7, unit: .weeks, start: cycleStart)
        XCTAssertFalse(ScheduleService.isResting(r, on: day(13)))
        XCTAssertTrue(ScheduleService.isResting(r, on: day(14)))
        XCTAssertTrue(ScheduleService.isResting(r, on: day(20)))
        XCTAssertFalse(ScheduleService.isResting(r, on: day(21)))
    }

    func testCycleComposesWithWeekly() {
        // Weekly-Sunday whose cycle rests on that Sunday → resting wins, not due.
        let sunday = DateComponents(calendar: cal, year: 2024, month: 1, day: 7).date!  // a Sunday
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.weekly.rawValue
        r.weekdays = [1]
        r.timeSlotsMinutes = [9 * 60]
        r.cycleOnDays = 7; r.cycleOffDays = 7
        r.cycleUnitRaw = CycleUnit.weeks.rawValue
        r.anchorDate = cal.date(byAdding: .day, value: -7, to: sunday)!  // sunday lands in the OFF week
        XCTAssertTrue(ScheduleService.isResting(r, on: sunday))
        XCTAssertFalse(ScheduleService.isDueDay(r, on: sunday))
    }

    func testContinuousWhenNoCycle() {
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = [8 * 60]
        XCTAssertFalse(r.hasCycle)
        XCTAssertFalse(ScheduleService.isResting(r, on: day(3)))
        XCTAssertTrue(ScheduleService.isDueDay(r, on: day(3)))
        XCTAssertNil(ScheduleService.cycleStatus(for: r, on: day(3)))
    }

    func testCycleStatusOn() {
        let r = cycledRule(onDays: 56, offDays: 28, unit: .weeks, start: cycleStart)
        let s = ScheduleService.cycleStatus(for: r, on: day(14))!
        XCTAssertEqual(s.phase, .on)
        XCTAssertEqual(s.indexInUnit, 3)
        XCTAssertEqual(s.totalUnits, 8)
        XCTAssertEqual(s.daysLeftInPhase, 42)
        XCTAssertEqual(s.chipText, "wk 3/8")
        XCTAssertTrue(s.unitIsWeeks)
    }

    func testCycleStatusResting() {
        let r = cycledRule(onDays: 56, offDays: 28, unit: .weeks, start: cycleStart)
        let s = ScheduleService.cycleStatus(for: r, on: day(60))!   // phaseDay 60 → off
        XCTAssertEqual(s.phase, .resting)
        XCTAssertEqual(s.daysLeftInPhase, 24)                       // 28 - (60-56)
        XCTAssertEqual(s.chipText, "rest")
        XCTAssertEqual(s.resumesOn.map { cal.startOfDay(for: $0) }, day(84))
    }

    func testActiveDose() {
        let it = titratingItem(starts: [7, 28, 56], doses: [0.25, 0.5, 1.0], base: 0.1, start: cycleStart)
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(0)), 0.1)    // before first step → base
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(7)), 0.25)
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(30)), 0.5)
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(100)), 1.0)
    }

    func testActiveDoseEmptyTitration() {
        let it = ProtocolItem()
        it.doseAmount = 0.3
        let r = ScheduleRule(); r.frequencyRaw = "daily"; it.schedule = r
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(10)), 0.3)
    }

    func testActiveDoseUnsortedSteps() {
        let it = titratingItem(starts: [56, 7, 28], doses: [1.0, 0.25, 0.5], base: 0.1, start: cycleStart)
        XCTAssertEqual(ScheduleService.activeDose(for: it, on: day(30)), 0.5)   // sorts internally
    }

    func testNextTitration() {
        let it = titratingItem(starts: [7, 28, 56], doses: [0.25, 0.5, 1.0], base: 0.1, start: cycleStart)
        let n = ScheduleService.nextTitration(for: it, on: day(10))!
        XCTAssertEqual(n.dose, 0.5)
        XCTAssertEqual(n.weeksAway, 3)                                          // (28-10+6)/7
        XCTAssertNil(ScheduleService.nextTitration(for: it, on: day(60)))       // past the last step
    }

    func testStepStartAndResumeDay() {
        let it = titratingItem(starts: [7, 28], doses: [0.25, 0.5], base: 0.1, start: cycleStart)
        let r = it.schedule!
        XCTAssertTrue(ScheduleService.isStepStart(r, on: day(28)))
        XCTAssertFalse(ScheduleService.isStepStart(r, on: day(27)))

        let cyc = cycledRule(onDays: 5, offDays: 2, unit: .days, start: cycleStart)
        XCTAssertTrue(ScheduleService.isResumeDay(cyc, on: day(7)))   // day6 rest → day7 on
        XCTAssertFalse(ScheduleService.isResumeDay(cyc, on: day(8)))  // day7 on → day8 on
    }

    func testOverdueLabelRounding() {
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 45), "45m late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 59), "59m late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 60), "1h late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 135), "2h 15m late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 47 * 60 + 59), "47h 59m late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: 48 * 60), "2d late")
        XCTAssertEqual(ScheduleService.overdueLabel(minutesLate: -5), "0m late")
    }

    func testTitrationLadder() {
        let it = titratingItem(starts: [7, 28, 56], doses: [0.25, 0.5, 1.0], base: 0.1, start: cycleStart)
        let ladder = ScheduleService.titrationLadder(for: it, on: day(30))
        XCTAssertEqual(ladder.count, 3)
        XCTAssertEqual(ladder.map(\.weekStart), [2, 5, 9])
        XCTAssertTrue(ladder[0].isPast)
        XCTAssertTrue(ladder[1].isCurrent)
        XCTAssertFalse(ladder[2].isPast)
        XCTAssertFalse(ladder[2].isCurrent)
    }
}
