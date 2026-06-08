import Foundation

/// Pure builder for the Diary line in the uncached chat grounding block (M8a):
/// recent check-in averages (7d) + the weight trend (30d). Returns nil when there's
/// nothing to say, so the grounding block stays tight. Educational framing — these
/// are observed numbers, never a diagnosis (the system prompt enforces voice).
enum DiaryGrounding {
    static func summaryLine(entries: [DiaryEntry], metrics: [BodyMetric],
                            weightUnit: WeightUnit = .lb, asOf now: Date = Date()) -> String? {
        var parts: [String] = []

        let avgs = DiarySeries.recentAverages(entries: entries, days: 7, asOf: now)
        let avgBits: [String] = [DiaryMetric.energy, .sleep, .mood, .libido].compactMap { m in
            guard let a = avgs[m] else { return nil }
            return "\(m.groundingLabel) \(Int(a.rounded()))/10"
        }
        if !avgBits.isEmpty {
            parts.append("Recent check-ins 7d avg: " + avgBits.joined(separator: ", ") + ".")
        }

        let trend = DiarySeries.weightTrend(metrics: metrics, days: 30, asOf: now)
        if let cur = trend.currentKg {
            let toU: (Double) -> Double = { weightUnit == .lb ? Units.kgToLb($0) : $0 }
            let u = weightUnit.rawValue
            if let delta = trend.deltaKg, abs(delta) >= 0.1 {
                let dir = delta < 0 ? "down" : "up"
                parts.append(String(format: "Weight %.1f %@, %@ %.1f %@ over 30d.",
                                    toU(cur), u, dir, abs(toU(delta)), u))
            } else {
                parts.append(String(format: "Weight %.1f %@.", toU(cur), u))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
