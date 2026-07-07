import Foundation

/// A value-type snapshot of one stack compound for correlation (extracted at the call
/// site so the engine stays a pure function of value types, off-main testable).
struct CompoundWindow: Sendable, Equatable {
    var name: String
    /// A user-set protocol start, if one exists (nil when only the add-date is known).
    var startDate: Date?
    /// When the compound was added to the stack (the honest fallback anchor).
    var addedDate: Date

    /// The date correlations anchor to, and whether it is a true start or just the add.
    var anchor: Date { startDate ?? addedDate }
    var hasRealStart: Bool { startDate != nil }
}

/// One educational vitals insight. Copy is always hedged; correlation lines say so.
struct VitalInsight: Equatable, Identifiable {
    enum Metric: String { case hrv, restingHR, sleep, respiratory, general }
    enum Tone { case attention, info, positive }
    var metric: Metric
    var tone: Tone
    var headline: String
    var detail: String
    var isCorrelation: Bool = false
    var id: String { (isCorrelation ? "corr-" : "base-") + metric.rawValue }
}

/// Pure vitals analysis (M38). Baselines compare a recent window against the user's
/// own 30-day baseline; correlations anchor to when a compound started (or was added).
/// Calendar-injectable, no HealthKit, no SwiftData.
enum VitalsInsightEngine {
    static let recentDays = 7
    static let baselineWindowDays = 30
    static let minBaselineSamples = 10
    static let minRecentSamples = 3

    // Rule thresholds.
    static let hrvDropFraction = 0.10        // HRV down >10% vs baseline
    static let rhrRiseFraction = 0.05        // resting HR up >5%...
    static let rhrRiseBpm = 3.0              // ...or +3 bpm
    static let sleepDebtHours = 0.75         // >45 min below baseline
    static let respRiseFraction = 0.08       // respiratory up >8%
    // Persistence: an attention insight needs the threshold breached on `persistNeed`
    // of the last `persistWindow` days that have data (damps noisy consumer HRV).
    static let persistWindow = 5
    static let persistNeed = 3
    static let maxInsights = 2

    // MARK: Windowed averages

    static func average(_ series: [DatedValue], from: Date, to: Date) -> (avg: Double, count: Int)? {
        let vals = series.filter { $0.day >= from && $0.day < to }.map(\.value)
        guard !vals.isEmpty else { return nil }
        return (vals.reduce(0, +) / Double(vals.count), vals.count)
    }

    /// Mean over the `windowDays` days immediately preceding the recent window (min
    /// sample count). With defaults, this is "days 7 through 36 ago".
    static func baseline(_ series: [DatedValue], excludingLastDays: Int = recentDays,
                         windowDays: Int = baselineWindowDays, asOf: Date,
                         calendar: Calendar = .current) -> Double? {
        let from = calendar.date(byAdding: .day, value: -(excludingLastDays + windowDays - 1), to: asOf) ?? asOf
        let to = calendar.date(byAdding: .day, value: -(excludingLastDays - 1), to: asOf) ?? asOf
        guard let r = average(series, from: from, to: to), r.count >= minBaselineSamples else { return nil }
        return r.avg
    }

