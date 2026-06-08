import XCTest
@testable import Vita

final class StarterSuggesterTests: XCTestCase {

    func testEachGoalMapsToSlugs() {
        for g in GoalKind.allCases {
            XCTAssertFalse(StarterSuggester.slugs(for: [g]).isEmpty, "\(g) should map to ≥1 slug")
        }
    }

    func testFatLossSuggestsSemaglutide() {
        XCTAssertTrue(StarterSuggester.slugs(for: [.fatLoss]).contains("semaglutide"))
    }

    func testRecoverySuggestsHealingPeptides() {
        let s = StarterSuggester.slugs(for: [.recoveryHealing])
        XCTAssertTrue(s.contains("bpc-157"))
        XCTAssertTrue(s.contains("tb-500"))
    }

    func testDedupesAcrossGoals() {
        // recoveryHealing + muscleStrength shouldn't duplicate anything.
        let s = StarterSuggester.slugs(for: [.recoveryHealing, .muscleStrength])
        XCTAssertEqual(s.count, Set(s).count, "no duplicate slugs")
    }

    func testEmptyGoalsEmptyResult() {
        XCTAssertTrue(StarterSuggester.slugs(for: []).isEmpty)
    }
}
