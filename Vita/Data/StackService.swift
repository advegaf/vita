import Foundation
import SwiftData

/// The single write path for the stack (add / remove / dedupe / dose+schedule edit).
@MainActor
struct StackService {
    let context: ModelContext

    func activePlan() -> ProtocolPlan {
        let plans = (try? context.fetch(FetchDescriptor<ProtocolPlan>())) ?? []
        if let p = plans.first(where: { $0.isActive }) ?? plans.first { return p }
        let p = ProtocolPlan()
        p.isActive = true
        let settings = CatalogStore.fetchOrCreateSettings(context)
        p.owner = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        context.insert(p)
        return p
    }

    func items() -> [ProtocolItem] {
        let d = FetchDescriptor<ProtocolItem>(
            sortBy: [SortDescriptor(\.sortIndex), SortDescriptor(\.addedAt)]
        )
        return (try? context.fetch(d)) ?? []
    }

    func isInStack(_ slug: String) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        return all.contains { $0.compoundSlug == slug }
    }

    func item(forSlug slug: String) -> ProtocolItem? {
        ((try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? [])
            .first { $0.compoundSlug == slug }
    }

    /// Builds an in-memory draft from a compound's seed (NOT inserted). The setup
    /// sheet edits it, then `commit` persists.
    func draft(for c: CatalogCompound) -> DoseDraft {
        var d = DoseDraft(compoundSlug: c.slug, displayName: c.name)
        d.categoryRaw = c.categoryRaw
        d.rxStatusRaw = c.rxStatusRaw
        d.routeRaw = c.primaryRoute?.rawValue ?? ""
        d.doseUnit = c.doseUnit
        d.doseAmount = seedDose(c)
        d.frequency = (c.defaultScheduleType == .asNeeded) ? .prn : .daily
        d.blocks = (c.defaultScheduleType == .asNeeded) ? [] : [.morning]
        return d
    }

    /// Loads an existing item back into a draft for editing.
    func draft(for item: ProtocolItem) -> DoseDraft {
        var d = DoseDraft(compoundSlug: item.compoundSlug, displayName: item.displayName)
        d.editingItemID = item.id
        d.aiGenerated = item.aiGenerated
        d.categoryRaw = item.categoryRaw
        d.rxStatusRaw = item.rxStatusRaw
        d.routeRaw = item.routeRaw
        d.doseUnit = item.doseUnit
        d.doseAmount = item.doseAmount
        if let r = item.schedule {
            d.frequency = r.frequency
            d.weekdays = Set(r.weekdays)
            d.times = r.timeSlotsMinutes.sorted()
            d.protocolStart = r.anchorDate
            d.cycleUnit = r.cycleUnit
            d.cycleEnabled = r.hasCycle
            d.cycleOnValue  = r.cycleUnit == .weeks ? r.cycleOnDays  / 7 : r.cycleOnDays
            d.cycleOffValue = r.cycleUnit == .weeks ? r.cycleOffDays / 7 : r.cycleOffDays
            d.titrationEnabled = r.hasTitration
            d.titrationSteps = r.titrationSteps.map { TitrationStepDraft(weekN: $0.dayStart / 7 + 1, dose: $0.dose) }
        }
        if let v = item.vial {
            d.hasVial = true; d.hasExistingVial = true
            d.vialMg = v.vialMg; d.waterMl = v.waterMl; d.syringe = v.syringe; d.budDays = v.budDays
        }
        return d
    }

    /// Persists a draft as a new item or updates the one being edited. Dedupe on add.
    /// `rebuild: false` defers the notification/widget side effects (batch callers
    /// like `applyPlan` run them once at the end).
    @discardableResult
    func commit(_ d: DoseDraft, rebuild: Bool = true) -> ProtocolItem? {
        let item: ProtocolItem
        if let id = d.editingItemID, let existing = items().first(where: { $0.id == id }) {
            item = existing
        } else {
            guard !isInStack(d.compoundSlug) else { return nil } // one per compound
            item = ProtocolItem()
            item.compoundSlug = d.compoundSlug
            item.displayName = d.displayName
            item.categoryRaw = d.categoryRaw
            item.rxStatusRaw = d.rxStatusRaw
            item.sortIndex = items().count
            item.plan = activePlan()
            context.insert(item)
            // Re-adding a compound mints a new id, which would orphan its old logs
            // (denormalized by design). Re-link them so adherence, streaks, and
            // "logged Nh ago" survive a remove → re-add round trip. In this branch
            // no live item has the slug, so every matching log is an orphan.
            let orphans = ((try? context.fetch(FetchDescriptor<DoseLog>())) ?? [])
                .filter { $0.compoundSlug == d.compoundSlug }
            for log in orphans { log.itemID = item.id }
        }
        item.doseUnitRaw = d.doseUnit.rawValue
        item.doseAmount = max(0, d.doseAmount)
        item.aiGenerated = d.aiGenerated
        if !d.routeRaw.isEmpty { item.routeRaw = d.routeRaw }
        item.kindRaw = (d.frequency == .prn) ? "prn" : "scheduled"

        let rule = item.schedule ?? {
            let r = ScheduleRule(); item.schedule = r; return r
        }()
        rule.frequencyRaw = d.frequency.rawValue
        rule.weekdays = Array(d.weekdays).sorted()
        rule.timeSlotsMinutes = (d.frequency == .prn) ? [] : d.times.sorted()
        rule.scheduleTypeRaw = scheduleType(for: d.frequency).rawValue
        rule.cadenceLabel = ScheduleService.cadenceLabel(for: rule)
        item.cadenceLabel = rule.cadenceLabel

        // Advanced: protocol-start anchor + cycle envelope + titration ladder (M9).
        rule.anchorDate = d.protocolStart
        rule.cycleUnitRaw = d.cycleUnit.rawValue
        rule.cycleOnDays = d.hasCycle ? d.cycleOnDays : 0
        rule.cycleOffDays = d.hasCycle ? d.cycleOffDays : 0
        let tsteps = d.hasTitration ? d.titrationSteps.sorted { $0.weekN < $1.weekN } : []
        rule.titrationDayStarts = tsteps.map { ($0.weekN - 1) * 7 }
        rule.titrationDoses = tsteps.map { $0.dose }

        // Vial (create / update / clear). A NEW vial takes its default
        // `reconstitutedAt = now`; editing an existing vial NEVER resets it (that's
        // what `startNewVial` is for), so derived supply stays truthful. Size changes
        // on an existing vial are routed through `startNewVial` by the setup sheet,
        // so `d.vialMg` here only creates or corrects water/syringe/BUD in place.
        if d.hasVial, d.vialMg > 0, d.waterMl > 0 {
            let v: Vial
            if let existing = item.vial { v = existing }
            else { let nv = Vial(); context.insert(nv); nv.item = item; item.vial = nv; v = nv }
            v.compoundSlug = d.compoundSlug
            v.vialMg = d.vialMg
            v.waterMl = d.waterMl
            v.syringeRaw = d.syringe.rawValue
            v.budDays = d.budDays
            v.concentrationMgPerMl = ReconstitutionCalculator.concentration(vialMg: d.vialMg, waterMl: d.waterMl)
        } else if let v = item.vial {
            context.delete(v); item.vial = nil
        }

        context.saveLogged("StackService")
        if rebuild {
            NotificationManager.rebuild(context: context)
            WidgetBridge.update(context: context)
        }
        return item
    }

    /// Replaces the active vial's contents with a freshly reconstituted one: same
    /// `Vial` row, new size/water/syringe/BUD, and `reconstitutedAt` reset to now so
    /// derived consumption restarts from zero. This is the ONLY path that resets the
    /// supply clock (editing via the setup sheet never does).
    func startNewVial(for item: ProtocolItem, vialMg: Double, waterMl: Double,
                      syringe: SyringeType, budDays: Int = VialEngine.defaultBUDDays) {
        let v: Vial
        if let existing = item.vial { v = existing }
        else { let nv = Vial(); context.insert(nv); nv.item = item; item.vial = nv; v = nv }
        v.compoundSlug = item.compoundSlug
        v.vialMg = vialMg
        v.waterMl = waterMl
        v.syringeRaw = syringe.rawValue
        v.budDays = budDays
        v.concentrationMgPerMl = ReconstitutionCalculator.concentration(vialMg: vialMg, waterMl: waterMl)
        v.reconstitutedAt = .now
        v.legacyNudgeDismissedAt = nil
        context.saveLogged("StackService.startNewVial")
        NotificationManager.rebuild(context: context)
        WidgetBridge.update(context: context)
    }

    func remove(_ item: ProtocolItem, rebuild: Bool = true) {
        context.delete(item)
        context.saveLogged("StackService")
        if rebuild {
            NotificationManager.rebuild(context: context)
            WidgetBridge.update(context: context)
        }
    }

    /// Replaces the plan with `drafts` by MERGING in place (the onboarding refine
    /// path): an item whose compound stays gets its dose/schedule fields updated on
    /// the SAME item (id stable, vial/cycle/titration kept, DoseLogs stay linked),
    /// items not in the new plan are removed, new compounds are added, and on-screen
    /// order follows the drafts. One save + one notification/widget rebuild at the
    /// end. Never delete-all + insert-all: that re-identifies every row while Review
    /// is rendering them (deleted-model access traps) and fires the heavy rebuild
    /// per mutation.
    ///
    /// `protecting` marks items the merge may not touch (the user's own — see
    /// `ProtocolItem.aiGenerated`): they are never updated or removed, and a draft
    /// colliding with a protected slug is skipped (the caller surfaces it as a
    /// suggestion instead).
    func applyPlan(_ drafts: [DoseDraft], protecting: (ProtocolItem) -> Bool = { _ in false }) {
        let protectedSlugs = Set(items().filter(protecting).map(\.compoundSlug))
        let bySlug = Dictionary(drafts.map { ($0.compoundSlug, $0) },
                                uniquingKeysWith: { a, _ in a })
        for item in items() {
            guard !protecting(item) else { continue }
            if let d = bySlug[item.compoundSlug] {
                var merged = draft(for: item)
                merged.doseUnit = d.doseUnit
                merged.doseAmount = d.doseAmount
                merged.frequency = d.frequency
                merged.weekdays = d.weekdays
                merged.times = d.times
                commit(merged, rebuild: false)
            }
            // An AI item absent from the refined plan is LEFT IN PLACE — the
            // background swap must never delete a row the user may be looking at
            // (device crash log: SwiftData traps when a rendered StackRow touches
            // a deleted ScheduleRule). It stays visible, editable, and removable
            // by the user.
        }
        let existing = Set(items().map(\.compoundSlug))
        for d in drafts where !existing.contains(d.compoundSlug) && !protectedSlugs.contains(d.compoundSlug) {
            commit(d, rebuild: false)
        }
        let order = Dictionary(drafts.enumerated().map { ($1.compoundSlug, $0) },
                               uniquingKeysWith: { a, _ in a })
        for item in items() where !protecting(item) {
            item.sortIndex = order[item.compoundSlug] ?? item.sortIndex
        }
        context.saveLogged("StackService")
        NotificationManager.rebuild(context: context)
        WidgetBridge.update(context: context)
    }

    /// A cheap, order-independent snapshot of the editable plan state. The refine
    /// task captures one before its network call and applies its result only if it
    /// still matches — so a dose/schedule edit (not just an add/remove) made while
    /// Claude was thinking is never clobbered.
    nonisolated static func fingerprint(_ items: [ProtocolItem]) -> String {
        items.map { i in
            let times = (i.schedule?.timeSlotsMinutes ?? []).sorted().map(String.init).joined(separator: ",")
            let freq = i.schedule?.frequencyRaw ?? ""
            return "\(i.compoundSlug)|\(i.doseAmount)|\(i.doseUnitRaw)|\(freq)|\(times)"
        }
        .sorted()
        .joined(separator: ";")
    }

    /// Whether Claude's draft differs enough from the user's own item to surface
    /// as a suggestion (dose off by >15%, or a different unit/cadence/times).
    nonisolated static func suggestsChange(dose: Double, unitRaw: String, frequencyRaw: String,
                                           times: [Int], draft d: DoseDraft) -> Bool {
        if d.doseUnit.rawValue != unitRaw { return true }
        if d.frequency.rawValue != frequencyRaw { return true }
        if d.times.sorted() != times.sorted() { return true }
        guard dose > 0 else { return d.doseAmount > 0 }
        return abs(d.doseAmount - dose) / dose > 0.15
    }

    private func scheduleType(for f: Frequency) -> ScheduleType {
        switch f {
        case .daily: .daily
        case .eod: .interval
        case .weekly: .weekly
        case .prn: .asNeeded
        }
    }

    private func seedDose(_ c: CatalogCompound) -> Double {
        if let lo = c.typicalDoseLow, let hi = c.typicalDoseHigh { return (lo + hi) / 2 }
        return c.typicalDoseLow ?? c.typicalDoseHigh ?? 0
    }
}