    /// Mean over exactly the last `days` days (today and the `days - 1` before it).
    static func recentAverage(_ series: [DatedValue], days: Int = recentDays, asOf: Date,
                              calendar: Calendar = .current) -> Double? {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: asOf) ?? asOf
        let end = calendar.date(byAdding: .day, value: 1, to: asOf) ?? asOf
        guard let r = average(series, from: start, to: end), r.count >= minRecentSamples else { return nil }
        return r.avg
    }

    /// True when a per-day predicate holds on at least `persistNeed` of the last
    /// `persistWindow` days that have data.
    private static func persists(_ series: [DatedValue], asOf: Date, calendar: Calendar,
                                 breaches: (Double) -> Bool) -> Bool {
        let start = calendar.date(byAdding: .day, value: -persistWindow, to: asOf) ?? asOf
        let recent = series.filter { $0.day >= start }.suffix(persistWindow)
        guard !recent.isEmpty else { return false }
        return recent.filter { breaches($0.value) }.count >= min(persistNeed, recent.count)
    }

    // MARK: Insights

    static func insights(_ s: VitalsSeries, windows: [CompoundWindow] = [], asOf now: Date = Date(),
                         calendar: Calendar = .current) -> [VitalInsight] {
        var correlations: [VitalInsight] = []
        var attentions: [VitalInsight] = []
        var infos: [VitalInsight] = []

        // 1. Correlation vs the most recent compound anchored inside the data window.
        if let w = mostRecentAnchored(windows, asOf: now, calendar: calendar) {
            if let c = correlation(metric: .restingHR, series: s.restingHR, window: w, asOf: now,
                                   calendar: calendar, adverseWhenHigher: true, unit: "bpm",
                                   minDelta: rhrRiseBpm) {
                correlations.append(c)
            } else if let c = correlation(metric: .hrv, series: s.hrvMs, window: w, asOf: now,
                                          calendar: calendar, adverseWhenHigher: false, unit: "ms",
                                          minDelta: 5) {
                correlations.append(c)
            }
        }

        // 2. Baseline-delta rules (attention ones are persistence-gated).
        if let base = baseline(s.hrvMs, asOf: now, calendar: calendar),
           let recent = recentAverage(s.hrvMs, asOf: now, calendar: calendar),
           recent < base * (1 - hrvDropFraction),
           persists(s.hrvMs, asOf: now, calendar: calendar, breaches: { $0 < base * (1 - hrvDropFraction) }) {
            attentions.append(.init(metric: .hrv, tone: .attention,
                headline: "HRV is running below your baseline.",
                detail: "7-day average \(mg(recent)) ms versus a 30-day baseline of \(mg(base)) ms. Recovery load may be worth watching."))
        }
        if let base = baseline(s.restingHR, asOf: now, calendar: calendar),
           let recent = recentAverage(s.restingHR, asOf: now, calendar: calendar),
           (recent > base * (1 + rhrRiseFraction) || recent > base + rhrRiseBpm),
           persists(s.restingHR, asOf: now, calendar: calendar, breaches: { $0 > base + rhrRiseBpm }) {
            attentions.append(.init(metric: .restingHR, tone: .attention,
                headline: "Resting heart rate is up versus your baseline.",
                detail: "7-day average \(mg(recent)) bpm versus a 30-day baseline of \(mg(base)) bpm. This can follow stress, illness, or poor sleep."))
        }
        if let base = baseline(s.sleepHours, asOf: now, calendar: calendar),
           let recent = recentAverage(s.sleepHours, asOf: now, calendar: calendar),
           recent < base - sleepDebtHours,
           persists(s.sleepHours, asOf: now, calendar: calendar, breaches: { $0 < base - sleepDebtHours }) {
            attentions.append(.init(metric: .sleep, tone: .attention,
                headline: "Sleep is below your usual.",
                detail: "About \(oneDp(base - recent)) hours less per night than your 30-day average."))
        }
        if let base = baseline(s.respiratoryRate, asOf: now, calendar: calendar),
           let recent = recentAverage(s.respiratoryRate, asOf: now, calendar: calendar),
           recent > base * (1 + respRiseFraction) {
            infos.append(.init(metric: .respiratory, tone: .info,
                headline: "Respiratory rate is slightly elevated.",
                detail: "7-day average \(oneDp(recent)) versus \(oneDp(base)) breaths per minute."))
        }

        // 3. Assemble: at most one attention (correlation wins), then info, cap total.
        var out: [VitalInsight] = []
        if let c = correlations.first { out.append(c) }
        else if let a = attentions.first { out.append(a) }
        out += infos.prefix(maxInsights - out.count)

        if out.isEmpty {
            out.append(.init(metric: .general, tone: .positive,
                headline: "Your vitals are steady versus your baseline.",
                detail: "Nothing notable in HRV, resting heart rate, or sleep over the last week."))
        }
        return Array(out.prefix(maxInsights))
    }

    /// One grounding line for chat, recent vs baseline for each metric with data.
    static func groundingLine(_ s: VitalsSeries, asOf now: Date = Date(),
                              calendar: Calendar = .current) -> String? {
        var bits: [String] = []
        if let r = recentAverage(s.hrvMs, asOf: now, calendar: calendar),
           let b = baseline(s.hrvMs, asOf: now, calendar: calendar) {
            bits.append("HRV 7d \(mg(r)) ms vs 30d \(mg(b)) ms")
        }
        if let r = recentAverage(s.restingHR, asOf: now, calendar: calendar),
           let b = baseline(s.restingHR, asOf: now, calendar: calendar) {
            bits.append("resting HR \(mg(r)) vs \(mg(b)) bpm")
        }
        if let r = recentAverage(s.sleepHours, asOf: now, calendar: calendar),
           let b = baseline(s.sleepHours, asOf: now, calendar: calendar) {
            bits.append("sleep \(oneDp(r)) vs \(oneDp(b)) h")
        }
        return bits.isEmpty ? nil : bits.joined(separator: "; ")
    }

    // MARK: Correlation helper

    private static func mostRecentAnchored(_ windows: [CompoundWindow], asOf: Date,
                                           calendar: Calendar) -> CompoundWindow? {
        let earliest = calendar.date(byAdding: .day, value: -baselineWindowDays, to: asOf) ?? asOf
        let latest = calendar.date(byAdding: .day, value: -minRecentSamples, to: asOf) ?? asOf
        return windows.filter { $0.anchor >= earliest && $0.anchor <= latest }
            .max { $0.anchor < $1.anchor }
    }

    private static func correlation(metric: VitalInsight.Metric, series: [DatedValue],
                                    window w: CompoundWindow, asOf: Date, calendar: Calendar,
                                    adverseWhenHigher: Bool, unit: String, minDelta: Double) -> VitalInsight? {
        let beforeStart = calendar.date(byAdding: .day, value: -14, to: w.anchor) ?? w.anchor
        let afterEnd = calendar.date(byAdding: .day, value: 1, to: asOf) ?? asOf
        guard let before = average(series, from: beforeStart, to: w.anchor), before.count >= minRecentSamples,
              let after = average(series, from: w.anchor, to: afterEnd), after.count >= minRecentSamples
        else { return nil }
        let delta = after.avg - before.avg
        let adverse = adverseWhenHigher ? delta >= minDelta : delta <= -minDelta
        guard abs(delta) >= minDelta else { return nil }

        let dateStr = w.anchor.formatted(.dateTime.month(.abbreviated).day())
        let anchorPhrase = w.hasRealStart ? "\(w.name) started \(dateStr)" : "you added \(w.name)"
        let dirWord: String
        switch metric {
        case .restingHR: dirWord = delta >= 0 ? "up \(mg(delta)) bpm" : "down \(mg(-delta)) bpm"
        case .hrv:       dirWord = delta >= 0 ? "up \(mg(delta)) ms" : "down \(mg(-delta)) ms"
        default:         dirWord = "\(mg(delta)) \(unit)"
        }
        let label = metric == .hrv ? "HRV" : "Resting heart rate"
        return VitalInsight(
            metric: metric, tone: adverse ? .attention : .info,
            headline: "\(label) has averaged \(dirWord) since \(anchorPhrase).",
            detail: "Before \(mg(before.avg)) \(unit), since then \(mg(after.avg)) \(unit). This is a correlation, not causation. Educational, not medical advice.",
            isCorrelation: true)
    }

    private static func mg(_ v: Double) -> String { String(Int(v.rounded())) }
    private static func oneDp(_ v: Double) -> String { String(format: "%.1f", v) }
}
