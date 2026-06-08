import Foundation

/// Insulin-syringe scales. `unitsPerML` is how many syringe units make up 1 mL.
enum SyringeType: String, Codable, Sendable, CaseIterable {
    case u100, u50, u40
    var unitsPerML: Double { switch self { case .u100: 100; case .u50: 50; case .u40: 40 } }
    var label: String { switch self { case .u100: "U-100"; case .u50: "U-50"; case .u40: "U-40" } }
}

enum ReconWarning: String, Sendable {
    case belowResolution   // < 1 unit: hard to measure accurately
    case doseExceedsVial   // dose larger than the whole vial
    case zeroInput         // missing/zero vial or water
}

struct ReconResult: Sendable {
    var concentrationMgPerMl: Double
    var volumeMl: Double
    var exactUnits: Double
    var roundedUnits: Double          // nearest 0.5u for display
    var warnings: [ReconWarning]
}

/// Pure reconstitution math. mL = doseMg / (vialMg/waterMl); units = mL × syringe.unitsPerML.
/// Carry full precision; round only at display. Worked check: 5 mg + 2 mL, 0.25 mg, U-100
/// → 2.5 mg/mL → 0.1 mL → 10 units.
enum ReconstitutionCalculator {

    static func concentration(vialMg: Double, waterMl: Double) -> Double {
        guard waterMl > 0 else { return 0 }
        return vialMg / waterMl
    }

    /// `doseMg` is the dose expressed in milligrams (callers convert mcg → mg first).
    static func result(doseMg: Double, vialMg: Double, waterMl: Double,
                       syringe: SyringeType) -> ReconResult {
        var warnings: [ReconWarning] = []
        guard vialMg > 0, waterMl > 0 else {
            return ReconResult(concentrationMgPerMl: 0, volumeMl: 0,
                               exactUnits: 0, roundedUnits: 0, warnings: [.zeroInput])
        }
        let conc = vialMg / waterMl                  // mg per mL
        let volumeMl = doseMg / conc                 // mL to draw
        let units = volumeMl * syringe.unitsPerML
        if doseMg > vialMg { warnings.append(.doseExceedsVial) }
        if units > 0 && units < 1 { warnings.append(.belowResolution) }
        return ReconResult(
            concentrationMgPerMl: conc,
            volumeMl: volumeMl,
            exactUnits: units,
            roundedUnits: (units * 2).rounded() / 2,   // nearest 0.5u
            warnings: warnings
        )
    }

    /// Convenience for callers holding a dose in arbitrary units (mcg/mg/iu → mg).
    static func units(doseMg: Double, vialMg: Double, waterMl: Double, syringe: SyringeType) -> Double {
        result(doseMg: doseMg, vialMg: vialMg, waterMl: waterMl, syringe: syringe).roundedUnits
    }

    /// HGH-class approximation: ~3 IU per mg. Used by the calculator's mg ↔ IU toggle.
    static let iuPerMg = 3.0
    static func mgFromIU(_ iu: Double) -> Double { iu / iuPerMg }
    static func iuFromMg(_ mg: Double) -> Double { mg * iuPerMg }
}

/// Formats a units value without trailing zeros (10, 7.5).
func vtFormatUnits(_ u: Double) -> String {
    u == u.rounded() ? String(Int(u)) : String(format: "%g", u)
}
