import Foundation
import SwiftData

/// The single write path for dose logging (M4). Upserts a `DoseLog` per scheduled
/// occurrence (so re-acting flips status, never duplicates), deletes on undo, and
/// appends PRN logs freely. Built to be callable from a background `ModelContext`
/// too, so M5's notification Log/Skip actions reuse it verbatim.
@MainActor
struct DoseLogger {
    let context: ModelContext

    /// Pure occurrence ↔ log match (testable without a container; non-isolated so
    /// the pure derivation/streak helpers can call it off the main actor).
    nonisolated static func matches(_ log: DoseLog, itemID: UUID, dayStart: Date, minutes: Int,
                                    calendar: Calendar = .current) -> Bool {
        !log.isPRN && log.itemID == itemID && log.scheduledMinutes == minutes
            && calendar.isDate(log.scheduledDayStart, inSameDayAs: dayStart)
    }

    private func allLogs() -> [DoseLog] {
        (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
    }

    func logged(itemID: UUID, minutes: Int, on day: Date = Date()) -> DoseLog? {
        let start = Calendar.current.startOfDay(for: day)
        return allLogs().first { Self.matches($0, itemID: itemID, dayStart: start, minutes: minutes) }
    }

    /// Take or skip a scheduled occurrence. Upserts on (itemID, day, minutes).
    @discardableResult
    func log(item: ProtocolItem, occurrence: DoseOccurrence, on day: Date = Date(),
             status: DoseStatus) -> DoseLog {
        let start = Calendar.current.startOfDay(for: day)
        let log = logged(itemID: item.id, minutes: occurrence.minutes, on: day) ?? {
            let l = DoseLog(); context.insert(l); return l
        }()
        stamp(log, from: item)
        log.scheduledDayStart = start
        log.scheduledMinutes = occurrence.minutes
        log.statusRaw = status.rawValue
        log.isPRN = false
        log.loggedAt = Date()
        try? context.save()
        NotificationManager.rebuild(context: context)   // drop this occurrence's reminder
        return log
    }

    /// Revert a scheduled occurrence to un-acted.
    func undo(item: ProtocolItem, occurrence: DoseOccurrence, on day: Date = Date()) {
        if let log = logged(itemID: item.id, minutes: occurrence.minutes, on: day) {
            context.delete(log)
            try? context.save()
            NotificationManager.rebuild(context: context)   // reminder comes back
        }
    }

    /// Log a PRN ("as needed") dose at `when`. Appends (multiple per day allowed).
    @discardableResult
    func logPRN(item: ProtocolItem, at when: Date = Date()) -> DoseLog {
        let log = DoseLog()
        stamp(log, from: item)
        log.scheduledDayStart = Calendar.current.startOfDay(for: when)
        log.scheduledMinutes = -1
        log.isPRN = true
        log.statusRaw = DoseStatus.taken.rawValue
        log.loggedAt = when
        context.insert(log)
        try? context.save()
        return log
    }

    /// Most recent PRN log for an item on a given day (drives "logged Nh ago").
    func lastPRN(itemID: UUID, on day: Date = Date()) -> DoseLog? {
        let start = Calendar.current.startOfDay(for: day)
        return allLogs()
            .filter { $0.isPRN && $0.itemID == itemID
                && Calendar.current.isDate($0.scheduledDayStart, inSameDayAs: start) }
            .max { $0.loggedAt < $1.loggedAt }
    }

    private func stamp(_ log: DoseLog, from item: ProtocolItem) {
        log.itemID = item.id
        log.compoundSlug = item.compoundSlug
        log.displayName = item.displayName
        log.doseText = item.doseText
        log.categoryRaw = item.categoryRaw
    }
}
