import Foundation

/// Pure check-in streak (M8a). A day is "done" when its `DiaryEntry` is logged.
/// Walks back from today: today counts only if already logged (an un-checked-in
/// today doesn't break a prior run — skip to yesterday); stops at the first
/// un-logged past day. Capped at 366. Structural sibling of `StreakService`.
enum DiaryStreak {
    static let maxDays = 366

    static func current(entries: [DiaryEntry], asOf now: Date, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: now)
        let logged = Set(entries.filter { $0.isLogged }.map { calendar.startOfDay(for: $0.dayStart) })
        var day = today
        var streak = 0
        var first = true

        for _ in 0..<maxDays {
            let done = logged.contains(day)
            if first {
                first = false
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
