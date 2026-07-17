import XCTest
@testable import Vita

final class UnitsTests: XCTestCase {

    func testKgLbRoundTrip() {
        XCTAssertEqual(Units.kgToLb(100), 220.462, accuracy: 0.01)
        XCTAssertEqual(Units.lbToKg(Units.kgToLb(78)), 78, accuracy: 1e-9)
    }

    func testCmToFeetInches() {
        let a = Units.cmToFeetInches(180)        // ≈ 5 ft 11 in
        XCTAssertEqual(a.feet, 5); XCTAssertEqual(a.inches, 11)
        let b = Units.cmToFeetInches(152.4)      // exactly 5 ft 0 in
        XCTAssertEqual(b.feet, 5); XCTAssertEqual(b.inches, 0)
    }

    func testFeetInchesRoundsToFullFoot() {
        // 182.7 cm rounds to 72 inches = 6 ft 0 in (not 5 ft 12 in)
        let r = Units.cmToFeetInches(182.7)
        XCTAssertEqual(r.feet, 6); XCTAssertEqual(r.inches, 0)
    }

    func testFeetInchesToCmRoundTrip() {
        XCTAssertEqual(Units.feetInchesToCm(feet: 5, inches: 11), 180.34, accuracy: 1e-9)
        let cm = 175.0
        let fi = Units.cmToFeetInches(cm)
        XCTAssertEqual(Units.feetInchesToCm(feet: fi.feet, inches: fi.inches), cm, accuracy: 1.5)
    }

    func testCmInchRoundTrip() {
        XCTAssertEqual(Units.cmToInches(80), 31.496, accuracy: 0.001)
        XCTAssertEqual(Units.inchesToCm(Units.cmToInches(80)), 80, accuracy: 1e-9)
        XCTAssertEqual(Units.inchesToCm(1), 2.54, accuracy: 1e-9)
    }

    func testTrim() {
        XCTAssertEqual(Units.trim(78), "78")
        XCTAssertEqual(Units.trim(172.4), "172.4")
    }

    func testParseDoubleAcceptsCommaDecimals() {
        XCTAssertEqual(Units.parseDouble("82.5"), 82.5)
        XCTAssertEqual(Units.parseDouble("82,5"), 82.5)   // comma-decimal keyboards
        XCTAssertNil(Units.parseDouble("abc"))
        XCTAssertNil(Units.parseDouble(""))
    }

    // MARK: - Range-aware dose steps (M50)

    func testDoseStepScalesWithRange() {
        // The user's rule: a 200-600 mcg range steps by 50.
        XCTAssertEqual(Units.doseStep(lo: 200, hi: 600, unit: .mcg), 50)
        XCTAssertEqual(Units.doseStep(lo: 250, hi: 500, unit: .mcg), 25)
        XCTAssertEqual(Units.doseStep(lo: 1000, hi: 3000, unit: .mcg), 250)
        XCTAssertEqual(Units.doseStep(lo: 0.25, hi: 1.0, unit: .mg), 0.05, accuracy: 1e-9)
        XCTAssertEqual(Units.doseStep(lo: 5, hi: 15, unit: .mg), 1)
        XCTAssertEqual(Units.doseStep(lo: 2, hi: 6, unit: .iu), 0.5, accuracy: 1e-9)
    }

    func testDoseStepFloorsAndFallbacks() {
        // Narrow ranges never go below the per-unit floor.
        XCTAssertEqual(Units.doseStep(lo: 100, hi: 110, unit: .mcg), 5)
        XCTAssertEqual(Units.doseStep(lo: 0.5, hi: 0.6, unit: .mg), 0.05, accuracy: 1e-9)
        // No range (custom compounds) keeps the original defaults.
        XCTAssertEqual(Units.doseStep(lo: nil, hi: nil, unit: .mcg), 50)
        XCTAssertEqual(Units.doseStep(lo: nil, hi: 500, unit: .mcg), 50)
        XCTAssertEqual(Units.doseStep(lo: nil, hi: nil, unit: .mg), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Units.doseStep(lo: nil, hi: nil, unit: .iu), 0.5, accuracy: 1e-9)
        // Degenerate range behaves like no range.
        XCTAssertEqual(Units.doseStep(lo: 500, hi: 500, unit: .mcg), 50)
    }

    func testNiceStepSnapsTo1_2p5_5() {
        XCTAssertEqual(Units.niceStep(50), 50)
        XCTAssertEqual(Units.niceStep(31.25), 25)
        XCTAssertEqual(Units.niceStep(7), 5)
        XCTAssertEqual(Units.niceStep(2.4), 1)
        XCTAssertEqual(Units.niceStep(0.09), 0.05, accuracy: 1e-9)
        XCTAssertEqual(Units.niceStep(0), 1, "degenerate input stays sane")
    }
}
