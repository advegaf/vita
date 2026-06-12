import XCTest
@testable import Vita

@MainActor
final class OnboardingModelTests: XCTestCase {

    func testBackFromReviewSkipsGenerating() {
        let m = OnboardingModel()
        m.step = .review
        m.back()
        XCTAssertEqual(m.step, .health)   // never lands on the auto-advancing Generating step
    }

    func testBackPopsPeptidesDetailFirst() {
        let m = OnboardingModel()
        m.step = .peptides
        m.peptidesPath = ["bpc-157"]
        m.back()
        XCTAssertEqual(m.step, .peptides) // first back closes the pushed detail…
        XCTAssertTrue(m.peptidesPath.isEmpty)
        m.back()
        XCTAssertEqual(m.step, .goals)    // …then leaves the step
    }

    func testAdvanceStopsAtLastStep() {
        let m = OnboardingModel()
        m.step = .notifications
        m.advance()                        // double-tap on the last step is a no-op
        XCTAssertEqual(m.step, .notifications)
    }
}
