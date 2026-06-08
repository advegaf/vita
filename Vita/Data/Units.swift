import Foundation

/// Pure unit conversions for the profile fields. Storage is canonical metric
/// (kg, cm); display/entry converts to the user's chosen unit.
enum Units {
    static let lbPerKg = 2.2046226218
    static let cmPerInch = 2.54

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
}

enum WeightUnit: String { case kg, lb }
enum HeightUnit: String { case cm, ftIn }
/// Body-measurement display unit (canonical storage is always cm).
enum MeasurementUnit: String { case cm, inch = "in" }
