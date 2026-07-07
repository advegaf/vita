import XCTest
import SwiftData
@testable import Vita

/// Pure vial-lifecycle math (M37). All derive-live: remaining is vial mg minus the
/// stamped dose of taken logs since reconstitution.
@MainActor
final class VialEngineTests: XCTestCase {

    private var container: ModelContainer!   // retained — a dropped in-memory container traps
    private func makeContext() -> ModelContext {
        container = VitaContainer.make(inMemory: true)
        return container.mainContext
    }

    private let cal = Calendar.current

    private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    @discardableResult
    private func makeItem(_ ctx: ModelContext, slug: String = "bpc-157",
                          dose: Double = 250, unit: String = "mcg") -> ProtocolItem {
        let item = ProtocolItem()
        item.compoundSlug = slug
        item.displayName = slug.uppercased()
        item.doseAmount = dose
        item.doseUnitRaw = unit
        ctx.insert(item)
        return item
    }

    private func dailyRule(_ ctx: ModelContext, _ item: ProtocolItem, slots: [Int] = [480]) {
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.daily.rawValue
        r.timeSlotsMinutes = slots
        r.item = item
        ctx.insert(r)
        item.schedule = r
    }

    private func makeVial(_ ctx: ModelContext, _ item: ProtocolItem, mg: Double = 5,
                          water: Double = 2, recon: Date, budDays: Int = 28) -> Vial {
        let v = Vial()
        v.compoundSlug = item.compoundSlug
        v.vialMg = mg
        v.waterMl = water
        v.concentrationMgPerMl = ReconstitutionCalculator.concentration(vialMg: mg, waterMl: water)
        v.reconstitutedAt = recon
        v.budDays = budDays
        v.item = item
        ctx.insert(v)
        item.vial = v
        return v
    }

    @discardableResult
    private func log(_ ctx: ModelContext, _ item: ProtocolItem, at when: Date,
                     dose: Double, unit: String = "mcg", status: DoseStatus = .taken,
                     slug: String? = nil, minutes: Int = 480) -> DoseLog {
        let l = DoseLog()
        l.itemID = item.id
        l.compoundSlug = slug ?? item.compoundSlug
        l.doseAmount = dose
        l.doseUnitRaw = unit
        l.statusRaw = status.rawValue
        l.loggedAt = when
        l.scheduledDayStart = cal.startOfDay(for: when)   // well-formed scheduled log
        l.scheduledMinutes = minutes
        ctx.insert(l)
        return l
    }

    // MARK: - doseMg

