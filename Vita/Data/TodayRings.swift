import Foundation

/// The Today hero's ring data: doses acted today, streak, and 7-day adherence,
/// plus the calm status lines. Pure — derives everything live from items + logs
/// (same sources as the DotMeter and the detail adherence card), never
/// materializing events.
struct TodayRingsSnapshot: Equatable {
    var dosesActed = 0
    var dosesTotal = 0
    var overdueCount = 0
    var streakDays = 0
    var weekLogged = 0
    var weekScheduled = 0

    /// Ring fractions (0…1). A day/week with nothing scheduled reads complete —
    /// a rest day is a kept promise, not an empty one.
    var doseProgress: Double { dosesTotal == 0 ? 1 : Double(dosesActed) / Double(dosesTotal) }
    var weekProgress: Double { weekScheduled == 0 ? 1 : Double(weekLogged) / Double(weekScheduled) }
    /// Streak ring fills over a week; beyond that it stays full and the number talks.
    var streakProgress: Double { min(1, Double(streakDays) / 7) }

    var weekPercentText: String { "\(Int((weekProgress * 100).rounded()))%" }

    /// "Two doses left." — the photo-header subtitle (same voice as the old
    /// Today headline count).
    var remainingLine: String {
        let remaining = dosesTotal - dosesActed
        if dosesTotal == 0 { return "Nothing scheduled." }
        if remaining == 0 { return "All done for today." }
        let words = ["zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        let n = remaining < words.count ? words[remaining] : "\(remaining)"
        return remaining == 1 ? "\(n) dose left." : "\(n) doses left."
    }

    /// "On track." / "All done." / "Two to catch up." / "Rest day."
    var headline: String {
        if dosesTotal == 0 { return "Rest day." }
        if overdueCount > 0 {
            let words = ["", "One", "Two", "Three", "Four", "Five"]
            let n = overdueCount < words.count ? words[overdueCount] : "\(overdueCount)"
            return overdueCount == 1 ? "\(n) to catch up." : "\(n) to catch up."
        }
        if dosesActed == dosesTotal { return "All done." }
        return "On track."
    }

    var subline: String {
        if dosesTotal == 0 { return "Nothing scheduled today." }
        if overdueCount > 0 { return "A dose slipped past its time." }
        if dosesActed == dosesTotal { return "Every dose is in." }
        return "Nothing urgent right now."
    }
}

enum TodayRings {

    static func snapshot(items: [ProtocolItem], logs: [DoseLog], asOf now: Date,
                         calendar: Calendar = .current) -> TodayRingsSnapshot {
        var s = TodayRingsSnapshot()

        for item in items {
            for o in ScheduleService.occurrences(for: item, on: now, calendar: calendar) {
                s.dosesTotal += 1
                switch ScheduleService.state(itemID: o.itemID, minutes: o.minutes,
                                             day: now, logs: logs, now: now, calendar: calendar) {
                case .taken, .skipped: s.dosesActed += 1
                case .overdue:         s.overdueCount += 1
                case .due:             break
                }
            }
        }

        s.streakDays = StreakService.currentStreak(items: items, logs: logs,
                                                   asOf: now, calendar: calendar)

        // 7-day adherence, aggregated across scheduled (non-PRN) items with the
        // same honest denominator as the detail card (rest days excluded, today
        // only counted once resolved).
        for item in items where (item.schedule?.frequency ?? .prn) != .prn {
            let (logged, scheduled) = Adherence.summary(item: item, logs: logs, days: 7,
                                                        asOf: now, calendar: calendar)
            s.weekLogged += logged
            s.weekScheduled += scheduled
        }

        return s
    }
}
