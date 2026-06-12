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
}
