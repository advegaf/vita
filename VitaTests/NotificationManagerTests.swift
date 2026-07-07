import XCTest
@testable import Vita

@MainActor
final class NotificationManagerTests: XCTestCase {
    private let cal = Calendar.current
    private lazy var today = cal.startOfDay(for: Date())
    private lazy var noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: today)!

    // Detached models (no container) — plan() only reads properties.
    private func item(_ freq: Frequency, times: [Int], weekdays: [Int] = [],
                      name: String = "BPC-157") -> ProtocolItem {
        let it = ProtocolItem()
        it.displayName = name
        it.doseAmount = 250
        it.doseUnitRaw = DoseUnit.mcg.rawValue
        let r = ScheduleRule()
        r.frequencyRaw = freq.rawValue
        r.timeSlotsMinutes = times
        r.weekdays = weekdays
        r.anchorDate = today
        it.schedule = r
        return it
    }

    private func log(_ item: ProtocolItem, minutes: Int, daysFromToday: Int = 0,
                     status: DoseStatus = .taken) -> DoseLog {
        let l = DoseLog()
        l.itemID = item.id
        l.scheduledDayStart = cal.date(byAdding: .day, value: daysFromToday, to: today)!
        l.scheduledMinutes = minutes
        l.statusRaw = status.rawValue
        return l
    }

    private func todayReminders(_ plan: [NotificationManager.PlannedReminder]) -> [NotificationManager.PlannedReminder] {
        plan.filter { cal.isDate($0.fireDate, inSameDayAs: today) }
    }

    private func withVial(_ item: ProtocolItem, mg: Double, reconDaysAgo: Int = 0,
                          budDays: Int = 28) -> ProtocolItem {
        let v = Vial()
        v.compoundSlug = item.compoundSlug
        v.vialMg = mg; v.waterMl = 2
        v.concentrationMgPerMl = mg / 2
        v.reconstitutedAt = cal.date(byAdding: .day, value: -reconDaysAgo, to: today)!
        v.budDays = budDays
        v.item = item; item.vial = v
        return item
    }

    func testVialNoticesLowAndBUDFireOnce() {
        // 1 mg vial at 0.25 mg/dose = 4 doses → low is imminent; BUD 28 days out.
        let it = withVial(item(.daily, times: [8 * 60]), mg: 1)
        let notices = NotificationManager.vialNotices(for: [it], logs: [], from: noon, calendar: cal)
        let ids = notices.map(\.id)
        XCTAssertTrue(ids.contains { $0.hasPrefix("vial-low-") })
        XCTAssertTrue(ids.contains { $0.hasPrefix("vial-bud-") })
        XCTAssertTrue(notices.allSatisfy { $0.fireDate > noon })
        // Deterministic: a second pass yields the same ids (idempotent, no daily nag).
        let again = NotificationManager.vialNotices(for: [it], logs: [], from: noon, calendar: cal)
        XCTAssertEqual(ids, again.map(\.id))
    }

    func testVialNoticesNoLowWhenAmpleSupply() {
        // 100 mg vial = 400 doses; low day is beyond the projection horizon.
        let it = withVial(item(.daily, times: [8 * 60]), mg: 100)
        let notices = NotificationManager.vialNotices(for: [it], logs: [], from: noon, calendar: cal)
        XCTAssertFalse(notices.contains { $0.id.hasPrefix("vial-low-") })
        XCTAssertTrue(notices.contains { $0.id.hasPrefix("vial-bud-") })   // BUD still applies
    }

    func testVialNoticesNoneWithoutVial() {
        let notices = NotificationManager.vialNotices(for: [item(.daily, times: [8 * 60])],
                                                      logs: [], from: noon, calendar: cal)
        XCTAssertTrue(notices.isEmpty)
    }

    func testMaterializedFutureOnly() {
        // Daily with a morning (past at noon) + evening (future) slot.
        let plan = NotificationManager.plan(for: [item(.daily, times: [8 * 60, 21 * 60])],
                                            logs: [], from: noon, calendar: cal)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { $0.fireDate > noon })             // never schedules the past
        XCTAssertEqual(todayReminders(plan).map(\.minutes), [21 * 60])    // today: only the 9pm slot
    }

    func testLoggedOccurrenceExcludedUndoReincludes() {
        let it = item(.daily, times: [21 * 60])
        let unlogged = NotificationManager.plan(for: [it], logs: [], from: noon, calendar: cal)
        XCTAssertEqual(todayReminders(unlogged).count, 1)

        let logged = NotificationManager.plan(for: [it], logs: [log(it, minutes: 21 * 60)], from: noon, calendar: cal)
        XCTAssertTrue(todayReminders(logged).isEmpty)                     // logged → no reminder

        // (undo = no log) → reminder returns, same as `unlogged` above.
        XCTAssertEqual(todayReminders(unlogged).count, 1)
    }

    func testSkippedAlsoExcludes() {
        let it = item(.daily, times: [21 * 60])
        let plan = NotificationManager.plan(for: [it], logs: [log(it, minutes: 21 * 60, status: .skipped)],
                                            from: noon, calendar: cal)
        XCTAssertTrue(todayReminders(plan).isEmpty)
    }

    func testPrnMakesNone() {
        XCTAssertTrue(NotificationManager.plan(for: [item(.prn, times: [21 * 60])],
                                               logs: [], from: noon, calendar: cal).isEmpty)
    }

    func testWeeklyOnlyOnChosenDay() {
        let wd = cal.component(.weekday, from: today)
        let plan = NotificationManager.plan(for: [item(.weekly, times: [21 * 60], weekdays: [wd])],
                                            logs: [], from: noon, calendar: cal)
        XCTAssertFalse(plan.isEmpty)
        XCTAssertTrue(plan.allSatisfy { cal.component(.weekday, from: $0.fireDate) == wd })
    }

    func testBodyAndTitle() {
        let plan = NotificationManager.plan(for: [item(.daily, times: [21 * 60])], logs: [], from: noon, calendar: cal)
        XCTAssertTrue(plan[0].body.contains("250 mcg"))
        XCTAssertTrue(plan[0].title.contains("BPC-157"))
    }

    func testDeterministicIDs() {
        let it = item(.daily, times: [21 * 60])
        let a = NotificationManager.plan(for: [it], logs: [], from: noon, calendar: cal).map(\.id)
        let b = NotificationManager.plan(for: [it], logs: [], from: noon, calendar: cal).map(\.id)
        XCTAssertEqual(a, b)
    }

    func testCappedUnderPendingLimit() {
        let items = (0..<30).map { _ in item(.daily, times: [6 * 60, 9 * 60, 12 * 60, 18 * 60, 21 * 60]) }
        XCTAssertLessThanOrEqual(
            NotificationManager.plan(for: items, logs: [], from: noon, calendar: cal).count,
            NotificationManager.maxPending)
    }

    // MARK: - Action helpers

    func testStatusForAction() {
        XCTAssertEqual(NotificationManager.status(forAction: "LOG_DOSE"), .taken)
        XCTAssertEqual(NotificationManager.status(forAction: "SKIP_DOSE"), .skipped)
        XCTAssertNil(NotificationManager.status(forAction: "SNOOZE_15"))
    }

    func testOccurrenceFromUserInfo() {
        let id = UUID()
        let ti = today.timeIntervalSince1970
        let occ = NotificationManager.occurrence(from: ["itemID": id.uuidString, "minutes": 480, "day": ti])
        XCTAssertEqual(occ?.itemID, id)
        XCTAssertEqual(occ?.minutes, 480)
        XCTAssertEqual(occ?.day.timeIntervalSince1970 ?? 0, ti, accuracy: 1)
        XCTAssertNil(NotificationManager.occurrence(from: ["minutes": 480]))
    }

    func testOccurrencePrefersZoneIndependentDayKey() {
        // After a timezone change, the epoch (some past zone's midnight) resolves
        // to the WRONG local day — the dayKey components must win.
        let id = UUID()
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: today)
        let key = (c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0)
        let misleadingEpoch = today.addingTimeInterval(-10 * 3600).timeIntervalSince1970 // "yesterday" in epoch terms
        let occ = NotificationManager.occurrence(from:
            ["itemID": id.uuidString, "minutes": 480, "day": misleadingEpoch, "dayKey": key])
        XCTAssertEqual(occ?.day, today)                       // dayKey wins over the epoch
        XCTAssertEqual(NotificationManager.date(fromDayKey: key), today)
        XCTAssertNil(NotificationManager.date(fromDayKey: 0))
    }

    // MARK: - M9 change notices + titrated reminder bodies

    func testTitrationStepUpNoticeDayBefore() {
        let it = item(.daily, times: [9 * 60])       // anchor = today
        let r = it.schedule!
        it.doseUnitRaw = DoseUnit.mg.rawValue
        r.titrationDayStarts = [0, 3]                 // step up on day 3 → day-2 notice fires in the future
        r.titrationDoses = [0.25, 0.5]
        let notices = NotificationManager.decisionNotices(for: [it], from: noon, calendar: cal)
        XCTAssertTrue(notices.contains { $0.title.contains("Dose change") && $0.body.contains("up") })
        XCTAssertTrue(notices.allSatisfy { $0.fireDate > noon })   // future-only
    }

    func testCycleResumeNotice() {
        let it = item(.daily, times: [9 * 60])       // anchor = today
        let r = it.schedule!
        r.cycleOnDays = 5; r.cycleOffDays = 2; r.cycleUnitRaw = CycleUnit.days.rawValue
        let notices = NotificationManager.decisionNotices(for: [it], from: noon, calendar: cal)
        XCTAssertTrue(notices.contains { $0.body.contains("resumes") })   // day 7 = first ON after the off block
    }

    func testNoNoticesForPlainItem() {
        let it = item(.daily, times: [9 * 60])
        XCTAssertTrue(NotificationManager.decisionNotices(for: [it], from: noon, calendar: cal).isEmpty)
    }

    func testReminderBodyUsesTitratedDose() {
        let it = item(.daily, times: [21 * 60])       // anchor today, evening (future) slot
        let r = it.schedule!
        it.doseUnitRaw = DoseUnit.mg.rawValue
        r.titrationDayStarts = [0]
        r.titrationDoses = [0.5]
        let plan = NotificationManager.plan(for: [it], logs: [], from: noon, calendar: cal)
        XCTAssertTrue(plan.first?.body.contains("0.5 mg") ?? false)
    }
}
