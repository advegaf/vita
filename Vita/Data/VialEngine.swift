import Foundation

/// Pure vial-lifecycle math (M37). Remaining supply is DERIVED, never stored: it is
/// the vial's mg minus the sum of every taken dose logged since the vial was
/// reconstituted (matching the app's derive-live convention). Undo therefore
/// self-heals, skipped doses never decrement, and "start a new vial" resets the
/// clock with zero bookkeeping. Calendar-injectable; no SwiftData writes.
enum VialEngine {
    static let defaultBUDDays = 28
    static let lowDosesThreshold = 3          // "running low" at this many doses or fewer
    static let projectionHorizonDays = 365    // run-out walk cap; beyond this we don't project

    /// A dose in mg for any unit. IU has no universal ratio, so it routes through the
    /// per-compound `iuPerMg` when known, else the HGH-class approximation (≈ 3 IU/mg).
    /// Returns nil for a non-positive amount.
    static func doseMg(_ amount: Double, unit: DoseUnit, iuPerMg: Double? = nil) -> Double? {
        guard amount > 0 else { return nil }
        switch unit {
        case .mcg: return amount / 1000
        case .mg:  return amount
        case .iu:  return amount / (iuPerMg ?? ReconstitutionCalculator.iuPerMg)
        }
    }

    /// mg consumed from the active vial: taken (never skipped) logs for `slug` whose
    /// `loggedAt >= since`, summing each log's own stamped dose+unit. Legacy logs
    /// (empty unit / zero amount, created before M37) contribute 0 by construction.
    static func consumedMg(logs: [DoseLog], slug: String, since: Date,
                           iuPerMg: Double? = nil) -> Double {
        var total: Double = 0
        for log in logs {
            guard log.status == .taken, log.compoundSlug == slug, log.loggedAt >= since,
                  let unit = log.doseUnit,
                  let mg = doseMg(log.doseAmount, unit: unit, iuPerMg: iuPerMg) else { continue }
            total += mg
        }
        return total
    }

    /// True when a taken log after reconstitution carries no numeric stamp — i.e. the
    /// vial predates M37, so derived remaining would read falsely full. Drives the
    /// one-time adoption nudge (the vial's `legacyNudgeDismissedAt` stores dismissal).
    static func isLegacyVial(logs: [DoseLog], slug: String, since: Date) -> Bool {
        logs.contains { $0.status == .taken && $0.compoundSlug == slug
            && $0.loggedAt >= since && $0.doseUnit == nil }
    }

    struct Status: Equatable {
        var totalMg: Double
        var remainingMg: Double          // clamped to >= 0
        var fractionRemaining: Double    // 0...1, drives the supply bar
        var dosesRemaining: Int?         // at the current effective dose; nil if unconvertible
        var runOutDate: Date?            // schedule-walked; nil for PRN / no schedule
        var budDays: Int
        var budDate: Date
        var daysSinceRecon: Int
        var isPastBUD: Bool
        var isLow: Bool
        var isOverdrawn: Bool            // consumed more than the vial holds (dose edited up, etc.)
        var hasFractionalLastDose: Bool  // 0 < remaining < one dose
        var isLegacy: Bool
    }

    /// The full derived picture for a vial as of `now`. `iuPerMg` comes from the
    /// item's catalog compound (nil for mcg/mg items).
    static func status(item: ProtocolItem, vial: Vial, logs: [DoseLog],
                       asOf now: Date, iuPerMg: Double? = nil,
                       calendar: Calendar = .current) -> Status {
        let total = vial.vialMg
        let consumed = consumedMg(logs: logs, slug: vial.compoundSlug,
                                  since: vial.reconstitutedAt, iuPerMg: iuPerMg)
        let remainingRaw = total - consumed
        let remaining = max(0, remainingRaw)
        let fraction = total > 0 ? min(1, max(0, remaining / total)) : 0
        let currentDoseMg = doseMg(item.effectiveDose(on: now, calendar: calendar),
                                   unit: item.doseUnit, iuPerMg: iuPerMg)
        let dosesRemaining = currentDoseMg.map { Int((remaining / $0).rounded(.down)) }
        var fractional = false
        if let d = currentDoseMg { fractional = remaining > 0 && remaining < d }
        let recon = calendar.startOfDay(for: vial.reconstitutedAt)
        let today = calendar.startOfDay(for: now)
        let daysSince = calendar.dateComponents([.day], from: recon, to: today).day ?? 0
        let budDate = calendar.date(byAdding: .day, value: vial.budDays, to: recon) ?? vial.reconstitutedAt
        let runOut = runOutDate(item: item, remainingMg: remaining, from: now, logs: logs,
                                iuPerMg: iuPerMg, calendar: calendar)

        return Status(
            totalMg: total,
            remainingMg: remaining,
            fractionRemaining: fraction,
            dosesRemaining: dosesRemaining,
            runOutDate: runOut,
            budDays: vial.budDays,
            budDate: budDate,
            daysSinceRecon: max(0, daysSince),
            isPastBUD: daysSince >= vial.budDays,
            isLow: dosesRemaining.map { $0 <= lowDosesThreshold } ?? false,
            isOverdrawn: remainingRaw < 0,
            hasFractionalLastDose: fractional,
            isLegacy: isLegacyVial(logs: logs, slug: vial.compoundSlug, since: vial.reconstitutedAt)
        )
    }

