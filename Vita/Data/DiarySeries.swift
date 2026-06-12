import Foundation

/// One point in a daily series; `value == nil` means no data that day (Charts
/// breaks the line / the sparkline skips it).
struct DiaryPoint: Identifiable, Equatable {
    var day: Date
    var value: Double?
    var id: Date { day }
}

/// Pure derivations powering the sparkline, the hero chart, and the AI grounding.
enum DiarySeries {

    /// `days` slots back from `asOf` (inclusive), oldest first, one slot per day.
    /// Ratings come from `DiaryEntry`; body metrics keep the latest sample per day
    /// (canonical units). Missing days carry `nil`.
    static func series(_ metric: DiaryMetric, entries: [DiaryEntry], metrics: [BodyMetric],
                       days: Int, asOf now: Date, calendar: Calendar = .current) -> [DiaryPoint] {
        let today = calendar.startOfDay(for: now)
        var byDay: [Date: Double] = [:]
        if metric.isRating {
            for e in entries {
                let v = e.rating(for: metric)
                guard v > 0 else { continue }
                byDay[calendar.startOfDay(for: e.dayStart)] = Double(v)   // already one entry/day
            }
        } else if let kind = metric.bodyKind {
            var latestAt: [Date: Date] = [:]
            for m in metrics where m.kind == kind {
                let d = calendar.startOfDay(for: m.measuredAt)
                if let prev = latestAt[d], prev >= m.measuredAt { continue }
                latestAt[d] = m.measuredAt
                byDay[d] = m.valueCanonical
            }
        }
        return (0..<max(days, 0)).reversed().map { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return DiaryPoint(day: d, value: byDay[d])
        }
    }

    /// Most recent sample of a body kind (canonical units).
    static func latest(_ kind: BodyMetricKind, metrics: [BodyMetric]) -> Double? {
        metrics.filter { $0.kind == kind }.max { $0.measuredAt < $1.measuredAt }?.valueCanonical
    }

    /// 7-day (or N-day) averages of the four ratings, ignoring unset (0) values.
    /// A "7-day" window is today + the 6 prior days: `-(days - 1)` from today's
    /// start, not `-days` (which silently averaged an 8th day in).
    static func recentAverages(entries: [DiaryEntry], days: Int, asOf now: Date,
                               calendar: Calendar = .current) -> [DiaryMetric: Double] {
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1),
                                   to: calendar.startOfDay(for: now)) ?? now
        let recent = entries.filter { $0.dayStart >= cutoff }
        var out: [DiaryMetric: Double] = [:]
        for m in [DiaryMetric.energy, .sleep, .mood, .libido] {
            let vals = recent.map { $0.rating(for: m) }.filter { $0 > 0 }
            if !vals.isEmpty { out[m] = Double(vals.reduce(0, +)) / Double(vals.count) }
        }
        return out
    }

    /// Current weight + signed delta (current − earliest) over the window (canonical kg).
    static func weightTrend(metrics: [BodyMetric], days: Int, asOf now: Date,
                            calendar: Calendar = .current) -> (currentKg: Double?, deltaKg: Double?) {
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1),
                                   to: calendar.startOfDay(for: now)) ?? now
        let weights = metrics.filter { $0.kind == .weight && $0.measuredAt >= cutoff }
            .sorted { $0.measuredAt < $1.measuredAt }
        guard let last = weights.last else { return (nil, nil) }
        guard let first = weights.first, weights.count > 1 else { return (last.valueCanonical, nil) }
        return (last.valueCanonical, last.valueCanonical - first.valueCanonical)
    }
}

/// Pure y-domain padding for the trend chart so a plotted line floats in the
/// middle ~60% of the height and never touches the top/bottom edge. `minSpan`
/// is a floor so a near-flat series still gets vertical room (reads as a gentle
/// wander centered in the card, not a flat or edge-hugging line).
enum TrendDomain {
    static func padded(min lo: Double, max hi: Double, minSpan: Double) -> ClosedRange<Double> {
        let mid = (lo + hi) / 2
        let span = Swift.max(hi - lo, minSpan)   // floor for near-flat data
        let half = (span / 0.6) / 2              // data occupies the middle 60%
        return (mid - half)...(mid + half)
    }
}
