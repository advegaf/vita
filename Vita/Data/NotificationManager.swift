import Foundation
import SwiftData
import SwiftUI
import UserNotifications

/// Routes notification taps + lock-screen actions. Log/Skip write the same DoseLog
/// as the in-app tap (shared DoseLogger); tapping the body opens that dose's detail.
@MainActor
@Observable
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()
    var pendingTab: AppTab?
    var pendingDetailItemID: UUID?
    /// Prefills the chat input (never auto-sends) — set by cross-links like the
    /// lab marker's "Ask vita" alongside `pendingTab = .chat`.
    var pendingChatPrompt: String?
    /// Chat owns the focus source, while the root owns the floating navigation.
    /// Keeping this transient signal in the shared router makes tab-bar hiding
    /// deterministic even when UIKit keyboard notifications are delayed.
    var isChatInputFocused = false
    var container: ModelContainer?

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let log = UNNotificationAction(identifier: "LOG_DOSE", title: "Log", options: [])
        let skip = UNNotificationAction(identifier: "SKIP_DOSE", title: "Skip", options: [])
        let snooze = UNNotificationAction(identifier: "SNOOZE_15", title: "Snooze 15m", options: [])
        let category = UNNotificationCategory(identifier: "DOSE_REMINDER",
                                              actions: [log, skip, snooze],
                                              intentIdentifiers: [], options: [])
        // Review-only change notices (titration step-up / cycle resume): no actions.
        let decision = UNNotificationCategory(identifier: "DOSE_DECISION", actions: [],
                                              intentIdentifiers: [], options: [])
        center.setNotificationCategories([category, decision])
    }

    // NOTE (M53): these delegate methods must use the completionHandler variants,
    // NOT the async ones. With `nonisolated async`, Swift resumes UIKit's implicit
    // completion on a background executor, and UIKit's follow-up snapshot /
    // state-restoration work (_updateStateRestorationArchive...) asserts off-main
    // and aborts: SIGABRT on EVERY notification tap, cold or warm. The handlers
    // below hop to the main actor and invoke the completion there.

    // Show banners even while the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // The imported ObjC block is not @Sendable; it is a one-shot heap block,
        // safe to invoke once from the main actor.
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in done([.banner, .sound]) }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        // Resolve the Sendable occurrence (dayKey-aware) before hopping actors.
        let occ = NotificationManager.occurrence(from: userInfo)
        let itemID = userInfo["itemID"] as? String

        // Snooze reuses the fired (non-Sendable) content; UNUserNotificationCenter
        // is thread-safe, so schedule here rather than carry it across the hop.
        if action == "SNOOZE_15" {
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            let req = UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)",
                                            content: response.notification.request.content, trigger: trigger)
            UNUserNotificationCenter.current().add(req)
        }

        // Same one-shot ObjC block situation as willPresent above.
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            switch action {
            case "LOG_DOSE", "SKIP_DOSE":
                handleLog(action: action, occ: occ)
            case UNNotificationDefaultActionIdentifier:
                if let id = NotificationRouter.detailItemID(fromUserInfoItemID: itemID) {
                    pendingDetailItemID = id
                } else {
                    pendingTab = .today
                }
            default:
                break
            }
            // On main: UIKit runs snapshot/state work when this fires.
            done()
        }
    }

    /// Pure, testable parse of a reminder's deep-link target. RootShell applies
    /// the resulting pending id only once the scene is active (the sheet must
    /// never present mid-foreground-transition; device crash, M47).
    nonisolated static func detailItemID(fromUserInfoItemID raw: String?) -> UUID? {
        raw.flatMap(UUID.init(uuidString:))
    }

    private func handleLog(action: String, occ: (itemID: UUID, minutes: Int, day: Date)?) {
        guard let status = NotificationManager.status(forAction: action),
              let occ, let container else { return }
        let context = container.mainContext
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        guard let item = items.first(where: { $0.id == occ.itemID }) else { return }
        DoseLogger(context: context).log(
            item: item, occurrence: DoseOccurrence(itemID: occ.itemID, minutes: occ.minutes),
            on: occ.day, status: status)
    }
}