    /// Forward-walks the schedule day by day, spending `remainingMg` on each due
    /// occurrence at that day's effective (titration-aware) dose, and returns the day
    /// of the first dose that can't be covered. The walk starts today and skips
    /// today's already-taken slots (they've already reduced remaining). Respects
    /// cycles/EOD/weekly via `ScheduleService.occurrences`. nil for PRN or if supply
    /// outlasts the horizon.
    static func runOutDate(item: ProtocolItem, remainingMg: Double, from now: Date,
                           logs: [DoseLog], iuPerMg: Double? = nil,
                           horizonDays: Int = projectionHorizonDays,
                           calendar: Calendar = .current) -> Date? {
        guard let rule = item.schedule, rule.frequency != .prn else { return nil }
        var remaining = remainingMg
        let startDay = calendar.startOfDay(for: now)
        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { break }
            let occ = ScheduleService.occurrences(for: item, on: day, calendar: calendar)
            guard !occ.isEmpty,
                  let doseAmt = doseMg(item.effectiveDose(on: day, calendar: calendar),
                                       unit: item.doseUnit, iuPerMg: iuPerMg), doseAmt > 0
            else { continue }
            for o in occ.sorted(by: { $0.minutes < $1.minutes }) {
                if offset == 0,
                   ScheduleService.state(itemID: item.id, minutes: o.minutes, day: day,
                                         logs: logs, now: now, calendar: calendar) == .taken {
                    continue   // already spent from remaining today
                }
                if remaining < doseAmt { return day }
                remaining -= doseAmt
            }
        }
        return nil
    }

    /// The day of the Nth upcoming scheduled dose (skipping today's already-taken
    /// slots), or nil within the horizon. Lets a low-supply notice fire on the morning
    /// supply is projected to reach the threshold, which is a stable future date, so
    /// rebuilds reschedule the same notice rather than nagging a fresh one each day.
    static func dateAfterDoses(item: ProtocolItem, count: Int, from now: Date,
                               logs: [DoseLog], horizonDays: Int = projectionHorizonDays,
                               calendar: Calendar = .current) -> Date? {
        guard count > 0, let rule = item.schedule, rule.frequency != .prn else { return nil }
        var remaining = count
        let startDay = calendar.startOfDay(for: now)
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        for offset in 0...horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startDay) else { break }
            for o in ScheduleService.occurrences(for: item, on: day, calendar: calendar)
                .sorted(by: { $0.minutes < $1.minutes }) {
                // Only count genuinely upcoming slots: skip today's already-passed or
                // already-taken doses so the projected low-day is a real future morning.
                if offset == 0 {
                    if o.minutes <= nowMinutes { continue }
                    if ScheduleService.state(itemID: item.id, minutes: o.minutes, day: day,
                                             logs: logs, now: now, calendar: calendar) == .taken { continue }
                }
                remaining -= 1
                if remaining == 0 { return day }
            }
        }
        return nil
    }

    // MARK: - Copy builders (pure, CopyGuard-safe: no em dashes, no middle dots)

    /// Primary status line: "4 doses left" / "Less than 1 dose left" / empty + resync
    /// guidance. nil only when the dose can't be converted to mg (no unit tracking).
    static func supplyLine(_ s: Status) -> String? {
        if s.isOverdrawn { return "Supply tracking may be off. Start a new vial to resync." }
        guard s.dosesRemaining != nil else { return nil }
        if s.remainingMg <= 0 { return "Vial looks empty. Start a new vial when you reconstitute." }
        if s.hasFractionalLastDose { return "Less than 1 dose left" }
        let n = s.dosesRemaining ?? 0
        return "\(n) dose\(n == 1 ? "" : "s") left"
    }

    /// "Runs out around Jul 18". nil when there is no projection (PRN / outlasts horizon).
    static func runOutLine(_ s: Status) -> String? {
        guard let date = s.runOutDate else { return nil }
        return "Runs out around \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    /// "Day 12 of 28 since reconstitution".
    static func budLine(_ s: Status) -> String {
        "Day \(s.daysSinceRecon) of \(s.budDays) since reconstitution"
    }
}
