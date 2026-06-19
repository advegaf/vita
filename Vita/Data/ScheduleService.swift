import Foundation

/// The three time-of-day blocks. One source of truth, reused by the setup sheet,
/// the schedule math, and Today.
enum DayBlock: Int, CaseIterable, Sendable {
    case morning, midday, night

    var title: String {
        switch self { case .morning: "Morning"; case .midday: "Midday"; case .night: "Night" }
    }
    var greeting: String {
        switch self { case .morning: "Good morning."; case .midday: "Good afternoon."; case .night: "Good evening." }
    }
    var symbol: String {
        switch self { case .morning: "sunrise.fill"; case .midday: "sun.max.fill"; case .night: "moon.fill" }
    }
    /// Default clock time when this block is chosen (minutes-from-midnight).
    var defaultMinutes: Int {
        switch self { case .morning: 8 * 60; case .midday: 13 * 60; case .night: 21 * 60 }
    }
    var emptyLine: String {
        switch self {
        case .morning: "Nothing to pin this morning."
        case .midday:  "Nothing to pin this midday."
        case .night:   "Nothing to pin tonight."
        }
    }
    var doneLine: String {
        switch self {
        case .morning: "All done this morning."
        case .midday:  "All done this midday."
        case .night:   "All done tonight."
        }
    }

    /// Morning < 12:00 ≤ Midday < 17:00 ≤ Night.
    static func from(minutes: Int) -> DayBlock {
        if minutes < 12 * 60 { return .morning }
        if minutes < 17 * 60 { return .midday }
        return .night
    }
}

/// One scheduled dose on a given day.
struct DoseOccurrence: Identifiable, Hashable {
    let itemID: UUID
    let minutes: Int          // minutes-from-midnight
    var id: String { "\(itemID.uuidString)-\(minutes)" }
    var block: DayBlock { DayBlock.from(minutes: minutes) }
    var timeText: String {
        let h24 = minutes / 60, m = minutes % 60
        let h12 = h24 % 12 == 0 ? 12 : h24 % 12
        let ampm = h24 < 12 ? "AM" : "PM"
        return String(format: "%d:%02d %@", h12, m, ampm)
    }
}

/// Computes the day's occurrences live from a ProtocolItem's ScheduleRule.
/// No DoseEvent materialization (that's M4) — Today derives on the fly.
enum ScheduleService {

    static func occurrences(for item: ProtocolItem, on date: Date,
                            calendar: Calendar = .current) -> [DoseOccurrence] {
        guard let rule = item.schedule, rule.frequency != .prn else { return [] }
        guard isDueDay(rule, on: date, calendar: calendar) else { return [] }
        return rule.timeSlotsMinutes.sorted().map {
            DoseOccurrence(itemID: item.id, minutes: $0)
        }
    }

    static func isDueDay(_ rule: ScheduleRule, on date: Date,
                         calendar: Calendar = .current) -> Bool {
        if isResting(rule, on: date, calendar: calendar) { return false }   // cycle OFF-block → nothing due
        switch rule.frequency {
        case .prn:
            return false
        case .daily:
            return true
        case .weekly:
            let wd = calendar.component(.weekday, from: date) // 1=Sun…7=Sat
            return rule.weekdays.contains(wd)
        case .eod:
            let a = calendar.startOfDay(for: rule.anchorDate)
            let d = calendar.startOfDay(for: date)
            let days = calendar.dateComponents([.day], from: a, to: d).day ?? 0
            return abs(days) % 2 == 0
        }
    }

    /// Derives an occurrence's UI state from the day's logs + `now`: taken/skipped
    /// from a matching log, else overdue (today, past its slot) or due. Pure.
    static func state(itemID: UUID, minutes: Int, day: Date, logs: [DoseLog],
                      now: Date, calendar: Calendar = .current) -> DoseState {
        let start = calendar.startOfDay(for: day)
        if let log = logs.first(where: {
            DoseLogger.matches($0, itemID: itemID, dayStart: start, minutes: minutes, calendar: calendar)
        }) {
            return log.status == .skipped ? .skipped : .taken
        }
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if calendar.isDate(start, inSameDayAs: now), minutes < nowMinutes { return .overdue }
        return .due
    }

