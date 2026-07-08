import XCTest
@testable import Vita

final class DoseFormatTests: XCTestCase {

    func testDoseOnlyWhenNoDraw() {
        XCTAssertEqual(DoseFormat.doseWithDraw(dose: "250 mcg", drawUnits: nil), "250 mcg")
        XCTAssertEqual(DoseFormat.doseWithDraw(dose: "0.5 mg", drawUnits: 0), "0.5 mg")
    }

    func testDoseWithDrawUsesBulletAndUnits() {
        // Dose stays in its authored unit (no mcg -> mg); units appended after a bullet.
        XCTAssertEqual(DoseFormat.doseWithDraw(dose: "250 mcg", drawUnits: 10), "250 mcg • 10u")
        XCTAssertEqual(DoseFormat.doseWithDraw(dose: "0.5 mg", drawUnits: 20), "0.5 mg • 20u")
        XCTAssertEqual(DoseFormat.doseWithDraw(dose: "4 IU", drawUnits: 7.5), "4 IU • 7.5u")
    }

    /// The separator must be the bullet U+2022 (which CopyGuard allows), NOT the
    /// spaced middle dot U+00B7 (which CopyGuard bans) — guards against a silent swap.
    func testSeparatorIsBulletNotMiddleDot() {
        let s = DoseFormat.doseWithDraw(dose: "250 mcg", drawUnits: 10)
        XCTAssertTrue(s.unicodeScalars.contains(Unicode.Scalar(0x2022)!))   // •
        XCTAssertFalse(s.unicodeScalars.contains(Unicode.Scalar(0x00B7)!))  // ·
    }
}