/// Schedules local dose reminders from the stack. Every reminder is materialized
/// as a concrete, non-repeating fire date over a rolling window, and an occurrence
/// that already has a DoseLog (taken/skipped) is skipped — so logging a dose (in
/// app or from a notification) makes its reminder disappear, and undo brings it back.
@MainActor
enum NotificationManager {

    // 21 days (was 14): a two-week trip with the app unopened left the back half
    // unreminded. The 60-pending cap still prefix-limits dense stacks safely.
    static let windowDays = 21
    static let maxPending = 60          // stay under the iOS 64-pending cap
    static let categoryID = "DOSE_REMINDER"

    /// EVERY id prefix this manager plans. The rebuild sweep removes only these, so
    /// a planner emitting an unlisted prefix would leak stale requests forever —
    /// the exhaustive-prefix test in NotificationManagerTests guards this invariant.
    nonisolated static let managedPrefixes = ["dose-", "titr-", "resume-", "vial-", "pre-", "late-"]

    struct PlannedReminder: Equatable {
        var id: String
        var title: String
        var body: String
        var itemID: UUID
        var minutes: Int
        var fireDate: Date
    }

    // MARK: Build (pure) — future, un-acted occurrences across the window

    static func plan(for items: [ProtocolItem], logs: [DoseLog], from now: Date = Date(),
                     calendar: Calendar = .current) -> [PlannedReminder] {
        var out: [PlannedReminder] = []
        // Indexed acted-occurrence lookups — this runs after EVERY dose log, and the
        // log table grows forever (14 days × items × slots × a linear scan otherwise).
        let acted = Set(logs.filter { !$0.isPRN }.map {
            StreakService.actedKey(itemID: $0.itemID, day: $0.scheduledDayStart,
                                   minutes: $0.scheduledMinutes, calendar: calendar)
        })
        for item in items {
            guard let rule = item.schedule, rule.frequency != .prn else { continue }
            for dayOffset in 0..<windowDays {
                guard let day = calendar.date(byAdding: .day, value: dayOffset,
                                              to: calendar.startOfDay(for: now)) else { continue }
                guard ScheduleService.isDueDay(rule, on: day, calendar: calendar) else { continue }
                let dayStart = calendar.startOfDay(for: day)
                for m in rule.timeSlotsMinutes.sorted() {
                    guard let fire = calendar.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: day),
                          fire > now else { continue }
                    // Already taken or skipped → no reminder.
                    if acted.contains(StreakService.actedKey(itemID: item.id, day: dayStart,
                                                             minutes: m, calendar: calendar)) { continue }
                    out.append(PlannedReminder(
                        id: Self.reminderID(itemID: item.id, day: dayStart, minutes: m, calendar: calendar),
                        title: "Time to pin \(item.displayName)", body: reminderBody(item, on: dayStart),
                        itemID: item.id, minutes: m, fireDate: fire))
                }
            }
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    nonisolated private static func dayKey(_ day: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    /// y*10000+m*100+d back to a local startOfDay. Zone-independent, unlike an
    /// epoch of some past timezone's midnight.
    nonisolated static func date(fromDayKey key: Int, calendar: Calendar = .current) -> Date? {
        guard key > 0 else { return nil }
        var c = DateComponents()
        c.year = key / 10_000
        c.month = (key / 100) % 100
        c.day = key % 100
        return calendar.date(from: c)
    }

    /// Deterministic reminder id for a dose occurrence — shared with `DoseLogger`
    /// so logging in-app can also clear the already-DELIVERED banner.
    nonisolated static func reminderID(itemID: UUID, day: Date, minutes: Int,
                                       calendar: Calendar = .current) -> String {
        "dose-\(itemID.uuidString)-\(dayKey(calendar.startOfDay(for: day), calendar))-\(minutes)"
    }

    private static func reminderBody(_ item: ProtocolItem, on day: Date) -> String {
        item.doseWithDrawText(on: day)
    }

    // MARK: Change notices (review-only: titration step-up + cycle resume)

    static let decisionCategoryID = "DOSE_DECISION"

    struct PlannedNotice: Equatable {
        var id: String
        var title: String
        var body: String
        var itemID: UUID
        var fireDate: Date
    }

    static func decisionNotices(for items: [ProtocolItem], from now: Date = Date(),
                                calendar: Calendar = .current) -> [PlannedNotice] {
        var out: [PlannedNotice] = []
        for item in items {
            guard let rule = item.schedule, rule.hasCycle || rule.hasTitration else { continue }
            let firstSlot = rule.timeSlotsMinutes.min()
            let hour = firstSlot.map { $0 / 60 } ?? 9
            let minute = firstSlot.map { $0 % 60 } ?? 0
            for dayOffset in 0..<windowDays {
                guard let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) else { continue }
                let dayStart = calendar.startOfDay(for: day)
                guard let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart),
                      fire > now else { continue }
                // (a) Titration: notify the DAY BEFORE a step start.
                if rule.hasTitration, let tomorrow = calendar.date(byAdding: .day, value: 1, to: dayStart),
                   ScheduleService.isStepStart(rule, on: tomorrow, calendar: calendar) {
                    let todayDose = ScheduleService.activeDose(for: item, on: dayStart, calendar: calendar)
                    let newDose = ScheduleService.activeDose(for: item, on: tomorrow, calendar: calendar)
                    if newDose != todayDose {
                        let dir = newDose > todayDose ? "up" : "down"
                        out.append(PlannedNotice(
                            id: "titr-\(item.id.uuidString)-\(dayKey(dayStart, calendar))",
                            title: "Dose change tomorrow",
                            body: "\(item.displayName) steps \(dir) to \(vtFormatNumber(newDose)) \(item.doseUnit.label) tomorrow.",
                            itemID: item.id, fireDate: fire))
                    }
                }
                // (b) Cycle resume: the first ON day after an OFF block.
                if rule.hasCycle, ScheduleService.isResumeDay(rule, on: dayStart, calendar: calendar) {
                    out.append(PlannedNotice(
                        id: "resume-\(item.id.uuidString)-\(dayKey(dayStart, calendar))",
                        title: "Back on today",
                        body: "\(item.displayName) resumes today.",
                        itemID: item.id, fireDate: fire))
                }
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: Vial notices (low supply + beyond-use), one-shot per vial

    /// Passive notices for a vial running low or reaching its beyond-use day. Both fire
    /// on deterministic future mornings (projected low-day / BUD-day) with ids keyed to
    /// the reconstitution day, so a rebuild reschedules the SAME notice instead of
    /// minting a new one daily; once the morning passes and it fires, the past fire date
    /// drops it from future rebuilds. The in-app VialCard carries the info regardless.
    static func vialNotices(for items: [ProtocolItem], logs: [DoseLog], from now: Date = Date(),
                            calendar: Calendar = .current) -> [PlannedNotice] {
        var out: [PlannedNotice] = []
        for item in items {
            guard let vial = item.vial else { continue }
            let itemLogs = logs.filter { $0.compoundSlug == vial.compoundSlug }
            let s = VialEngine.status(item: item, vial: vial, logs: itemLogs, asOf: now, calendar: calendar)
            let reconKey = dayKey(calendar.startOfDay(for: vial.reconstitutedAt), calendar)
            let firstSlot = item.schedule?.timeSlotsMinutes.min()
            let hour = firstSlot.map { $0 / 60 } ?? 9
            let minute = firstSlot.map { $0 % 60 } ?? 0

            // (a) Low supply: fire on the morning supply is projected to reach the threshold.
            if let n = s.dosesRemaining, n > VialEngine.lowDosesThreshold,
               let lowDay = VialEngine.dateAfterDoses(item: item, count: n - VialEngine.lowDosesThreshold,
                                                      from: now, logs: itemLogs, calendar: calendar),
               let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0,
                                        of: calendar.startOfDay(for: lowDay)), fire > now {
                out.append(PlannedNotice(
                    id: "vial-low-\(item.id.uuidString)-\(reconKey)",
                    title: "\(item.displayName) vial is running low",
                    body: "About \(VialEngine.lowDosesThreshold) doses left at your current dose. Worth planning a refill.",
                    itemID: item.id, fireDate: fire))
            }

            // (b) Beyond-use: fire on the BUD-day morning (educational, never "expired").
            if let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0,
                                        of: calendar.startOfDay(for: s.budDate)), fire > now {
                out.append(PlannedNotice(
                    id: "vial-bud-\(item.id.uuidString)-\(reconKey)",
                    title: "Day \(vial.budDays) since reconstitution",
                    body: "Your \(item.displayName) vial reaches the \(vial.budDays)-day mark many references use. Check your source.",
                    itemID: item.id, fireDate: fire))
            }
        }
        return out.sorted { $0.fireDate < $1.fireDate }
    }

    // MARK: Notification depth (quiet hours, pre-dose lead, overdue re-ping) — pure

    /// Value-type prefs so the planners stay container-free and testable.
    struct Prefs: Equatable, Sendable {
        var quietEnabled = false
        var quietStart = 1320      // minutes-from-midnight
        var quietEnd = 420
        var preLead = 0            // minutes before the dose; 0 = off
        var latePing = true

        @MainActor static func from(_ s: AppSettings) -> Prefs {
            Prefs(quietEnabled: s.quietHoursEnabled, quietStart: s.quietStartMinutes,
                  quietEnd: s.quietEndMinutes, preLead: s.preDoseLeadMinutes,
                  latePing: s.latePingEnabled)
        }
    }

    /// True when `date` falls inside the quiet window. Handles the midnight wrap
    /// (start > end spans midnight); start == end means effectively disabled.
    nonisolated static func inQuietWindow(_ date: Date, prefs: Prefs,
                                          calendar: Calendar = .current) -> Bool {
        guard prefs.quietEnabled, prefs.quietStart != prefs.quietEnd else { return false }
        let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if prefs.quietStart < prefs.quietEnd {
            return m >= prefs.quietStart && m < prefs.quietEnd
        }
        return m >= prefs.quietStart || m < prefs.quietEnd   // wraps midnight
    }

    /// The end of the quiet window containing (or after) `date` — where an advisory
    /// notice shifts to. Adds a day when the window wraps past midnight.
    nonisolated static func shiftedToQuietEnd(_ date: Date, prefs: Prefs,
                                              calendar: Calendar = .current) -> Date {
        guard inQuietWindow(date, prefs: prefs, calendar: calendar) else { return date }
        let m = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let dayStart = calendar.startOfDay(for: date)
        // In a wrapping window, times at/after quietStart resolve to TOMORROW's end.
        let endsTomorrow = prefs.quietStart > prefs.quietEnd && m >= prefs.quietStart
        let endDay = endsTomorrow
            ? (calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart) : dayStart
        return calendar.date(bySettingHour: prefs.quietEnd / 60, minute: prefs.quietEnd % 60,
                             second: 0, of: endDay) ?? date
    }

    /// Advisory notices (titr/resume/vial) shift out of quiet hours; dose reminders
    /// are NEVER shifted (the user scheduled that time).
    nonisolated static func applyQuietHours(notices: [PlannedNotice], prefs: Prefs,
                                            calendar: Calendar = .current) -> [PlannedNotice] {
        notices.map { n in
            var out = n
            out.fireDate = shiftedToQuietEnd(n.fireDate, prefs: prefs, calendar: calendar)
            return out
        }
    }

    /// "Coming up" lead reminders derived 1:1 from the dose plan. Dropped inside
    /// quiet hours (a shifted pre-alert could land after the dose itself) and when
    /// already past. Same userInfo/category as the dose reminder so Log works early.
    static func preReminders(from reminders: [PlannedReminder], prefs: Prefs,
                             now: Date = Date(),
                             calendar: Calendar = .current) -> [PlannedReminder] {
        guard prefs.preLead > 0 else { return [] }
        return reminders.compactMap { r in
            let fire = r.fireDate.addingTimeInterval(-Double(prefs.preLead) * 60)
            guard fire > now, !inQuietWindow(fire, prefs: prefs, calendar: calendar) else { return nil }
            return PlannedReminder(
                id: "pre-" + r.id.dropFirst("dose-".count),
                title: "Coming up: \(r.title.replacingOccurrences(of: "Time to pin ", with: ""))",
                body: r.body, itemID: r.itemID, minutes: r.minutes, fireDate: fire)
        }
    }

    /// One gentle follow-up ~45 minutes after an unacted dose reminder. Structural
    /// one-per-occurrence: deterministic id + the source plan already excludes acted
    /// occurrences, and every log triggers a rebuild that sweeps stale ids.
    static let latePingDelayMinutes = 45

    static func latePings(from reminders: [PlannedReminder], prefs: Prefs,
                          now: Date = Date(),
                          calendar: Calendar = .current) -> [PlannedReminder] {
        guard prefs.latePing else { return [] }
        return reminders.compactMap { r in
            let fire = r.fireDate.addingTimeInterval(Double(latePingDelayMinutes) * 60)
            guard fire > now, !inQuietWindow(fire, prefs: prefs, calendar: calendar) else { return nil }
            let name = r.title.replacingOccurrences(of: "Time to pin ", with: "")
            let time = DoseOccurrence(itemID: r.itemID, minutes: r.minutes).timeText
            return PlannedReminder(
                id: "late-" + r.id.dropFirst("dose-".count),
                title: "Still pending: \(name)",
                body: "Scheduled for \(time). Log or skip when you are ready.",
                itemID: r.itemID, minutes: r.minutes, fireDate: fire)
        }
    }

    // MARK: Action helpers (pure, testable)

    nonisolated static func status(forAction id: String) -> DoseStatus? {
        switch id {
        case "LOG_DOSE": .taken
        case "SKIP_DOSE": .skipped
        default: nil
        }
    }

    nonisolated static func occurrence(from userInfo: [AnyHashable: Any])
        -> (itemID: UUID, minutes: Int, day: Date)? {
        guard let idStr = userInfo["itemID"] as? String, let id = UUID(uuidString: idStr),
              let m = userInfo["minutes"] as? Int else { return nil }
        // The zone-independent dayKey is authoritative: an epoch stored as another
        // timezone's midnight resolves to the WRONG local day after travel, so a
        // lock-screen Log/Skip would write the dose to a neighboring date.
        if let key = userInfo["dayKey"] as? Int, let day = date(fromDayKey: key) {
            return (id, m, day)
        }
        guard let ti = userInfo["day"] as? Double else { return nil }
        return (id, m, Date(timeIntervalSince1970: ti)) // legacy payloads
    }

    // MARK: Schedule (effectful)

    /// Bumped per rebuild so a superseded in-flight rebuild aborts instead of
    /// interleaving its remove/add with a newer one.
    private static var rebuildGeneration = 0

    static func rebuild(context: ModelContext) {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let center = UNUserNotificationCenter.current()
        guard settings.notificationsEnabled else {
            center.removeAllPendingNotificationRequests()
            return
        }

        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let prefs = Prefs.from(settings)
        let allReminders = plan(for: items, logs: logs)
        // Advisory notices shift out of quiet hours; dose reminders never do.
        let allNotices = applyQuietHours(notices: decisionNotices(for: items), prefs: prefs)
        let allVialNotices = applyQuietHours(notices: vialNotices(for: items, logs: logs), prefs: prefs)
        // A dense reminder stack must not starve change or vial notices: reserve slots
        // for each before reminders take the rest.
        let reservedNotices = min(allNotices.count, 8)
        let reservedVial = min(allVialNotices.count, 4)
        let reminders = Array(allReminders.prefix(maxPending - reservedNotices - reservedVial))
        let notices = Array(allNotices.prefix(maxPending - reminders.count - reservedVial))
        let vialN = Array(allVialNotices.prefix(maxPending - reminders.count - notices.count))
        // Pre-dose leads + overdue re-pings are conveniences: they fill LEFTOVER
        // budget only and never displace a real dose reminder or notice.
        let leftover = maxPending - reminders.count - notices.count - vialN.count
        let extras = Array((preReminders(from: reminders, prefs: prefs)
                            + latePings(from: reminders, prefs: prefs))
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(max(0, leftover)))

        // Replace only OUR pending requests — an in-flight one-shot "Snooze 15m"
        // copy (`snooze-*`) must survive a rebuild (any dose log or stack edit
        // used to silently cancel it via removeAllPendingNotificationRequests).
        rebuildGeneration += 1
        let gen = rebuildGeneration
        let calendar = Calendar.current
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            guard gen == rebuildGeneration else { return }   // superseded by a newer rebuild
            let managed = pending.map(\.identifier).filter { id in
                Self.managedPrefixes.contains { id.hasPrefix($0) }
            }
            center.removePendingNotificationRequests(withIdentifiers: managed)

            for r in reminders + extras {
                let content = UNMutableNotificationContent()
                content.title = r.title
                content.body = r.body
                content.sound = .default
                // Only the true dose-time reminder is time-sensitive; pre-alerts and
                // the overdue follow-up are ordinary interruptions.
                content.interruptionLevel = r.id.hasPrefix("dose-") ? .timeSensitive : .active
                content.categoryIdentifier = categoryID
                content.userInfo = [
                    "itemID": r.itemID.uuidString,
                    "minutes": r.minutes,
                    "day": calendar.startOfDay(for: r.fireDate).timeIntervalSince1970, // legacy fallback
                    "dayKey": dayKey(calendar.startOfDay(for: r.fireDate), calendar),  // zone-independent
                ]
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
            }

            for n in notices + vialN {
                let content = UNMutableNotificationContent()
                content.title = n.title
                content.body = n.body
                content.interruptionLevel = .passive
                content.categoryIdentifier = decisionCategoryID
                content.userInfo = ["itemID": n.itemID.uuidString]
                let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: n.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
            }
            #if DEBUG
            NSLog("vita-notif: scheduled %d reminders + %d notices + %d vial + %d pre/late",
                  reminders.count, notices.count, vialN.count, extras.count)
            #endif
        }
    }

