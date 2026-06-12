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

    func testReAddRelinksDoseHistory() throws {
        let c = ctx()
        let svc = StackService(context: c)
        let first = svc.commit(baseDraft())!
        DoseLogger(context: c).log(item: first,
                                   occurrence: DoseOccurrence(itemID: first.id, minutes: 480),
                                   status: .taken)
        svc.remove(first)                                       // logs survive (denormalized)…
        let second = svc.commit(baseDraft())!                   // …and re-adding mints a new id
        XCTAssertNotEqual(first.id, second.id)
        let logs = try c.fetch(FetchDescriptor<DoseLog>())
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.itemID, second.id)           // history re-linked, not orphaned
        XCTAssertNotNil(DoseLogger(context: c).logged(itemID: second.id, minutes: 480))
    }

    // MARK: applyPlan (the onboarding refine merge — never delete-all/insert-all)

    func testApplyPlanUpdatesOverlapInPlace() {
        let svc = StackService(context: ctx())
        let starter = svc.commit(baseDraft())!
        let originalID = starter.id

        var refined = DoseDraft(compoundSlug: "bpc-157", displayName: "BPC-157")
        refined.doseUnit = .mcg; refined.doseAmount = 500
        refined.frequency = .daily; refined.times = [9 * 60, 21 * 60]
        svc.applyPlan([refined])

        let items = svc.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, originalID)               // same item, no delete/recreate
        XCTAssertEqual(items[0].doseAmount, 500)
        XCTAssertEqual(items[0].schedule?.timeSlotsMinutes, [540, 1260])
    }

    func testApplyPlanKeepsStaleAndAddsNew() {
        // ADDITIVE-ONLY: the background swap never deletes a row the user may be
        // looking at (device crash: deleted-model render trap). Stale items stay.
        let svc = StackService(context: ctx())
        let aID = svc.commit(baseDraft())!.id                 // bpc-157 (not in the refined plan)
        var b = DoseDraft(compoundSlug: "tb-500", displayName: "TB-500")
        b.doseUnit = .mg; b.doseAmount = 2
        b.frequency = .weekly; b.weekdays = [1]; b.times = [480]
        let bID = svc.commit(b)!.id

        var bRefined = b; bRefined.doseAmount = 2.5
        var c = DoseDraft(compoundSlug: "cjc-1295", displayName: "CJC-1295")
        c.doseUnit = .mcg; c.doseAmount = 100
        c.frequency = .daily; c.times = [21 * 60]
        svc.applyPlan([bRefined, c])

        XCTAssertEqual(Set(svc.items().map(\.compoundSlug)),
                       ["bpc-157", "tb-500", "cjc-1295"])     // nothing deleted, addition landed
        XCTAssertEqual(svc.item(forSlug: "bpc-157")?.id, aID) // stale item untouched
        XCTAssertEqual(svc.item(forSlug: "tb-500")?.id, bID)  // B kept its identity
        XCTAssertEqual(svc.item(forSlug: "tb-500")?.doseAmount, 2.5)
    }

    func testApplyPlanPreservesVialCycleTitration() {
        let svc = StackService(context: ctx())
        var d = baseDraft()
        d.hasVial = true; d.vialMg = 5; d.waterMl = 2
        d.cycleEnabled = true; d.cycleUnit = .weeks; d.cycleOnValue = 8; d.cycleOffValue = 4
        d.titrationEnabled = true
        d.titrationSteps = [TitrationStepDraft(weekN: 1, dose: 250)]
        let item = svc.commit(d)!

        // Claude's refined drafts never carry vials or advanced settings; the
        // merge must update the dose without wiping the user's setup.
        var refined = DoseDraft(compoundSlug: "bpc-157", displayName: "BPC-157")
        refined.doseUnit = .mcg; refined.doseAmount = 300
        refined.frequency = .daily; refined.times = [480]
        svc.applyPlan([refined])

        XCTAssertEqual(item.doseAmount, 300)                  // refined dose applied
        XCTAssertNotNil(item.vial)                            // vial survives
        XCTAssertTrue(item.schedule!.hasCycle)                // cycle survives
        XCTAssertTrue(item.schedule!.hasTitration)            // ladder survives
    }

    func testApplyPlanKeepsDoseLogLinkage() {
        let c = ctx()
        let svc = StackService(context: c)
        let item = svc.commit(baseDraft())!
        DoseLogger(context: c).log(item: item,
                                   occurrence: DoseOccurrence(itemID: item.id, minutes: 480),
                                   status: .taken)

        var refined = DoseDraft(compoundSlug: "bpc-157", displayName: "BPC-157")
        refined.doseUnit = .mcg; refined.doseAmount = 400
        refined.frequency = .daily; refined.times = [480]
        svc.applyPlan([refined])

        // Same item id → today's log still counts (adherence/streak intact).
        XCTAssertNotNil(DoseLogger(context: c).logged(itemID: item.id, minutes: 480))
    }

    // MARK: Provenance + protected merge (the always-refine rules)

    func testApplyPlanNeverTouchesUserItems() {
        let svc = StackService(context: ctx())
        // A user pick (aiGenerated == false by default).
        let user = svc.commit(baseDraft())!
        XCTAssertFalse(user.aiGenerated)
        // An AI-owned item.
        var ai = DoseDraft(compoundSlug: "tb-500", displayName: "TB-500")
        ai.aiGenerated = true; ai.doseUnit = .mg; ai.doseAmount = 2
        ai.frequency = .weekly; ai.weekdays = [1]; ai.times = [480]
        svc.commit(ai)

        // Claude's plan: a different take on the user's compound + drops tb-500 + adds cjc.
        var userAlt = baseDraft(); userAlt.aiGenerated = true; userAlt.doseAmount = 999
        var c = DoseDraft(compoundSlug: "cjc-1295", displayName: "CJC-1295")
        c.aiGenerated = true; c.doseUnit = .mcg; c.doseAmount = 100
        c.frequency = .daily; c.times = [1260]
        svc.applyPlan([userAlt, c], protecting: { !$0.aiGenerated })

        XCTAssertEqual(user.doseAmount, 250)                  // user's item untouched
        XCTAssertNotNil(svc.item(forSlug: "tb-500"))          // AI item NOT in plan: kept (additive-only)
        XCTAssertNotNil(svc.item(forSlug: "cjc-1295"))        // AI addition landed
        XCTAssertEqual(svc.items().count, 3)                  // colliding draft NOT added as a dupe
    }

    func testFingerprintTracksDoseAndScheduleEdits() {
        let svc = StackService(context: ctx())
        let item = svc.commit(baseDraft())!
        let before = StackService.fingerprint(svc.items())
        XCTAssertEqual(before, StackService.fingerprint(svc.items()))  // stable

        var edit = svc.draft(for: item)
        edit.doseAmount = 300                                  // a dose edit alone must change it
        svc.commit(edit)
        XCTAssertNotEqual(before, StackService.fingerprint(svc.items()))
    }

    func testSuggestsChangeThresholds() {
        var d = DoseDraft(compoundSlug: "bpc-157", displayName: "BPC-157")
        d.doseUnit = .mcg; d.doseAmount = 250; d.frequency = .daily; d.times = [480]

        // Identical → no suggestion.
        XCTAssertFalse(StackService.suggestsChange(dose: 250, unitRaw: "mcg", frequencyRaw: "daily",
                                                   times: [480], draft: d))
        // Dose within 15% → still quiet.
        XCTAssertFalse(StackService.suggestsChange(dose: 240, unitRaw: "mcg", frequencyRaw: "daily",
                                                   times: [480], draft: d))
        // Dose off by >15% → suggest.
        XCTAssertTrue(StackService.suggestsChange(dose: 500, unitRaw: "mcg", frequencyRaw: "daily",
                                                  times: [480], draft: d))
        // Different cadence → suggest.
        XCTAssertTrue(StackService.suggestsChange(dose: 250, unitRaw: "mcg", frequencyRaw: "weekly",
                                                  times: [480], draft: d))
        // Different times → suggest.
        XCTAssertTrue(StackService.suggestsChange(dose: 250, unitRaw: "mcg", frequencyRaw: "daily",
                                                  times: [540], draft: d))
    }

    func testSheetSaveClaimsAIItem() {
        let svc = StackService(context: ctx())
        var ai = baseDraft(); ai.aiGenerated = true
        let item = svc.commit(ai)!
        XCTAssertTrue(item.aiGenerated)

        // The dose sheet forces aiGenerated = false on save (user touch claims it).
        var edit = svc.draft(for: item)
        XCTAssertTrue(edit.aiGenerated)                        // round-trips provenance
        edit.aiGenerated = false
        svc.commit(edit)
        XCTAssertFalse(item.aiGenerated)
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