    /// "45m late" / "2h 15m late" / "2d late" — lets an overdue pin say HOW late,
    /// so the user can triage at a glance. Pure.
    static func overdueLabel(minutesLate: Int) -> String {
        let m = max(0, minutesLate)
        if m < 60 { return "\(m)m late" }
        if m < 48 * 60 {
            let h = m / 60, rem = m % 60
            return rem == 0 ? "\(h)h late" : "\(h)h \(rem)m late"
        }
        return "\(m / (24 * 60))d late"
    }

    /// Human cadence label for stack rows ("Daily at 8:00 AM, 9:00 PM", "Weekly on Sun, Thu").
    static func cadenceLabel(for rule: ScheduleRule) -> String {
        if rule.frequency == .prn { return "As needed" }
        let times = rule.timeSlotsMinutes.sorted()
            .map { DoseOccurrence(itemID: rule.id, minutes: $0).timeText }
            .joined(separator: ", ")
        switch rule.frequency {
        case .daily: return times.isEmpty ? "Daily" : "Daily at \(times)"
        case .eod:   return times.isEmpty ? "Every other day" : "Every other day at \(times)"
        case .weekly:
            let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
            let days = rule.weekdays.sorted().compactMap { (1...7).contains($0) ? names[$0] : nil }
                .joined(separator: ", ")
            let base = days.isEmpty ? "Weekly" : "Weekly on \(days)"
            return times.isEmpty ? base : "\(base) at \(times)"
        case .prn: return "As needed"
        }
    }

    // MARK: - M9 cycles + titration (pure, calendar-injectable)

    enum CyclePhase: Equatable { case on, resting }

    struct CycleStatus: Equatable {
        var phase: CyclePhase
        var unitIsWeeks: Bool
        var indexInUnit: Int      // 1-based week/day within the ON phase
        var totalUnits: Int       // ON-phase length in the chosen unit
        var fraction: Double      // 0…1 through the full on+off envelope
        var daysLeftInPhase: Int
        var resumesOn: Date?      // first ON day after the current OFF block
        var chipText: String      // "wk 3/8" (on) / "rest" (resting)
    }

    struct TitrationStep: Equatable, Identifiable {
        var id: Int
        var weekStart: Int
        var dose: Double
        var unit: DoseUnit
        var isCurrent: Bool
        var isPast: Bool
    }

    /// True when a cycle is configured AND `date` is in the OFF phase.
    static func isResting(_ rule: ScheduleRule, on date: Date, calendar: Calendar = .current) -> Bool {
        guard rule.hasCycle else { return false }
        let period = rule.cycleOnDays + rule.cycleOffDays
        let days = elapsedDays(rule.protocolStart, date, calendar)
        let phase = ((days % period) + period) % period
        return phase >= rule.cycleOnDays
    }

    /// Cycle phase/progress for the ribbon + chip + resting line. nil = continuous.
    static func cycleStatus(for rule: ScheduleRule, on date: Date,
                            calendar: Calendar = .current) -> CycleStatus? {
        guard rule.hasCycle else { return nil }
        let period = rule.cycleOnDays + rule.cycleOffDays
        let days = elapsedDays(rule.protocolStart, date, calendar)
        let phaseDay = ((days % period) + period) % period
        let resting = phaseDay >= rule.cycleOnDays
        let unit = rule.cycleUnit
        let onUnits = max(1, rule.cycleOnDays / unit.perStep)
        let indexInUnit = (resting ? 0 : phaseDay) / unit.perStep + 1
        let daysLeft = resting ? (rule.cycleOffDays - (phaseDay - rule.cycleOnDays))
                               : (rule.cycleOnDays - phaseDay)
        let resumesOn = resting
            ? calendar.date(byAdding: .day, value: daysLeft, to: calendar.startOfDay(for: date))
            : nil
        let chip = resting ? "rest" : "\(unit.short) \(indexInUnit)/\(onUnits)"
        return CycleStatus(phase: resting ? .resting : .on, unitIsWeeks: unit == .weeks,
                           indexInUnit: indexInUnit, totalUnits: onUnits,
                           fraction: Double(phaseDay) / Double(period),
                           daysLeftInPhase: max(0, daysLeft), resumesOn: resumesOn, chipText: chip)
    }

