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

    // MARK: - Notification depth (quiet hours, pre-dose lead, late pings)

    private func prefs(quiet: Bool = false, start: Int = 1320, end: Int = 420,
                       lead: Int = 0, late: Bool = true) -> NotificationManager.Prefs {
        .init(quietEnabled: quiet, quietStart: start, quietEnd: end, preLead: lead, latePing: late)
    }

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = cal.date(byAdding: .day, value: dayOffset, to: today)!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testQuietWindowWrapAndBoundaries() {
        let p = prefs(quiet: true)                                  // 22:00 -> 07:00, wraps
        XCTAssertTrue(NotificationManager.inQuietWindow(at(23), prefs: p, calendar: cal))
        XCTAssertTrue(NotificationManager.inQuietWindow(at(3), prefs: p, calendar: cal))
        XCTAssertTrue(NotificationManager.inQuietWindow(at(22), prefs: p, calendar: cal))   // start inclusive
        XCTAssertFalse(NotificationManager.inQuietWindow(at(7), prefs: p, calendar: cal))   // end exclusive
        XCTAssertFalse(NotificationManager.inQuietWindow(at(12), prefs: p, calendar: cal))

        let day = prefs(quiet: true, start: 13 * 60, end: 15 * 60)  // non-wrapping
        XCTAssertTrue(NotificationManager.inQuietWindow(at(14), prefs: day, calendar: cal))
        XCTAssertFalse(NotificationManager.inQuietWindow(at(16), prefs: day, calendar: cal))

        let off = prefs(quiet: true, start: 600, end: 600)          // start == end -> disabled
        XCTAssertFalse(NotificationManager.inQuietWindow(at(10), prefs: off, calendar: cal))
        XCTAssertFalse(NotificationManager.inQuietWindow(at(23), prefs: prefs(), calendar: cal)) // toggle off
    }

    func testShiftToQuietEndCrossesMidnight() {
        let p = prefs(quiet: true)
        // 23:00 tonight shifts to 07:00 TOMORROW.
        let shifted = NotificationManager.shiftedToQuietEnd(at(23), prefs: p, calendar: cal)
        XCTAssertEqual(shifted, at(7, dayOffset: 1))
        // 03:00 shifts to 07:00 the same morning.
        XCTAssertEqual(NotificationManager.shiftedToQuietEnd(at(3), prefs: p, calendar: cal), at(7))
        // Outside the window: untouched.
        XCTAssertEqual(NotificationManager.shiftedToQuietEnd(at(12), prefs: p, calendar: cal), at(12))
    }

    func testNoticesShiftDoseRemindersDoNot() {
        let p = prefs(quiet: true)
        let it = item(.daily, times: [23 * 60])                     // 11 PM dose, inside quiet
        let reminders = NotificationManager.plan(for: [it], logs: [], from: at(12), calendar: cal)
        // Dose reminders keep their exact scheduled time.
        XCTAssertTrue(reminders.allSatisfy {
            cal.component(.hour, from: $0.fireDate) == 23
        })
        // Advisory notices shift to the quiet end.
        let notice = NotificationManager.PlannedNotice(
            id: "vial-low-x-1", title: "t", body: "b", itemID: it.id, fireDate: at(23))
        let shifted = NotificationManager.applyQuietHours(notices: [notice], prefs: p, calendar: cal)
        XCTAssertEqual(shifted.first?.fireDate, at(7, dayOffset: 1))
    }

    func testPreRemindersLeadDropAndIds() {
        let it = item(.daily, times: [9 * 60])
        let reminders = NotificationManager.plan(for: [it], logs: [], from: at(6), calendar: cal)
        let pre = NotificationManager.preReminders(from: reminders, prefs: prefs(lead: 30),
                                                   now: at(6), calendar: cal)
        XCTAssertFalse(pre.isEmpty)
        XCTAssertTrue(pre.allSatisfy { $0.id.hasPrefix("pre-") })
        // Fires 30 minutes before the paired dose reminder.
        XCTAssertEqual(pre.first!.fireDate,
                       reminders.first!.fireDate.addingTimeInterval(-1800))
        // Lead 0 -> none.
        XCTAssertTrue(NotificationManager.preReminders(from: reminders, prefs: prefs(lead: 0),
                                                       now: at(6), calendar: cal).isEmpty)
        // A pre-fire inside quiet hours is dropped, not shifted.
        let nightOwl = item(.daily, times: [23 * 60])
        let nightReminders = NotificationManager.plan(for: [nightOwl], logs: [], from: at(12), calendar: cal)
        let quietPre = NotificationManager.preReminders(
            from: nightReminders, prefs: prefs(quiet: true, lead: 30), now: at(12), calendar: cal)
        XCTAssertTrue(quietPre.isEmpty)     // 22:30 is inside 22:00-07:00
    }

    func testLatePingsDelayIdsAndToggle() {
        let it = item(.daily, times: [9 * 60])
        let reminders = NotificationManager.plan(for: [it], logs: [], from: at(6), calendar: cal)
        let late = NotificationManager.latePings(from: reminders, prefs: prefs(),
                                                 now: at(6), calendar: cal)
        XCTAssertFalse(late.isEmpty)
        XCTAssertTrue(late.allSatisfy { $0.id.hasPrefix("late-") })
        XCTAssertEqual(late.first!.fireDate,
                       reminders.first!.fireDate.addingTimeInterval(45 * 60))
        // One per occurrence (derived 1:1 from the plan).
        XCTAssertEqual(late.count, reminders.count)
        // Toggle off -> none.
        XCTAssertTrue(NotificationManager.latePings(from: reminders, prefs: prefs(late: false),
                                                    now: at(6), calendar: cal).isEmpty)
        // Acted occurrences are structurally excluded (plan already drops them).
        let acted = [log(it, minutes: 9 * 60)]
        let remindersAfterLog = NotificationManager.plan(for: [it], logs: acted, from: at(6), calendar: cal)
        let lateAfter = NotificationManager.latePings(from: remindersAfterLog, prefs: prefs(),
                                                      now: at(6), calendar: cal)
        XCTAssertFalse(lateAfter.contains { cal.isDate($0.fireDate, inSameDayAs: today) })
    }

    /// Structural guard for the historical stale-notification bug: every id any
    /// planner emits must carry a prefix the rebuild sweep manages.
    func testEveryPlannedIdHasManagedPrefix() {
        let injectable = item(.daily, times: [9 * 60])
        let cycled: ProtocolItem = {
            let it = item(.daily, times: [8 * 60], name: "Cycled")
            it.schedule!.cycleOnDays = 5; it.schedule!.cycleOffDays = 2
            it.schedule!.titrationDayStarts = [0, 7]; it.schedule!.titrationDoses = [250, 500]
            return it
        }()
        let vialed = withVial(item(.daily, times: [10 * 60], name: "Vialed"), mg: 1)

        var ids: [String] = []
        let reminders = NotificationManager.plan(for: [injectable, cycled, vialed], logs: [],
                                                 from: at(6), calendar: cal)
        ids += reminders.map(\.id)
        ids += NotificationManager.decisionNotices(for: [cycled], from: at(6), calendar: cal).map(\.id)
        ids += NotificationManager.vialNotices(for: [vialed], logs: [], from: at(6), calendar: cal).map(\.id)
        ids += NotificationManager.preReminders(from: reminders, prefs: prefs(lead: 30),
                                                now: at(6), calendar: cal).map(\.id)
        ids += NotificationManager.latePings(from: reminders, prefs: prefs(),
                                             now: at(6), calendar: cal).map(\.id)
        XCTAssertFalse(ids.isEmpty)
        for id in ids {
            XCTAssertTrue(NotificationManager.managedPrefixes.contains { id.hasPrefix($0) },
                          "unmanaged id would leak: \(id)")
        }
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

    // MARK: - Notification-tap deep link (M47)

    func testDetailItemIDParsesValidUUIDAndRejectsGarbage() {
        let id = UUID()
        XCTAssertEqual(NotificationRouter.detailItemID(fromUserInfoItemID: id.uuidString), id)
        XCTAssertNil(NotificationRouter.detailItemID(fromUserInfoItemID: "not-a-uuid"))
        XCTAssertNil(NotificationRouter.detailItemID(fromUserInfoItemID: ""))
        XCTAssertNil(NotificationRouter.detailItemID(fromUserInfoItemID: nil))
    }

    /// M55: a dose reminder's body tap lands on Today (the log surface), NEVER
    /// the compound-detail editing sheet — even with a perfectly valid itemID.
    /// Only review-a-change notices (DOSE_DECISION) deep-link to detail.
    func testDefaultTapRouteSendsDoseRemindersToTodayAndNoticesToDetail() {
        let id = UUID()
        XCTAssertEqual(NotificationRouter.defaultTapRoute(
            category: NotificationManager.categoryID, itemID: id.uuidString), .today)
        XCTAssertEqual(NotificationRouter.defaultTapRoute(
            category: NotificationManager.decisionCategoryID, itemID: id.uuidString), .detail(id))
        // Garbage or missing ids always degrade to Today, never a broken sheet.
        XCTAssertEqual(NotificationRouter.defaultTapRoute(
            category: NotificationManager.decisionCategoryID, itemID: "not-a-uuid"), .today)
        XCTAssertEqual(NotificationRouter.defaultTapRoute(
            category: NotificationManager.decisionCategoryID, itemID: nil), .today)
        XCTAssertEqual(NotificationRouter.defaultTapRoute(category: "", itemID: id.uuidString), .today)
    }

    /// Source guard: the detail sheet must be driven by RootShell's scene-gated
    /// copy, never directly by the router's pending id (the direct binding
    /// presented mid-foreground-transition and crashed on device, M47).
    func testRootShellGatesDetailSheetOnScenePhase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Vita/App/RootShell.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("presentedItemID != nil"),
                      "Sheet must bind to the scene-gated presentedItemID.")
        XCTAssertFalse(source.contains("get: { router.pendingDetailItemID != nil }"),
                       "Sheet must not bind directly to the router's pending id.")
        XCTAssertTrue(source.contains("scenePhase == .active"),
                      "Pending deep links must wait for an active scene.")
    }

    /// Source guard (M53): scenePhase alone is not enough — on a cold launch the
    /// scene reports .active before the root view is in the window, and the sheet
    /// presentation crashed on device. The guard must ALSO require uiReady (set
    /// after first onAppear settles), the onAppear rescue must re-check the
    /// pending id (onChange misses values set before subscription), and the
    /// router must be @State for stable observation.
    func testRootShellRequiresUIReadyBeforePresenting() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appendingPathComponent("Vita/App/RootShell.swift"),
            encoding: .utf8)
        XCTAssertTrue(source.contains("scenePhase == .active, uiReady"),
                      "Presentation guard must require BOTH an active scene and a settled root view.")
        XCTAssertTrue(source.contains(".onAppear"),
                      "Cold-launch pending ids predate the onChange subscriptions; onAppear must re-check.")
        XCTAssertTrue(source.contains("@State private var router"),
                      "The router must be @State so Observation survives view identity refreshes.")
    }
}