/// Mutable, in-memory editing state for the dose-setup sheet.
struct DoseDraft: Identifiable {
    var id = UUID()
    var editingItemID: UUID? = nil
    /// Provenance carried into the item on commit (see `ProtocolItem.aiGenerated`).
    /// The dose sheet forces this false on save: a user edit claims the item.
    var aiGenerated: Bool = false
    var compoundSlug: String
    var displayName: String
    var categoryRaw: String = PeptideCategory.other.rawValue
    var rxStatusRaw: String = RxStatus.nonRx.rawValue
    var routeRaw: String = ""
    var doseUnit: DoseUnit = .mcg
    var doseAmount: Double = 0
    var frequency: Frequency = .daily
    var weekdays: Set<Int> = []                 // 1=Sun…7=Sat
    var times: [Int] = []                       // minutes-from-midnight

    // Optional vial for syringe-unit tracking.
    var hasVial: Bool = false
    /// True when the item being edited already has a reconstituted vial. The setup
    /// sheet uses this to fix the size (changing it routes through `startNewVial`,
    /// which resets the supply clock) rather than mutating it in place.
    var hasExistingVial: Bool = false
    var vialMg: Double = 0
    var waterMl: Double = 0
    var syringe: SyringeType = .u100
    var budDays: Int = VialEngine.defaultBUDDays