    /// The active dose on `date`: latest titration step whose start <= date, else base.
    static func activeDose(for item: ProtocolItem, on date: Date,
                           calendar: Calendar = .current) -> Double {
        guard let rule = item.schedule, rule.hasTitration else { return item.doseAmount }
        let elapsed = elapsedDays(rule.protocolStart, date, calendar)
        return rule.titrationSteps.last { $0.dayStart <= elapsed }?.dose ?? item.doseAmount
    }
    static func activeDoseText(for item: ProtocolItem, on date: Date,
                               calendar: Calendar = .current) -> String {
        "\(vtFormatNumber(activeDose(for: item, on: date, calendar: calendar))) \(item.doseUnit.label)"
    }

    /// Next upcoming step strictly after `date`: dose + whole weeks away. nil if none.
    static func nextTitration(for item: ProtocolItem, on date: Date,
                              calendar: Calendar = .current) -> (dose: Double, weeksAway: Int)? {
        guard let rule = item.schedule, rule.hasTitration else { return nil }
        let elapsed = elapsedDays(rule.protocolStart, date, calendar)
        guard let next = rule.titrationSteps.first(where: { $0.dayStart > elapsed }) else { return nil }
        return (next.dose, max(1, (next.dayStart - elapsed + 6) / 7))
    }

    /// Full ladder with current/past flags for the detail display.
    static func titrationLadder(for item: ProtocolItem, on date: Date,
                                calendar: Calendar = .current) -> [TitrationStep] {
        guard let rule = item.schedule, rule.hasTitration else { return [] }
        let elapsed = elapsedDays(rule.protocolStart, date, calendar)
        let steps = rule.titrationSteps
        let currentStart = steps.last { $0.dayStart <= elapsed }?.dayStart
        return steps.enumerated().map { i, s in
            TitrationStep(id: i, weekStart: s.dayStart / 7 + 1, dose: s.dose, unit: item.doseUnit,
                          isCurrent: s.dayStart == currentStart,
                          isPast: currentStart != nil && s.dayStart < currentStart!)
        }
    }

    static func isRestingToday(_ item: ProtocolItem, on date: Date, calendar: Calendar = .current) -> Bool {
        guard let rule = item.schedule else { return false }
        return isResting(rule, on: date, calendar: calendar)
    }

    /// "resting, back Tue" tail for the Today rest row.
    static func restingLine(for item: ProtocolItem, on date: Date, calendar: Calendar = .current) -> String {
        guard let rule = item.schedule, let s = cycleStatus(for: rule, on: date, calendar: calendar),
              let resume = s.resumesOn else { return "resting" }
        return "resting, back \(resume.formatted(.dateTime.weekday(.abbreviated)))"
    }

    /// True iff `date` is exactly a titration step's start day (for the day-before notice).
    static func isStepStart(_ rule: ScheduleRule, on date: Date, calendar: Calendar = .current) -> Bool {
        guard rule.hasTitration else { return false }
        let elapsed = elapsedDays(rule.protocolStart, date, calendar)
        return rule.titrationSteps.contains { $0.dayStart == elapsed }
    }

    /// True iff `date` is ON but `date-1` was resting (first ON day after an OFF block).
    static func isResumeDay(_ rule: ScheduleRule, on date: Date, calendar: Calendar = .current) -> Bool {
        guard rule.hasCycle else { return false }
        let prev = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) ?? date
        return !isResting(rule, on: date, calendar: calendar) && isResting(rule, on: prev, calendar: calendar)
    }

    private static func elapsedDays(_ from: Date, _ to: Date, _ calendar: Calendar) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: from),
                                to: calendar.startOfDay(for: to)).day ?? 0
    }
}
