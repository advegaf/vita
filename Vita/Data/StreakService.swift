import Foundation

/// Pure streak calculation (M4). A day is "done" when every scheduled occurrence
/// that day has a taken/skipped log; a rest day (0 scheduled) holds the streak.
/// Walks back from today: today counts only if already done (an incomplete but
/// not-yet-midnight today doesn't break the run); stops at the first un-done past
/// day. Capped to avoid an unbounded walk on PRN-only stacks.
enum StreakService {
    static let maxDays = 366

    static func currentStreak(items: [ProtocolItem], logs: [DoseLog], asOf now: Date,
                              calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        var day = today
        var streak = 0
        var first = true

        for _ in 0..<maxDays {
            let occs = items.flatMap { ScheduleService.occurrences(for: $0, on: day, calendar: calendar) }
            let done = occs.isEmpty || occs.allSatisfy { occ in
                logs.contains {
                    DoseLogger.matches($0, itemID: occ.itemID, dayStart: day, minutes: occ.minutes, calendar: calendar)
                }
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
