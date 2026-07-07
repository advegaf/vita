import SwiftUI
import SwiftData

// MARK: - Lab models (CloudKit-legal). A panel OWNS its values, so unlike the
// denormalized DoseLog/DiaryEntry history this uses a relationship + explicit
// inverse with .cascade (matches ProtocolPlan <-> ProtocolItem).

@Model
final class LabPanel {
    var id: UUID = UUID()
    var scannedAt: Date = Date.now
    var panelDate: Date?
    var sourceLabName: String?
    var summary: String = ""
    var disclaimer: String = ""
    @Attribute(.externalStorage) var scanData: Data?   // EXIF-stripped jpeg/pdf bytes, local-only
    var scanMediaType: String?                          // "image/jpeg" | "application/pdf"
    @Relationship(deleteRule: .cascade, inverse: \LabValue.panel) var values: [LabValue]?
    init() {}

    /// Out-of-range markers first (clay), then printed/name order.
    var orderedValues: [LabValue] {
        (values ?? []).sorted { a, b in
            let ao = a.flag == .high || a.flag == .low
            let bo = b.flag == .high || b.flag == .low
            if ao != bo { return ao }                    // flagged first
            return a.name < b.name
        }
    }
    var flaggedCount: Int { (values ?? []).filter { $0.flag == .high || $0.flag == .low }.count }
    var effectiveDate: Date { panelDate ?? scannedAt }
}

@Model
final class LabValue {
    var id: UUID = UUID()
    var markerKey: String = ""
    var name: String = ""
    var value: Double = 0
    var unit: String = ""
    var refLow: Double?
    var refHigh: Double?
    var refText: String?
    var flagRaw: String?                                    // verbatim printed flag (display/debug only)
    var flagComputedRaw: String = LabFlag.unknown.rawValue  // app-computed flag = source of truth
    /// Set when the result was qualitative ("Negative"/"Positive"); shown in place of the number.
    var qualitativeText: String?
    var panel: LabPanel?
    init() {}

    var flag: LabFlag { LabFlag(rawValue: flagComputedRaw) ?? .unknown }

    /// The reading to display: the qualitative word when present, else the number + unit.
    var valueDisplay: String {
        if let q = qualitativeText, !q.isEmpty { return q }
        return "\(vtFormatNumber(value)) \(unit)".trimmingCharacters(in: .whitespaces)
    }

    /// "70–99 mg/dL" / "<150" / "n/a" for the printed reference.
    var refDisplay: String {
        if let lo = refLow, let hi = refHigh { return "\(vtFormatNumber(lo))–\(vtFormatNumber(hi))" }
        if let t = refText, !t.isEmpty { return ChatText.sanitize(t) }  // legacy stored text
        if let lo = refLow { return "≥ \(vtFormatNumber(lo))" }
        if let hi = refHigh { return "≤ \(vtFormatNumber(hi))" }
        return "n/a"
    }
}

/// High/low ONLY use the clay overdue color (the design's single non-green flag);
/// in-range is brown (the "good/logged" tone); no range is muted.
enum LabFlag: String, CaseIterable, Codable, Sendable {
    case low, normal, high, unknown
    var color: Color {
        switch self {
        case .high, .low: VT.overdue
        case .normal:     VT.why
        case .unknown:    VT.micro
        }
    }
    var label: String {
        switch self { case .low: "Low"; case .normal: "In range"; case .high: "High"; case .unknown: "No range" }
    }
    var isOutOfRange: Bool { self == .high || self == .low }
}
