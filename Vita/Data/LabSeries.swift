import Foundation

/// One plotted lab result for a marker across panels (display units = the latest
/// result's unit). `id` is the LabValue's id, never the date — two panels can share
/// an effectiveDate.
struct LabTrendPoint: Identifiable, Equatable {
    var id: UUID
    var date: Date              // panel.effectiveDate
    var value: Double
    var unit: String
    var refLow: Double?
    var refHigh: Double?
    var flag: LabFlag           // the STORED computed flag, never recomputed here
    var isOutOfRange: Bool { flag.isOutOfRange }
}

/// Index row for the Labs-list Trends section.
struct LabMarkerSummary: Identifiable, Equatable {
    var markerKey: String
    var name: String            // most recent printed name (falls back to markerKey)
    var latestValue: Double
    var unit: String
    var latestFlag: LabFlag
    var latestDate: Date
    var delta: Double?          // latest minus previous, unit-matched points only
    var pointCount: Int         // unit-matched point count
    var id: String { markerKey }
}

/// Pure marker-over-time derivations across saved LabPanels (M11). Mirrors
/// DiarySeries: static, synchronous, fully unit-testable. Panels arrive in any
/// order (SwiftData to-many relationships and @Query are unordered) — everything
/// here sorts explicitly.
enum LabSeries {

    struct Series: Equatable {
        var points: [LabTrendPoint]   // oldest first, all in `unit`
        var unit: String              // governing unit = the most recent result's
        var skippedCount: Int         // results dropped for unit mismatch
    }

    /// Oldest-first series for one marker, filtered to the latest result's unit
    /// (a marker reported in mmol/L by one lab and mg/dL by another must not plot
    /// on one axis). Unit comparison is case/whitespace-insensitive.
    static func series(markerKey: String, panels: [LabPanel]) -> Series {
        let raw = rawEntries(markerKey: markerKey, panels: panels)
        guard let newest = raw.last else { return Series(points: [], unit: "", skippedCount: 0) }
        let governing = normalizeUnit(newest.value.unit)
        var points: [LabTrendPoint] = []
        var skipped = 0
        for entry in raw {
            if normalizeUnit(entry.value.unit) == governing {
                points.append(LabTrendPoint(
                    id: entry.value.id, date: entry.date, value: entry.value.value,
                    unit: entry.value.unit, refLow: entry.value.refLow,
                    refHigh: entry.value.refHigh, flag: entry.value.flag))
            } else {
                skipped += 1
            }
        }
        return Series(points: points, unit: newest.value.unit, skippedCount: skipped)
    }

    /// All markers seen across the panels, split into trended (>= 2 plottable
    /// points) and single-result, each sorted out-of-range-latest first then name
    /// (the same comparator as LabPanel.orderedValues).
    static func trendedMarkers(panels: [LabPanel]) -> (trended: [LabMarkerSummary], single: [LabMarkerSummary]) {
        var keys: Set<String> = []
        for p in panels {
            for v in (p.values ?? []) where !v.markerKey.isEmpty { keys.insert(v.markerKey) }
        }
        var summaries: [LabMarkerSummary] = []
        for key in keys {
            let s = series(markerKey: key, panels: panels)
            guard let last = s.points.last else { continue }
            let newestRaw = rawEntries(markerKey: key, panels: panels).last?.value
            let name = (newestRaw?.name.isEmpty == false ? newestRaw!.name : key)
            let delta = s.points.count >= 2 ? last.value - s.points[s.points.count - 2].value : nil
            summaries.append(LabMarkerSummary(
                markerKey: key, name: name, latestValue: last.value, unit: last.unit,
                latestFlag: last.flag, latestDate: last.date, delta: delta,
                pointCount: s.points.count))
        }
        summaries.sort { a, b in
            if a.latestFlag.isOutOfRange != b.latestFlag.isOutOfRange { return a.latestFlag.isOutOfRange }
            return a.name < b.name
        }
        return (summaries.filter { $0.pointCount >= 2 }, summaries.filter { $0.pointCount < 2 })
    }

    /// Padded x-domain: first...last padded ~8% per side, floored at 7 days per
    /// side so a single point (or same-day points) still gets breathing room.
    static func dateDomain(for points: [LabTrendPoint]) -> ClosedRange<Date> {
        let dates = points.map(\.date)
        guard let lo = dates.min(), let hi = dates.max() else {
            let now = Date()
            return now.addingTimeInterval(-7 * 86400)...now.addingTimeInterval(7 * 86400)
        }
        let span = hi.timeIntervalSince(lo)
        let pad = max(span * 0.08, 7 * 86400)
        return lo.addingTimeInterval(-pad)...hi.addingTimeInterval(pad)
    }

    /// Padded y-domain that always contains the latest point's reference band.
    /// minSpan is magnitude-relative (markers range from TSH ~2 to testosterone
    /// ~600, so an absolute floor would be wrong at one end or the other).
    static func yDomain(points: [LabTrendPoint], refLow: Double?, refHigh: Double?) -> ClosedRange<Double> {
        var lo = points.map(\.value).min() ?? 0
        var hi = points.map(\.value).max() ?? 1
        if let refLow { lo = Swift.min(lo, refLow) }
        if let refHigh { hi = Swift.max(hi, refHigh) }
        let minSpan = Swift.max(Swift.max(abs(lo), abs(hi)) * 0.1, 0.5)
        return TrendDomain.padded(min: lo, max: hi, minSpan: minSpan)
    }

    // MARK: - Internals

    private static func normalizeUnit(_ u: String) -> String {
        u.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// One (date, value) per panel containing the marker, oldest panel first.
    /// Ties on effectiveDate break on scannedAt; a duplicated marker within one
    /// panel resolves deterministically by id (SwiftData to-many is unordered).
    private static func rawEntries(markerKey: String, panels: [LabPanel]) -> [(date: Date, value: LabValue)] {
        panels
            .sorted {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate < $1.effectiveDate }
                return $0.scannedAt < $1.scannedAt
            }
            .compactMap { panel in
                (panel.values ?? [])
                    .filter { $0.markerKey == markerKey }
                    .min { $0.id.uuidString < $1.id.uuidString }
                    .map { (panel.effectiveDate, $0) }
            }
    }
}
