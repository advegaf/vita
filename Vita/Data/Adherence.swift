import Foundation

/// One calendar day's adherence resolution for an item (oldest-first in a window).
enum AdherenceDay: Equatable {
    case taken          // every scheduled occurrence that day acted, all taken
    case skipped        // every occurrence acted, at least one skipped
    case missed         // a past day with un-acted scheduled occurrences
    case notScheduled   // rest/cycle-off/non-due day, or today while still in progress
}

/// Pure adherence derivations over the last N days (M13). Mirrors StreakService:
/// day-done = every scheduled occurrence acted (taken OR skipped — consistent with
/// the streak's semantics); an in-progress today never counts against the user.
/// Callers should pass logs pre-filtered to the window (cheap fetch discipline —
/// the full log table grows forever).
enum Adherence {

    /// Oldest-first day states for the last `days` calendar days (including today).
    static func dayStates(item: ProtocolItem, logs: [DoseLog], days: Int = 30,
                          asOf now: Date = Date(), calendar: Calendar = .current) -> [AdherenceDay] {
        let today = calendar.startOfDay(for: now)
        var out: [AdherenceDay] = []
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            out.append(state(item: item, logs: logs, day: day, today: today, calendar: calendar))
        }
        return out
    }

    /// "Logged 24 of 26 scheduled days." — logged = acted days; scheduled excludes
    /// rest/non-due days AND an unresolved today, so the denominator is honest.
    static func summary(item: ProtocolItem, logs: [DoseLog], days: Int = 30,
                        asOf now: Date = Date(), calendar: Calendar = .current) -> (logged: Int, scheduled: Int) {
        let states = dayStates(item: item, logs: logs, days: days, asOf: now, calendar: calendar)
        let scheduled = states.filter { $0 != .notScheduled }.count
        let logged = states.filter { $0 == .taken || $0 == .skipped }.count
        return (logged, scheduled)
    }

    /// PRN items have no schedule: count the as-needed logs in the window, and mark
    /// the days they were used (for the grid).
    static func prnDays(item: ProtocolItem, logs: [DoseLog], days: Int = 30,
                        asOf now: Date = Date(), calendar: Calendar = .current) -> [AdherenceDay] {
        let today = calendar.startOfDay(for: now)
        return stride(from: days - 1, through: 0, by: -1).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return .notScheduled }
            let used = logs.contains {
                $0.isPRN && $0.itemID == item.id && calendar.isDate($0.loggedAt, inSameDayAs: day)
            }
            return used ? .taken : .notScheduled
        }
    }

    static func prnCount(item: ProtocolItem, logs: [DoseLog], days: Int = 30,
                         asOf now: Date = Date(), calendar: Calendar = .current) -> Int {
        guard let cutoff = calendar.date(byAdding: .day, value: -(days - 1),
                                         to: calendar.startOfDay(for: now)) else { return 0 }
        return logs.filter { $0.isPRN && $0.itemID == item.id && $0.loggedAt >= cutoff }.count
    }

    // MARK: - Internals

    private static func state(item: ProtocolItem, logs: [DoseLog], day: Date,
                              today: Date, calendar: Calendar) -> AdherenceDay {
        // Days before the item existed are not "missed" — schedules compute for any
        // past date, but a compound added yesterday must not show 28 phantom misses.
        guard calendar.startOfDay(for: day) >= calendar.startOfDay(for: item.addedAt) else {
            return .notScheduled
        }
        let occs = ScheduleService.occurrences(for: item, on: day, calendar: calendar)
        guard !occs.isEmpty else { return .notScheduled }
        let dayStart = calendar.startOfDay(for: day)
        let acted = occs.map { occ in
            logs.first {
                DoseLogger.matches($0, itemID: occ.itemID, dayStart: dayStart,
                                   minutes: occ.minutes, calendar: calendar)
            }
        }
        if acted.allSatisfy({ $0 != nil }) {
            return acted.contains { $0?.status == .skipped } ? .skipped : .taken
        }
        // Partially/fully un-acted: a PAST day is missed; today is still in progress.
        return dayStart < today ? .missed : .notScheduled
    }
}
