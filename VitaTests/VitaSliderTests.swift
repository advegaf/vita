import XCTest
import CoreGraphics
@testable import Vita

/// Pure mapping/snapping math for the signature slider — no UI.
final class VitaSliderTests: XCTestCase {

    private let range = 1...10
    private let kr: CGFloat = 18   // knobRadius (knobGrab/2 = 36/2)
    private let w: CGFloat = 318

    func testEndsMapToBounds() {
        XCTAssertEqual(VitaSliderMath.value(forDragX: kr, width: w, knobRadius: kr, range: range), 1)
        XCTAssertEqual(VitaSliderMath.value(forDragX: w - kr, width: w, knobRadius: kr, range: range), 10)
        // Beyond the ends clamps.
        XCTAssertEqual(VitaSliderMath.value(forDragX: -50, width: w, knobRadius: kr, range: range), 1)
        XCTAssertEqual(VitaSliderMath.value(forDragX: w + 50, width: w, knobRadius: kr, range: range), 10)
    }

    func testMidpointIsMiddleDetent() {
        // Fraction 0.5 → 1 + round(0.5*9) = 1 + round(4.5) = 1 + 5 = 6 (round half away from zero).
        let mid = kr + (w - 2 * kr) * 0.5
        XCTAssertEqual(VitaSliderMath.value(forDragX: mid, width: w, knobRadius: kr, range: range), 6)
    }

    func testNearestDetentRounds() {
        // ~30% past detent 6 toward 7 stays 6; ~60% flips to 7.
        let usable = w - 2 * kr
        let frac6 = VitaSliderMath.position(forValue: 6, range: range)   // 5/9
        let step = 1.0 / 9.0
        let x30 = kr + (frac6 + step * 0.30) * usable
        let x60 = kr + (frac6 + step * 0.60) * usable
        XCTAssertEqual(VitaSliderMath.nearestDetent(forDragX: x30, width: w, knobRadius: kr, range: range), 6)
        XCTAssertEqual(VitaSliderMath.nearestDetent(forDragX: x60, width: w, knobRadius: kr, range: range), 7)
    }

    func testCenterXReachesEndsWithoutClip() {
        XCTAssertEqual(VitaSliderMath.centerX(forValue: 1, width: w, knobRadius: kr, range: range), kr, accuracy: 1e-6)
        XCTAssertEqual(VitaSliderMath.centerX(forValue: 10, width: w, knobRadius: kr, range: range), w - kr, accuracy: 1e-6)
    }

    func testPositionClampsOutOfRange() {
        XCTAssertEqual(VitaSliderMath.position(forValue: 0, range: range), 0, accuracy: 1e-9)
        XCTAssertEqual(VitaSliderMath.position(forValue: 99, range: range), 1, accuracy: 1e-9)
    }

    func testBubbleClampStaysInBounds() {
        let bw: CGFloat = 40, lane: CGFloat = 300
        XCTAssertEqual(VitaSliderMath.clampedBubbleX(center: 0, bubbleWidth: bw, laneWidth: lane), bw / 2, accuracy: 1e-6)
        XCTAssertEqual(VitaSliderMath.clampedBubbleX(center: lane, bubbleWidth: bw, laneWidth: lane), lane - bw / 2, accuracy: 1e-6)
        XCTAssertEqual(VitaSliderMath.clampedBubbleX(center: 150, bubbleWidth: bw, laneWidth: lane), 150, accuracy: 1e-6)
    }

    func testDegenerateWidthDoesNotCrash() {
        XCTAssertEqual(VitaSliderMath.fraction(forDragX: 10, width: 0, knobRadius: kr), 0)
        XCTAssertEqual(VitaSliderMath.value(forDragX: 10, width: 0, knobRadius: kr, range: range), 1)
    }
}
