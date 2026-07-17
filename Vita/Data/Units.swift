import Foundation

/// Pure unit conversions for the profile fields. Storage is canonical metric
/// (kg, cm); display/entry converts to the user's chosen unit.
enum Units {
    static let lbPerKg = 2.2046226218
    static let cmPerInch = 2.54

    /// Locale-tolerant numeric input: comma-decimal keyboards type "82,5", which
    /// `Double.init` rejects — silently dropping the user's measurement.
    static func parseDouble(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    static func kgToLb(_ kg: Double) -> Double { kg * lbPerKg }
    static func lbToKg(_ lb: Double) -> Double { lb / lbPerKg }

    static func cmToInches(_ cm: Double) -> Double { cm / cmPerInch }
    static func inchesToCm(_ inch: Double) -> Double { inch * cmPerInch }

    static func cmToFeetInches(_ cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = (cm / 2.54).rounded()
        var feet = Int(totalInches) / 12
        var inches = Int(totalInches) % 12
        if inches == 12 { feet += 1; inches = 0 }   // guard rounding to a full foot
        return (feet, inches)
    }

    static func feetInchesToCm(feet: Int, inches: Int) -> Double {
        Double(feet * 12 + inches) * 2.54
    }

    /// Formats a number without trailing zeros (78, 172.4).
    static func trim(_ d: Double) -> String {
        d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
    }

    /// Range-aware dose stepper increment (M50). With an educational range the
    /// step is ~1/8 of the span snapped to a clean 1/2.5/5 x 10^n value, so a
    /// 200-600 mcg compound steps by 50 instead of a tiny fixed tick. Per-unit
    /// floors keep steps sensible for narrow ranges; no range keeps the
    /// original per-unit defaults.
    static func doseStep(lo: Double?, hi: Double?, unit: DoseUnit) -> Double {
        let fallback: Double = switch unit { case .mcg: 50; case .mg: 0.25; case .iu: 0.5 }
        let floor: Double = switch unit { case .mcg: 5; case .mg: 0.05; case .iu: 0.25 }
        guard let lo, let hi, hi > lo else { return fallback }
        return max(niceStep((hi - lo) / 8), floor)
    }

    /// Snaps a raw step to the nearest-below {1, 2.5, 5} x 10^n value.
    static func niceStep(_ raw: Double) -> Double {
        guard raw > 0, raw.isFinite else { return 1 }
        let exponent = Foundation.floor(log10(raw))
        let magnitude = pow(10, exponent)
        let fraction = raw / magnitude
        let nice: Double = fraction >= 5 ? 5 : (fraction >= 2.5 ? 2.5 : 1)
        return nice * magnitude
    }
}

enum WeightUnit: String { case kg, lb }
enum HeightUnit: String { case cm, ftIn }
/// Body-measurement display unit (canonical storage is always cm).
enum MeasurementUnit: String { case cm, inch = "in" }
