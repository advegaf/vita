import XCTest
@testable import Vita

final class HealthScoreTests: XCTestCase {

    func testClassifyCentralOptimalEdgeNormalOutside() {
        // Range 40-60: central 60% = 44...56.
        XCTAssertEqual(HealthScore.classify(value: 50, refLow: 40, refHigh: 60), .optimal)
        XCTAssertEqual(HealthScore.classify(value: 41, refLow: 40, refHigh: 60), .normal)
        XCTAssertEqual(HealthScore.classify(value: 59, refLow: 40, refHigh: 60), .normal)
        XCTAssertEqual(HealthScore.classify(value: 39, refLow: 40, refHigh: 60), .outOfRange)
        XCTAssertEqual(HealthScore.classify(value: 61, refLow: 40, refHigh: 60), .outOfRange)
    }

    func testClassifyOneSidedAndDegenerate() {
        XCTAssertEqual(HealthScore.classify(value: 5, refLow: 1, refHigh: nil), .normal)
        XCTAssertEqual(HealthScore.classify(value: 0.5, refLow: 1, refHigh: nil), .outOfRange)
        XCTAssertEqual(HealthScore.classify(value: 3, refLow: nil, refHigh: 5), .normal)
        XCTAssertEqual(HealthScore.classify(value: 7, refLow: nil, refHigh: 5), .outOfRange)
        XCTAssertNil(HealthScore.classify(value: nil, refLow: 1, refHigh: 5))
        XCTAssertNil(HealthScore.classify(value: 3, refLow: nil, refHigh: nil))
    }

    func testComputeBlendsLabsAndAdherence() {
        // 2 optimal + 1 normal + 1 out = (2*1 + 1*0.6)/4 = 0.65 -> 45.5 lab points;
        // adherence 9/10 = 0.9 -> 27 points; total 72.5 -> 73.
        let r = HealthScore.compute(statuses: [.optimal, .optimal, .normal, .outOfRange],
                                    adherenceLogged: 9, adherenceScheduled: 10)
        XCTAssertEqual(r.score, 73)
        XCTAssertEqual(r.optimal, 2); XCTAssertEqual(r.normal, 1); XCTAssertEqual(r.outOfRange, 1)
        XCTAssertTrue(r.hasLabs)
    }

    func testComputeWithoutLabsIsAdherenceOnly() {
        let r = HealthScore.compute(statuses: [], adherenceLogged: 8, adherenceScheduled: 10)
        XCTAssertEqual(r.score, 80)
        XCTAssertFalse(r.hasLabs)
        // Nothing scheduled = full adherence credit.
        XCTAssertEqual(HealthScore.compute(statuses: [], adherenceLogged: 0,
                                           adherenceScheduled: 0).score, 100)
    }
}