    #if DEBUG
    /// UI-test hook (M53): fire a real DOSE_REMINDER n seconds from now for the
    /// first stack item, so the Springboard tap test does not wait out a calendar
    /// minute boundary. Requests permission itself because the demo seeds skip
    /// onboarding (where the real prompt lives). Env: VITA_NOTIF_TEST_SECONDS=<n>.
    /// The identifier carries no managed prefix, so rebuild sweeps ignore it.
    static func scheduleDebugTapReminder(context: ModelContext) {
        guard let raw = ProcessInfo.processInfo.environment["VITA_NOTIF_TEST_SECONDS"],
              let seconds = Double(raw), seconds > 0,
              let item = (try? context.fetch(FetchDescriptor<ProtocolItem>()))?.first else { return }
        let itemID = item.id
        let title = item.displayName
        Task { @MainActor in
            _ = await NotificationService.requestPermission()
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let content = UNMutableNotificationContent()
            content.title = "\(title) time"
            content.body = "Tap-test reminder (debug)."
            content.sound = .default
            content.categoryIdentifier = categoryID
            content.userInfo = [
                "itemID": itemID.uuidString,
                "minutes": 8 * 60,
                "day": today.timeIntervalSince1970,
                "dayKey": dayKey(today, calendar),
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
            try? await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: "debug-tap-test", content: content, trigger: trigger))
        }
    }
    #endif
}
