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

    // Show banners even while the app is foregrounded.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        // Resolve the Sendable occurrence (dayKey-aware) before hopping actors.
        let occ = NotificationManager.occurrence(from: userInfo)
        let itemID = userInfo["itemID"] as? String

        switch action {
        case "LOG_DOSE", "SKIP_DOSE":
            await MainActor.run { handleLog(action: action, occ: occ) }
        case "SNOOZE_15":
            // UNUserNotificationCenter is thread-safe; reuse the fired content, +15m.
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false)
            let req = UNNotificationRequest(identifier: "snooze-\(UUID().uuidString)",
                                            content: response.notification.request.content, trigger: trigger)
            try? await UNUserNotificationCenter.current().add(req)
        case UNNotificationDefaultActionIdentifier:
            await MainActor.run {
                if let id = itemID.flatMap(UUID.init(uuidString:)) { pendingDetailItemID = id }
                else { pendingTab = .today }
            }
        default:
            break
        }
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
        let dose = item.effectiveDoseText(on: day)
        if let units = item.effectiveDrawUnitsText(on: day) { return "\(dose) (\(units))" }
        return dose
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
        let allReminders = plan(for: items, logs: logs)
        let allNotices = decisionNotices(for: items)
        let allVialNotices = vialNotices(for: items, logs: logs)
        // A dense reminder stack must not starve change or vial notices: reserve slots
        // for each before reminders take the rest.
        let reservedNotices = min(allNotices.count, 8)
        let reservedVial = min(allVialNotices.count, 4)
        let reminders = Array(allReminders.prefix(maxPending - reservedNotices - reservedVial))
        let notices = Array(allNotices.prefix(maxPending - reminders.count - reservedVial))
        let vialN = Array(allVialNotices.prefix(maxPending - reminders.count - notices.count))

        // Replace only OUR pending requests — an in-flight one-shot "Snooze 15m"
        // copy (`snooze-*`) must survive a rebuild (any dose log or stack edit
        // used to silently cancel it via removeAllPendingNotificationRequests).
        rebuildGeneration += 1
        let gen = rebuildGeneration
        let calendar = Calendar.current
        Task { @MainActor in
            let pending = await center.pendingNotificationRequests()
            guard gen == rebuildGeneration else { return }   // superseded by a newer rebuild
            let managed = pending.map(\.identifier).filter {
                $0.hasPrefix("dose-") || $0.hasPrefix("titr-") || $0.hasPrefix("resume-")
                    || $0.hasPrefix("vial-")
            }
            center.removePendingNotificationRequests(withIdentifiers: managed)

            for r in reminders {
                let content = UNMutableNotificationContent()
                content.title = r.title
                content.body = r.body
                content.sound = .default
                content.interruptionLevel = .timeSensitive
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
            NSLog("vita-notif: scheduled %d reminders + %d notices + %d vial",
                  reminders.count, notices.count, vialN.count)
            #endif
        }
    }
}
