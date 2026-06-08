import XCTest
@testable import Vita

final class ReconstitutionCalculatorTests: XCTestCase {

    /// The canonical worked example: 5 mg vial + 2 mL water, 0.25 mg dose, U-100.
    /// 2.5 mg/mL → 0.1 mL → 10 units.
    func testWorkedExampleU100() {
        let r = ReconstitutionCalculator.result(doseMg: 0.25, vialMg: 5, waterMl: 2, syringe: .u100)
        XCTAssertEqual(r.concentrationMgPerMl, 2.5, accuracy: 1e-9)
        XCTAssertEqual(r.volumeMl, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.roundedUnits, 10, accuracy: 1e-9)
        XCTAssertTrue(r.warnings.isEmpty)
    }

    /// Same 0.1 mL draw on a U-50 syringe reads 5 units (50 units = 1 mL).
    func testU50() {
        XCTAssertEqual(ReconstitutionCalculator.units(doseMg: 0.25, vialMg: 5, waterMl: 2, syringe: .u50),
                       5, accuracy: 1e-9)
    }

    /// U-40: 0.1 mL × 40 = 4 units.
    func testU40() {
        XCTAssertEqual(ReconstitutionCalculator.units(doseMg: 0.25, vialMg: 5, waterMl: 2, syringe: .u40),
                       4, accuracy: 1e-9)
    }

    func testRoundsToHalfUnit() {
        // 0.3 mg in a 5mg/2mL vial = 0.12 mL = 12 units exactly.
        XCTAssertEqual(ReconstitutionCalculator.units(doseMg: 0.3, vialMg: 5, waterMl: 2, syringe: .u100),
                       12, accuracy: 1e-9)
        // A dose giving 7.4 units rounds to 7.5.
        let r = ReconstitutionCalculator.result(doseMg: 0.185, vialMg: 5, waterMl: 2, syringe: .u100)
        XCTAssertEqual(r.roundedUnits, 7.5, accuracy: 1e-9)
    }

    func testBelowResolutionWarning() {
        // Tiny dose → < 1 unit.
        let r = ReconstitutionCalculator.result(doseMg: 0.01, vialMg: 10, waterMl: 2, syringe: .u100)
        XCTAssertTrue(r.warnings.contains(.belowResolution))
    }

    func testDoseExceedsVialWarning() {
        let r = ReconstitutionCalculator.result(doseMg: 6, vialMg: 5, waterMl: 2, syringe: .u100)
        XCTAssertTrue(r.warnings.contains(.doseExceedsVial))
    }

    func testZeroInput() {
        let r = ReconstitutionCalculator.result(doseMg: 0.25, vialMg: 0, waterMl: 0, syringe: .u100)
        XCTAssertTrue(r.warnings.contains(.zeroInput))
        XCTAssertEqual(r.roundedUnits, 0)
    }

    func testMcgConversion() {
        // 250 mcg = 0.25 mg → same as the worked example.
        let mg = DoseUnit.mcg.toMg(250)
        XCTAssertEqual(mg, 0.25)
        XCTAssertNil(DoseUnit.iu.toMg(2), "IU has no fixed mg ratio")
    }

    /// The calculator's mg ↔ IU toggle uses an HGH-class ~3 IU/mg approximation
    /// and round-trips losslessly.
    func testIUConversionRoundTrip() {
        XCTAssertEqual(ReconstitutionCalculator.mgFromIU(3), 1, accuracy: 1e-9)
        XCTAssertEqual(ReconstitutionCalculator.iuFromMg(1), 3, accuracy: 1e-9)
        let mg = 2.5
        XCTAssertEqual(ReconstitutionCalculator.mgFromIU(ReconstitutionCalculator.iuFromMg(mg)),
                       mg, accuracy: 1e-9)
    }
}
