import Foundation

/// Pure wellness-score math (educational snapshot, never a diagnosis). Blends the
/// latest panel's biomarker mix with 30-day protocol adherence. Also home of the
/// optimal / normal / out-of-range classification the Data surfaces use.
enum HealthScore {

    enum MarkerStatus: Equatable { case optimal, normal, outOfRange }

    /// Classifies a numeric value against its reference range. "Optimal" = the
    /// central 60% of the range (an educational heuristic, not a clinical claim);
    /// in-range but near an edge = normal; outside = out of range. nil when the
    /// value or range can't support the math (qualitative rows, missing bounds).
    static func classify(value: Double?, refLow: Double?, refHigh: Double?) -> MarkerStatus? {
        guard let value else { return nil }
        switch (refLow, refHigh) {
        case let (lo?, hi?) where hi > lo:
            if value < lo || value > hi { return .outOfRange }
            let span = hi - lo
            let inner = (lo + span * 0.2)...(hi - span * 0.2)
            return inner.contains(value) ? .optimal : .normal
        case let (lo?, nil):
            return value >= lo ? .normal : .outOfRange
        case let (nil, hi?):
            return value <= hi ? .normal : .outOfRange
        default:
            return nil
        }
    }

    struct Result: Equatable {
        var score: Int               // 0-100
        var optimal: Int
        var normal: Int
        var outOfRange: Int
        var hasLabs: Bool
        var total: Int { optimal + normal + outOfRange }
    }

    /// Score = 70% biomarker mix (optimal 1.0, normal 0.6, out 0.0) + 30% adherence
    /// (logged/scheduled over 30 days; full credit when nothing was scheduled).
    /// Without labs, the score is adherence-only and `hasLabs` is false.
    static func compute(statuses: [MarkerStatus], adherenceLogged: Int,
                        adherenceScheduled: Int) -> Result {
        let optimal = statuses.filter { $0 == .optimal }.count
        let normal = statuses.filter { $0 == .normal }.count
        let out = statuses.filter { $0 == .outOfRange }.count
        let total = statuses.count

        let adherence = adherenceScheduled > 0
            ? Double(adherenceLogged) / Double(adherenceScheduled) : 1.0

        let score: Double
        if total > 0 {
            let labMix = (Double(optimal) * 1.0 + Double(normal) * 0.6) / Double(total)
            score = labMix * 70 + adherence * 30
        } else {
            score = adherence * 100
        }
        return Result(score: Int(score.rounded()), optimal: optimal, normal: normal,
                      outOfRange: out, hasLabs: total > 0)
    }
}
