import Foundation
import SwiftData

/// The write path for the Diary (M8a). Mirrors DoseLogger: upsert today's check-in
/// by `dayStart` (re-editing flips fields, never duplicates), append body metrics,
/// and merge Apple-Health weigh-ins idempotently by `healthUUID`.
@MainActor
struct DiaryService {
    let context: ModelContext

    /// Pure day match (testable without a container).
    nonisolated static func matchesDay(_ e: DiaryEntry, dayStart: Date, calendar: Calendar = .current) -> Bool {
        calendar.isDate(e.dayStart, inSameDayAs: dayStart)
    }

    private func allEntries() -> [DiaryEntry] { (try? context.fetch(FetchDescriptor<DiaryEntry>())) ?? [] }
    private func allMetrics() -> [BodyMetric] { (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? [] }

    func entry(on day: Date = Date()) -> DiaryEntry? {
        let start = Calendar.current.startOfDay(for: day)
        return allEntries().first { Self.matchesDay($0, dayStart: start) }
    }

    /// Upsert today's check-in (re-edit flips fields, never duplicates per day).
    @discardableResult
    func upsertToday(energy: Int, sleep: Int, mood: Int, libido: Int,
                     sideEffects: [SideEffect], note: String, on day: Date = Date()) -> DiaryEntry {
        let start = Calendar.current.startOfDay(for: day)
        let e = entry(on: day) ?? { let n = DiaryEntry(); context.insert(n); return n }()
        e.dayStart = start
        e.energy = energy; e.sleep = sleep; e.mood = mood; e.libido = libido
        e.sideEffectsRaw = sideEffects.map(\.rawValue)
        e.note = note
        e.loggedAt = Date()
        try? context.save()
        return e
    }

    /// Append a body measurement (manual source). Value is canonical (kg or cm).
    func addBodyMetric(_ kind: BodyMetricKind, valueCanonical: Double, at when: Date = Date()) {
        let m = BodyMetric()
        m.kindRaw = kind.rawValue; m.valueCanonical = valueCanonical
        m.measuredAt = when; m.sourceRaw = MetricSource.manual.rawValue
        context.insert(m); try? context.save()
    }

    /// Idempotent Apple-Health weight backfill — inserts only unseen HK sample UUIDs,
    /// so re-running the ~90-day import never doubles a day. Never writes Health.
    func mergeHealthWeights(_ samples: [(uuid: String, kg: Double, date: Date)]) {
        let known = Set(allMetrics().compactMap { $0.healthUUID })
        var inserted = false
        for s in samples where !known.contains(s.uuid) {
            let m = BodyMetric()
            m.kindRaw = BodyMetricKind.weight.rawValue
            m.valueCanonical = s.kg; m.measuredAt = s.date
            m.sourceRaw = MetricSource.health.rawValue; m.healthUUID = s.uuid
            context.insert(m); inserted = true
        }
        if inserted { try? context.save() }
    }
}
