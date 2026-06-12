import Foundation

/// Pure streak calculation (M4). A day is "done" when every scheduled occurrence
/// that day has a taken/skipped log; a rest day (0 scheduled) holds the streak.
/// Walks back from today: today counts only if already done (an incomplete but
/// not-yet-midnight today doesn't break the run); stops at the first un-done past
/// day. Capped to avoid an unbounded walk on PRN-only stacks.
enum StreakService {
    static let maxDays = 366

    /// O(1)-lookup key for an acted occurrence. The log table grows forever, so the
    /// day-walk below must NOT scan it per occurrence (366 days × occurrences × logs
    /// was a few million closure calls per render after a year of use).
    static func actedKey(itemID: UUID, day: Date, minutes: Int, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return "\(itemID.uuidString)#\((c.year ?? 0) * 10000 + (c.month ?? 0) * 100 + (c.day ?? 0))#\(minutes)"
    }

    static func currentStreak(items: [ProtocolItem], logs: [DoseLog], asOf now: Date,
                              calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var day = today
        var streak = 0
        var first = true

        // Index the scheduled (non-PRN) logs once; the walk then checks a Set.
        let acted = Set(logs.filter { !$0.isPRN }.map {
            actedKey(itemID: $0.itemID, day: $0.scheduledDayStart, minutes: $0.scheduledMinutes, calendar: calendar)
        })

        for _ in 0..<maxDays {
            let occs = items.flatMap { ScheduleService.occurrences(for: $0, on: day, calendar: calendar) }
            let done = occs.isEmpty || occs.allSatisfy { occ in
                acted.contains(actedKey(itemID: occ.itemID, day: day, minutes: occ.minutes, calendar: calendar))
            }
            if first {
                first = false
                // An incomplete *today* doesn't break a prior streak — skip to yesterday.
                if calendar.isDate(day, inSameDayAs: today), !done {
                    day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
                    continue
                }
            }
            guard done else { break }
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }
}