    // Advanced (M9): cycle envelope + titration ladder. Collapsed by default in the sheet.
    var protocolStart: Date = .now
    var cycleEnabled: Bool = false
    var cycleOnValue: Int = 0           // in the chosen unit (days or weeks)
    var cycleOffValue: Int = 0
    var cycleUnit: CycleUnit = .weeks
    var titrationEnabled: Bool = false
    var titrationSteps: [TitrationStepDraft] = []

    var hasCycle: Bool { cycleEnabled && cycleOnValue > 0 && cycleOffValue > 0 }
    var hasTitration: Bool { titrationEnabled && !titrationSteps.isEmpty }
    var cycleOnDays: Int { cycleOnValue * cycleUnit.perStep }
    var cycleOffDays: Int { cycleOffValue * cycleUnit.perStep }

    /// Live "draw to X units" for the current dose + vial draft, or nil. Routes
    /// through `VialEngine.doseMg`, so IU items draw too (HGH-class approximation).
    var drawUnitsText: String? {
        guard hasVial, vialMg > 0, waterMl > 0,
              let doseMg = VialEngine.doseMg(doseAmount, unit: doseUnit), doseMg > 0 else { return nil }
        let u = ReconstitutionCalculator.units(doseMg: doseMg, vialMg: vialMg,
                                               waterMl: waterMl, syringe: syringe)
        guard u > 0 else { return nil }
        return "Draw to \(vtFormatUnits(u)) units (\(syringe.label))"
    }

    /// Convenience: which blocks are active (derived from `times`).
    var blocks: Set<DayBlock> {
        get { Set(times.map { DayBlock.from(minutes: $0) }) }
        set {
            // Keep existing times whose block is still selected; add defaults for new blocks.
            let kept = times.filter { newValue.contains(DayBlock.from(minutes: $0)) }
            let keptBlocks = Set(kept.map { DayBlock.from(minutes: $0) })
            let added = newValue.subtracting(keptBlocks).map { $0.defaultMinutes }
            times = (kept + added).sorted()
        }
    }

    var isEditing: Bool { editingItemID != nil }
}

/// One editable titration step in the setup sheet (week N from protocol start + a dose).
struct TitrationStepDraft: Identifiable, Equatable {
    let id = UUID()
    var weekN: Int = 1
    var dose: Double = 0
}