    func testDoseMgConversions() {
        XCTAssertEqual(VialEngine.doseMg(250, unit: .mcg)!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(VialEngine.doseMg(2, unit: .mg)!, 2, accuracy: 1e-9)
        // IU with default HGH-class approximation (3 IU/mg).
        XCTAssertEqual(VialEngine.doseMg(6, unit: .iu)!, 2, accuracy: 1e-9)
        // IU with a per-compound override.
        XCTAssertEqual(VialEngine.doseMg(6, unit: .iu, iuPerMg: 2)!, 3, accuracy: 1e-9)
        XCTAssertNil(VialEngine.doseMg(0, unit: .mg))
        XCTAssertNil(VialEngine.doseMg(-5, unit: .mcg))
    }

    // MARK: - consumedMg filtering

    func testConsumedMgFiltersTakenSlugAndSince() {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let recon = day(2026, 7, 1)
        // taken after recon counts
        log(ctx, item, at: day(2026, 7, 2), dose: 250)
        log(ctx, item, at: day(2026, 7, 3), dose: 250)
        // skipped ignored
        log(ctx, item, at: day(2026, 7, 4), dose: 250, status: .skipped)
        // before recon ignored
        log(ctx, item, at: day(2026, 6, 30), dose: 250)
        // other slug ignored
        log(ctx, item, at: day(2026, 7, 5), dose: 250, slug: "tb-500")
        // legacy (no unit) contributes 0
        let legacy = log(ctx, item, at: day(2026, 7, 6), dose: 0); legacy.doseUnitRaw = ""

        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let consumed = VialEngine.consumedMg(logs: logs, slug: "bpc-157", since: recon)
        XCTAssertEqual(consumed, 0.5, accuracy: 1e-9)   // only the two valid taken logs
    }

    func testLegacyVialDetection() {
        let ctx = makeContext()
        let item = makeItem(ctx)
        let recon = day(2026, 7, 1)
        let legacy = log(ctx, item, at: day(2026, 7, 2), dose: 0); legacy.doseUnitRaw = ""
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        XCTAssertTrue(VialEngine.isLegacyVial(logs: logs, slug: "bpc-157", since: recon))
    }

    // MARK: - dosesRemaining boundaries

    func testDosesRemainingBoundaries() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)                 // 0.25 mg
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 5, recon: recon) // 20 doses
        // Consume 17 doses → 0.75 mg left → 3 doses, isLow.
        for i in 0..<17 { log(ctx, item, at: day(2026, 7, 1, 9).addingTimeInterval(Double(i)), dose: 250) }
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 2, 0, 1))
        XCTAssertEqual(s.dosesRemaining, 3)
        XCTAssertFalse(s.hasFractionalLastDose)
        XCTAssertTrue(s.isLow)
        XCTAssertEqual(s.remainingMg, 0.75, accuracy: 1e-9)
    }

    func testExactFitAndFractionalLastDose() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item)
        // Vial 0.30 mg: one full 0.25 dose + a 0.05 remainder.
        let vial = makeVial(ctx, item, mg: 0.30, recon: recon)
        var logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        var s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        XCTAssertEqual(s.dosesRemaining, 1)
        // Take the full dose → 0.05 mg left → fractional, "less than 1 dose".
        log(ctx, item, at: day(2026, 7, 1, 9), dose: 250)
        logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 12))
        XCTAssertEqual(s.dosesRemaining, 0)
        XCTAssertTrue(s.hasFractionalLastDose)
        XCTAssertEqual(VialEngine.supplyLine(s), "Less than 1 dose left")
    }

    func testOverdrawnClamps() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 1, recon: recon)   // 4 doses
        for i in 0..<5 { log(ctx, item, at: day(2026, 7, 1, 9).addingTimeInterval(Double(i)), dose: 250) }
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 2))
        XCTAssertTrue(s.isOverdrawn)
        XCTAssertEqual(s.remainingMg, 0)
        XCTAssertEqual(s.fractionRemaining, 0)
        XCTAssertEqual(VialEngine.supplyLine(s), "Supply tracking may be off. Start a new vial to resync.")
    }

    // MARK: - run-out walk

    func testRunOutDaily() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 5, recon: recon)   // 20 doses
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let now = day(2026, 7, 1, 0, 1)
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: now)
        // 20 doses cover offsets 0..19; the 21st (offset 20) can't be covered.
        XCTAssertEqual(s.runOutDate.map { cal.startOfDay(for: $0) }, day(2026, 7, 21))
    }

    func testRunOutStartsTodaySkippingTakenSlot() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 5, recon: recon)
        // Today's 8:00 slot already taken → remaining 4.75 (19 doses), not double-counted.
        log(ctx, item, at: day(2026, 7, 1, 8), dose: 250)
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let now = day(2026, 7, 1, 9)   // after the 8:00 slot
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: now)
        XCTAssertEqual(s.dosesRemaining, 19)
        XCTAssertEqual(s.runOutDate.map { cal.startOfDay(for: $0) }, day(2026, 7, 21))
    }

    func testRunOutTwoSlotsPerDay() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        dailyRule(ctx, item, slots: [480, 1260])   // twice daily → burns 2x
        let vial = makeVial(ctx, item, mg: 5, recon: recon)   // 20 doses → 10 days
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        XCTAssertEqual(s.runOutDate.map { cal.startOfDay(for: $0) }, day(2026, 7, 11))
    }

    func testRunOutEODParity() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let recon = day(2026, 7, 1)
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.eod.rawValue
        r.timeSlotsMinutes = [480]
        r.anchorDate = day(2026, 7, 1)
        r.item = item; ctx.insert(r); item.schedule = r
        let vial = makeVial(ctx, item, mg: 1, recon: recon)   // 4 doses
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        // Due on offsets 0,2,4,6; the 5th dose falls on offset 8.
        XCTAssertEqual(s.runOutDate.map { cal.startOfDay(for: $0) }, day(2026, 7, 9))
    }

    func testRunOutTitrationShortens() {
        let ctx = makeContext()
        let recon = day(2026, 7, 1)
        // Flat 0.25 daily, 5 mg → 20 days.
        let flat = makeItem(ctx, slug: "flat", dose: 250)
        dailyRule(ctx, flat)
        let flatVial = makeVial(ctx, flat, mg: 5, recon: recon)
        // Titrated: 0.25 then 0.5 at day 7 → burns faster.
        let titr = makeItem(ctx, slug: "titr", dose: 250)
        let tr = ScheduleRule()
        tr.frequencyRaw = Frequency.daily.rawValue
        tr.timeSlotsMinutes = [480]
        tr.anchorDate = day(2026, 7, 1)
        tr.titrationDayStarts = [0, 7]
        tr.titrationDoses = [250, 500]
        tr.item = titr; ctx.insert(tr); titr.schedule = tr
        let titrVial = makeVial(ctx, titr, mg: 5, recon: recon)

        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let now = day(2026, 7, 1, 0, 1)
        let flatOut = VialEngine.status(item: flat, vial: flatVial, logs: logs, asOf: now).runOutDate!
        let titrOut = VialEngine.status(item: titr, vial: titrVial, logs: logs, asOf: now).runOutDate!
        XCTAssertLessThan(titrOut, flatOut)   // stepping up shortens the run
    }

    func testRunOutCycleOffExtends() {
        let ctx = makeContext()
        let recon = day(2026, 7, 1)
        let cont = makeItem(ctx, slug: "cont", dose: 250)
        dailyRule(ctx, cont)
        let contVial = makeVial(ctx, cont, mg: 2, recon: recon)
        let cyc = makeItem(ctx, slug: "cyc", dose: 250)
        let cr = ScheduleRule()
        cr.frequencyRaw = Frequency.daily.rawValue
        cr.timeSlotsMinutes = [480]
        cr.anchorDate = day(2026, 7, 1)
        cr.cycleOnDays = 5; cr.cycleOffDays = 5   // rests half the time
        cr.item = cyc; ctx.insert(cr); cyc.schedule = cr
        let cycVial = makeVial(ctx, cyc, mg: 2, recon: recon)

        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let now = day(2026, 7, 1, 0, 1)
        let contOut = VialEngine.status(item: cont, vial: contVial, logs: logs, asOf: now).runOutDate!
        let cycOut = VialEngine.status(item: cyc, vial: cycVial, logs: logs, asOf: now).runOutDate!
        XCTAssertGreaterThan(cycOut, contOut)   // off-days stretch the supply
    }

    func testRunOutPRNIsNil() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.prn.rawValue
        r.item = item; ctx.insert(r); item.schedule = r
        let vial = makeVial(ctx, item, mg: 5, recon: day(2026, 7, 1))
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        XCTAssertNil(s.runOutDate)
        XCTAssertEqual(s.dosesRemaining, 20)   // still counts at current dose
    }

    func testRunOutHorizonCapReturnsNil() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)     // 0.25 mg
        let r = ScheduleRule()
        r.frequencyRaw = Frequency.weekly.rawValue
        r.timeSlotsMinutes = [480]
        r.weekdays = [cal.component(.weekday, from: day(2026, 7, 6))]   // once a week
        r.item = item; ctx.insert(r); item.schedule = r
        // 100 mg at 0.25/week is ~400 weeks — far past the 365-day horizon.
        let vial = makeVial(ctx, item, mg: 100, recon: day(2026, 7, 1))
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 6, 0, 1))
        XCTAssertNil(s.runOutDate)
    }

    // MARK: - BUD

    func testBUDBoundary() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        dailyRule(ctx, item)
        let recon = day(2026, 7, 1)
        let vial = makeVial(ctx, item, mg: 5, recon: recon, budDays: 28)
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())

        let s27 = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 28, 12))
        XCTAssertEqual(s27.daysSinceRecon, 27)
        XCTAssertFalse(s27.isPastBUD)
        XCTAssertEqual(VialEngine.budLine(s27), "Day 27 of 28 since reconstitution")

        let s28 = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 29, 12))
        XCTAssertEqual(s28.daysSinceRecon, 28)
        XCTAssertTrue(s28.isPastBUD)   // day 28 exactly is past the mark
    }

    // MARK: - copy builders

    func testSupplyAndRunOutLines() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 5, recon: day(2026, 7, 1))
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        XCTAssertEqual(VialEngine.supplyLine(s), "20 doses left")
        XCTAssertEqual(VialEngine.runOutLine(s), "Runs out around Jul 21")
    }

    func testSingularDoseCopy() {
        let ctx = makeContext()
        let item = makeItem(ctx, dose: 250)
        dailyRule(ctx, item)
        let vial = makeVial(ctx, item, mg: 0.25, recon: day(2026, 7, 1))
        let logs = try! ctx.fetch(FetchDescriptor<DoseLog>())
        let s = VialEngine.status(item: item, vial: vial, logs: logs, asOf: day(2026, 7, 1, 0, 1))
        XCTAssertEqual(s.dosesRemaining, 1)
        XCTAssertEqual(VialEngine.supplyLine(s), "1 dose left")   // singular
    }
}
