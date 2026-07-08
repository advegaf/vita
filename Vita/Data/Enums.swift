import SwiftUI

enum PeptideCategory: String, CaseIterable, Codable, Sendable {
    case weightLoss, cognitive, muscleRecovery, sexualHealth, generalHealth, other

    var title: String {
        switch self {
        case .weightLoss:    "Weight Loss"
        case .cognitive:     "Cognitive"
        case .muscleRecovery:"Muscle & Recovery"
        case .sexualHealth:  "Sexual Health"
        case .generalHealth: "General Health"
        case .other:         "Other"
        }
    }

    /// Display order for grouped sections.
    var order: Int {
        switch self {
        case .weightLoss: 0
        case .muscleRecovery: 1
        case .cognitive: 2
        case .sexualHealth: 3
        case .generalHealth: 4
        case .other: 5
        }
    }

    /// One locked tint per category, matched to the vial hues (no hashing).
    var tint: Color {
        switch self {
        case .weightLoss:    VT.catBlue
        case .cognitive:     VT.catPurple
        case .muscleRecovery:VT.catBrown
        case .sexualHealth:  VT.catPink
        case .generalHealth: VT.catYellow
        case .other:         VT.catGray
        }
    }

    /// Asset name of the category's colored vial render.
    var vialAsset: String {
        switch self {
        case .weightLoss:    "vial-blue"
        case .cognitive:     "vial-purple"
        case .muscleRecovery:"vial-brown"
        case .sexualHealth:  "vial-pink"
        case .generalHealth: "vial-yellow"
        case .other:         "vial-gray"
        }
    }

    init(seed raw: String) { self = PeptideCategory(rawValue: raw) ?? .other }
}

enum RxStatus: String, Codable, Sendable { case rx, nonRx, ambiguous }

enum DoseUnit: String, Codable, Sendable {
    case mcg, mg, iu
    var label: String { self == .iu ? "IU" : rawValue }
    /// Converts an amount in this unit to milligrams. IU has no fixed mg ratio, so it
    /// returns nil here; `VialEngine.doseMg` handles IU via the compound's `iuPerMg`
    /// (or the HGH-class approximation) for unit tracking.
    func toMg(_ amount: Double) -> Double? {
        switch self { case .mcg: amount / 1000; case .mg: amount; case .iu: nil }
    }
    /// All units can now be tracked as syringe units (IU via an approximate ratio,
    /// shown with a caption). Kept as a named flag for call-site readability.
    var supportsUnitTracking: Bool { true }
}

enum ScheduleType: String, Codable, Sendable {
    case daily, multiDaily, weekly, interval, cycle, titration, asNeeded
}

/// How a cycle's on/off blocks are entered (stored as days; this is labeling only).
enum CycleUnit: String, Codable, Sendable, CaseIterable {
    case days, weeks
    var label: String { self == .weeks ? "weeks" : "days" }
    var short: String { self == .weeks ? "wk" : "d" }
    /// Capitalized full word for the cycle badge ("Week 4/12" / "Day 3/5").
    var chipWord: String { self == .weeks ? "Week" : "Day" }
    var perStep: Int { self == .weeks ? 7 : 1 }   // multiplier days ↔ unit
}

enum Route: String, Codable, Sendable {
    case subcutaneous, intramuscular, oral, nasal, topical, other
    var label: String {
        switch self {
        case .subcutaneous: "subcutaneous"
        case .intramuscular:"intramuscular"
        case .oral:         "oral"
        case .nasal:        "nasal"
        case .topical:      "topical"
        case .other:        "other"
        }
    }
    var short: String {
        switch self {
        case .subcutaneous: "SubQ"
        case .intramuscular:"IM"
        case .oral:         "oral"
        case .nasal:        "nasal"
        case .topical:      "topical"
        case .other:        "n/a"
        }
    }
}

enum GoalKind: String, CaseIterable, Codable, Sendable {
    case fatLoss, muscleStrength, recoveryHealing, cognitionMood, sexualHealth, longevity
    var label: String {
        switch self {
        case .fatLoss:         "Fat loss"
        case .muscleStrength:  "Muscle & strength"
        case .recoveryHealing: "Recovery & injury healing"
        case .cognitionMood:   "Cognition & mood"
        case .sexualHealth:    "Sexual health"
        case .longevity:       "Longevity & general health"
        }
    }
    var sortIndex: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}

/// How a dose was acted on (persisted in a DoseLog). "missed" is never stored —
/// it's a derived past-day un-acted occurrence.
enum DoseStatus: String, Codable, Sendable { case taken, skipped }

/// Formats a dose number without trailing zeros (250, 0.25, 2.5).
func vtFormatNumber(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%g", d)
}
