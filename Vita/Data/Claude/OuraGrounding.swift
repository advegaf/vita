import Foundation

/// Pure builder for the Oura line in the uncached chat grounding block (M49):
/// the ring's latest night in one tight sentence so the assistant can reason
/// about recovery alongside the stack. Returns nil when nothing is connected,
/// keeping the block unchanged for non-Oura users. Educational framing only —
/// observed numbers, never a diagnosis (the system prompt enforces voice).
enum OuraGrounding {
    static func summaryLine(_ summary: OuraDailySummary?) -> String? {
        guard let s = summary, !s.isEmpty else { return nil }
        var bits: [String] = []

        if let v = s.vitals.sleepHours.last?.value {
            bits.append(String(format: "sleep %.1f h", v))
        }
        if let v = s.vitals.hrvMs.last?.value {
            bits.append(String(format: "HRV %.0f ms", v))
        }
        if let v = s.vitals.restingHR.last?.value {
            bits.append(String(format: "resting HR %.0f bpm", v))
        }
        if let v = s.vitals.respiratoryRate.last?.value {
            bits.append(String(format: "breath %.1f/min", v))
        }
        if let r = s.readiness.last?.score { bits.append("readiness \(r)/100") }
        if let r = s.sleepScore.last?.score { bits.append("sleep score \(r)/100") }
        if let t = s.temperatureDeviation.last?.value, abs(t) >= 0.05 {
            bits.append(String(format: "temp %+.1f C vs baseline", t))
        }

        guard !bits.isEmpty else { return nil }
        return "Wearables (Oura, latest night): " + bits.joined(separator: ", ") + "."
    }
}
