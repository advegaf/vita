import SwiftUI
import SwiftData

// MARK: - Models (CloudKit-legal, denormalized like DoseLog — no relationships,
// every property optional/defaulted, no .unique; uniqueness enforced in code).

/// One daily check-in (M8a). `dayStart` (startOfDay) is the upsert key — at most
/// one entry per local day. A rated metric is an Int 1...10; 0 = not rated. A day
/// is "logged" (streak/summary) when at least one metric is rated or there's a
/// side-effect / note.
@Model
final class DiaryEntry {
    var id: UUID = UUID()
    var dayStart: Date = Date.now        // startOfDay key (one per day)
    var energy: Int = 0                   // 1...10, 0 = unset
    var sleep: Int = 0
    var mood: Int = 0
    var libido: Int = 0
    var sideEffectsRaw: [String] = []     // SideEffect.rawValue list
    var note: String = ""
    var loggedAt: Date = Date.now
    init() {}

    var isLogged: Bool {
        energy > 0 || sleep > 0 || mood > 0 || libido > 0 || !sideEffectsRaw.isEmpty || !note.isEmpty
    }
    var ratedCount: Int { [energy, sleep, mood, libido].filter { $0 > 0 }.count }

    /// The 1...10 rating for a rating metric (0 for body metrics / unset).
    func rating(for m: DiaryMetric) -> Int {
        switch m {
        case .energy: energy; case .sleep: sleep; case .mood: mood; case .libido: libido
        default: 0
        }
    }
    var sideEffects: [SideEffect] { sideEffectsRaw.compactMap(SideEffect.init(rawValue:)) }
}

/// One body measurement sample (weight/waist/arm), append-only series. Value is
/// stored in CANONICAL units (weight kg, measurements cm). Apple-Health-imported
/// weigh-ins carry `healthUUID` so the backfill dedupes idempotently; manual
/// entries live alongside.
@Model
final class BodyMetric {
    var id: UUID = UUID()
    var kindRaw: String = BodyMetricKind.weight.rawValue   // weight | waist | arm
    var valueCanonical: Double = 0        // kg for weight, cm for measurements
    var measuredAt: Date = Date.now
    var sourceRaw: String = MetricSource.manual.rawValue   // manual | health
    var healthUUID: String?               // HKSample.uuid string — backfill dedupe key
    init() {}

    var kind: BodyMetricKind { BodyMetricKind(rawValue: kindRaw) ?? .weight }
    var source: MetricSource { MetricSource(rawValue: sourceRaw) ?? .manual }
}

// MARK: - Enums

enum BodyMetricKind: String, CaseIterable, Codable, Sendable {
    case weight, waist, arm
    var label: String { switch self { case .weight: "Weight"; case .waist: "Waist"; case .arm: "Arm" } }
    var canonicalUnit: String { self == .weight ? "kg" : "cm" }
    var isMeasurement: Bool { self != .weight }
}

enum MetricSource: String, Codable, Sendable { case manual, health }

/// Tap-to-tag preset side-effects on a check-in. The free-text note is the escape
/// hatch for anything not listed (no custom tag).
enum SideEffect: String, CaseIterable, Codable, Sendable {
    case nausea, headache, fatigue
    case injectionSite = "injection_site"
    case bloating
    case lowAppetite = "low_appetite"
    case sleepDisruption = "sleep_disruption"
    case irritability, flushing
    var label: String {
        switch self {
        case .nausea: "Nausea"; case .headache: "Headache"; case .fatigue: "Fatigue"
        case .injectionSite: "Injection site"; case .bloating: "Bloating"
        case .lowAppetite: "Low appetite"; case .sleepDisruption: "Sleep disruption"
        case .irritability: "Irritability"; case .flushing: "Flushing"
        }
    }
}

/// Presentation enum: the unified trend/chip metric set + their accents. Single
/// source so the slider, chip, sparkline, and chart line stay in lockstep.
enum DiaryMetric: String, CaseIterable, Identifiable, Sendable {
    case weight, energy, sleep, mood, libido, waist, arm
    var id: String { rawValue }
    var title: String {
        switch self {
        case .weight: "Weight"; case .energy: "Energy"; case .sleep: "Sleep"
        case .mood: "Mood"; case .libido: "Libido"; case .waist: "Waist"; case .arm: "Arm"
        }
    }
    /// Short label for grounding lines ("energy 4/10").
    var groundingLabel: String { rawValue }
    /// Locked palette assignment.
    var accent: Color {
        switch self {
        case .energy: VT.dose       // cyan
        case .sleep:  VT.catPurple  // violet
        case .mood:   VT.timing     // yellow
        case .libido: VT.catPink    // pink
        case .weight, .waist, .arm: VT.why   // brown (body group)
        }
    }
    /// True for the four 1...10 ratings (vs a body measurement value).
    var isRating: Bool { [.energy, .sleep, .mood, .libido].contains(self) }
    /// The body-metric kind backing this metric (nil for ratings).
    var bodyKind: BodyMetricKind? {
        switch self { case .weight: .weight; case .waist: .waist; case .arm: .arm; default: nil }
    }
}
