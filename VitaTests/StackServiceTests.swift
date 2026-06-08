import XCTest
import SwiftData
@testable import Vita

@MainActor
final class StackServiceTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps on use
    private func ctx() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private func baseDraft() -> DoseDraft {
        var d = DoseDraft(compoundSlug: "bpc-157", displayName: "BPC-157")
        d.doseUnit = .mcg; d.doseAmount = 250
        d.frequency = .daily; d.times = [8 * 60]
        return d
    }

    func testCommitCycleTitrationRoundTrip() {
        let svc = StackService(context: ctx())
        var d = baseDraft()
        d.protocolStart = Date(timeIntervalSince1970: 1_700_000_000)
        d.cycleEnabled = true; d.cycleUnit = .weeks; d.cycleOnValue = 8; d.cycleOffValue = 4
        d.titrationEnabled = true
        d.titrationSteps = [TitrationStepDraft(weekN: 1, dose: 0.25),
                            TitrationStepDraft(weekN: 5, dose: 0.5)]

        let item = svc.commit(d)!
        let rule = item.schedule!
        XCTAssertTrue(rule.hasCycle)
        XCTAssertEqual(rule.cycleOnDays, 56)
        XCTAssertEqual(rule.cycleOffDays, 28)
        XCTAssertEqual(rule.cycleUnit, .weeks)
        XCTAssertTrue(rule.hasTitration)
        XCTAssertEqual(rule.titrationDayStarts, [0, 28])
        XCTAssertEqual(rule.titrationDoses, [0.25, 0.5])
        XCTAssertEqual(rule.anchorDate.timeIntervalSince1970, d.protocolStart.timeIntervalSince1970, accuracy: 1)

        // Round-trip back into a draft for editing.
        let d2 = svc.draft(for: item)
        XCTAssertTrue(d2.cycleEnabled)
        XCTAssertEqual(d2.cycleOnValue, 8)
        XCTAssertEqual(d2.cycleOffValue, 4)
        XCTAssertEqual(d2.cycleUnit, .weeks)
        XCTAssertEqual(d2.titrationSteps.map(\.weekN), [1, 5])
        XCTAssertEqual(d2.titrationSteps.map(\.dose), [0.25, 0.5])
    }

    func testToggleOffClearsCycleTitration() {
        let svc = StackService(context: ctx())
        var d = baseDraft()
        d.cycleEnabled = true; d.cycleUnit = .weeks; d.cycleOnValue = 8; d.cycleOffValue = 4
        d.titrationEnabled = true
        d.titrationSteps = [TitrationStepDraft(weekN: 1, dose: 0.25)]
        let item = svc.commit(d)!
        XCTAssertTrue(item.schedule!.hasCycle)
        XCTAssertTrue(item.schedule!.hasTitration)

        // Edit the same item: turn both advanced features off.
        var edit = svc.draft(for: item)
        edit.cycleEnabled = false
        edit.titrationEnabled = false
        let item2 = svc.commit(edit)!
        XCTAssertFalse(item2.schedule!.hasCycle)
        XCTAssertEqual(item2.schedule!.cycleOnDays, 0)
        XCTAssertEqual(item2.schedule!.cycleOffDays, 0)
        XCTAssertFalse(item2.schedule!.hasTitration)
        XCTAssertTrue(item2.schedule!.titrationDayStarts.isEmpty)
        XCTAssertTrue(item2.schedule!.titrationDoses.isEmpty)
    }
}
