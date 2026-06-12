import Foundation

/// Pure builder for the Labs line in the AI grounding blocks (chat + protocol).
/// The latest panel's out-of-range markers as one educational line; nil when there
/// are no panels or nothing is flagged, so the block stays tight. Observed numbers
/// only — never a diagnosis (the system prompt enforces voice).
enum LabGrounding {
    static func summaryLine(panels: [LabPanel]) -> String? {
        guard let latest = panels.max(by: { $0.effectiveDate < $1.effectiveDate }) else { return nil }
        let flagged = (latest.values ?? []).filter { $0.flag.isOutOfRange }
        guard !flagged.isEmpty else { return nil }
        let bits = flagged.sorted { $0.name < $1.name }.prefix(8).map { v in
            "\(v.name) \(vtFormatNumber(v.value)) \(v.unit) (\(v.flag.label.lowercased()))"
        }
        return "Recent labs, out of printed range: " + bits.joined(separator: ", ") + "."
    }

    /// The prefilled chat ask after saving a panel in-app ("Ask vita to review
    /// your plan →"). The user sees and sends it themselves; chat's per-send
    /// grounding carries the full stack + labs context alongside it.
    static func stackReviewPrompt(panels: [LabPanel]) -> String {
        if let line = summaryLine(panels: panels) {
            return line + " Review my current stack against these results. Anything to add, adjust, or watch?"
        }
        return "I just imported new lab results and everything is in range. Anything in my current stack worth revisiting?"
    }
}
