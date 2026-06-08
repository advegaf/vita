#if DEBUG
import Foundation
import SwiftData

/// Debug-only: pre-populate ~30 days of check-ins + weight (trending down) so
/// screenshots show a real Diary. `VITA_DIARY_DEMO=1` leaves today un-logged (the
/// prompt + bloom shot); `=2` logs today too (the summary + streak shot). Never ships.
@MainActor
enum DiaryDemoSeed {
    static func populate(_ context: ModelContext, logToday: Bool) {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        if profile.onboardedAt == nil { profile.onboardedAt = Date() }

        let existing = (try? context.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        guard existing.isEmpty else { return }

        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        // 30 prior days of entries + a weight sample with a gentle downward drift
        // and day-to-day jitter (so the trend line wanders like real data, not a
        // synthetic straight ramp).
        for offset in stride(from: 30, through: 1, by: -1) {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            let t = Double(offset)
            let e = DiaryEntry()
            e.dayStart = day
            e.energy = clamp(6 + Int((sin(t * 0.9) * 2).rounded()))
            e.sleep  = clamp(6 + Int((cos(t * 0.7) * 2).rounded()))
            e.mood   = clamp(6 + Int((sin(t * 1.3 + 1) * 2).rounded()))
            e.libido = clamp(5 + Int((cos(t * 0.5) * 2).rounded()))
            if offset % 7 == 0 { e.sideEffectsRaw = [SideEffect.fatigue.rawValue] }
            if offset == 14 { e.note = "Felt strong this week." }
            e.loggedAt = day
            context.insert(e)

            let w = BodyMetric()
            w.kindRaw = BodyMetricKind.weight.rawValue
            let drift = Double(30 - offset) * 0.11          // ~3.3 kg down over 30d
            let jitter = sin(t * 1.7) * 0.45 + cos(t * 0.6) * 0.25   // ±~0.7 kg wander
            w.valueCanonical = 84.0 - drift + jitter
            w.measuredAt = day
            w.sourceRaw = MetricSource.manual.rawValue
            context.insert(w)
        }

        // A couple of measurements so those chips have a line.
        if let d20 = cal.date(byAdding: .day, value: -20, to: today) {
            let waist = BodyMetric(); waist.kindRaw = BodyMetricKind.waist.rawValue
            waist.valueCanonical = 88; waist.measuredAt = d20; context.insert(waist)
        }
        if let d8 = cal.date(byAdding: .day, value: -8, to: today) {
            let waist = BodyMetric(); waist.kindRaw = BodyMetricKind.waist.rawValue
            waist.valueCanonical = 86; waist.measuredAt = d8; context.insert(waist)
            let arm = BodyMetric(); arm.kindRaw = BodyMetricKind.arm.rawValue
            arm.valueCanonical = 38; arm.measuredAt = d8; context.insert(arm)
        }

        if logToday {
            let e = DiaryEntry()
            e.dayStart = today
            e.energy = 8; e.sleep = 7; e.mood = 8; e.libido = 6
            e.loggedAt = Date()
            context.insert(e)
        }
        try? context.save()
    }

    private static func clamp(_ v: Int) -> Int { min(10, max(1, v)) }
}
#endif
