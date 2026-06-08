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
        // Pull out Sendable primitives before hopping to the main actor.
        let itemID = userInfo["itemID"] as? String
        let minutes = userInfo["minutes"] as? Int
        let dayTI = userInfo["day"] as? Double

        switch action {
        case "LOG_DOSE", "SKIP_DOSE":
            await MainActor.run { handleLog(action: action, itemID: itemID, minutes: minutes, dayTI: dayTI) }
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

    private func handleLog(action: String, itemID: String?, minutes: Int?, dayTI: Double?) {
        guard let status = NotificationManager.status(forAction: action),
              let idStr = itemID, let id = UUID(uuidString: idStr),
              let m = minutes, let ti = dayTI, let container else { return }
        let context = container.mainContext
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        guard let item = items.first(where: { $0.id == id }) else { return }
        DoseLogger(context: context).log(
            item: item, occurrence: DoseOccurrence(itemID: id, minutes: m),
            on: Date(timeIntervalSince1970: ti), status: status)
    }
}

/// Schedules local dose reminders from the stack. Every reminder is materialized
/// as a concrete, non-repeating fire date over a rolling window, and an occurrence
/// that already has a DoseLog (taken/skipped) is skipped — so logging a dose (in
/// app or from a notification) makes its reminder disappear, and undo brings it back.
@MainActor
enum NotificationManager {

    static let windowDays = 14
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
                    if logs.contains(where: {
                        DoseLogger.matches($0, itemID: item.id, dayStart: dayStart, minutes: m, calendar: calendar)
                    }) { continue }
                    out.append(PlannedReminder(
                        id: "dose-\(item.id.uuidString)-\(dayKey(dayStart, calendar))-\(m)",
                        title: "Time to pin \(item.displayName)", body: reminderBody(item, on: dayStart),
                        itemID: item.id, minutes: m, fireDate: fire))
                }
            }
        }
        return Array(out.sorted { $0.fireDate < $1.fireDate }.prefix(maxPending))
    }

    private static func dayKey(_ day: Date, _ calendar: Calendar) -> Int {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return (c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0)
    }

    private static func reminderBody(_ item: ProtocolItem, on day: Date) -> String {
        let dose = item.effectiveDoseText(on: day)
        if let units = item.effectiveDrawUnitsText(on: day) { return "\(dose) · \(units)" }
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
              let m = userInfo["minutes"] as? Int, let ti = userInfo["day"] as? Double
        else { return nil }
        return (id, m, Date(timeIntervalSince1970: ti))
    }

    // MARK: Schedule (effectful)

    static func rebuild(context: ModelContext) {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        guard settings.notificationsEnabled else { return }

        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let reminders = plan(for: items, logs: logs)
        let calendar = Calendar.current
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
                "day": calendar.startOfDay(for: r.fireDate).timeIntervalSince1970,
            ]
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: r.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: trigger))
        }

        // Review-only change notices fill the remaining cap (reminders take priority).
        let notices = Array(decisionNotices(for: items).prefix(max(0, maxPending - reminders.count)))
        for n in notices {
            let content = UNMutableNotificationContent()
            content.title = n.title
            content.body = n.body
            content.interruptionLevel = .passive
            content.categoryIdentifier = decisionCategoryID
            content.userInfo = ["itemID": n.itemID.uuidString]
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: n.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: n.id, content: content, trigger: trigger))
        }
        #if DEBUG
        NSLog("vita-notif: scheduled %d reminders + %d notices", reminders.count, notices.count)
        #endif
    }
}
