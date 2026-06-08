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
        d.categoryRaw = item.categoryRaw
        d.rxStatusRaw = item.rxStatusRaw
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
            d.hasVial = true; d.vialMg = v.vialMg; d.waterMl = v.waterMl; d.syringe = v.syringe
        }
        return d
    }

    /// Persists a draft as a new item or updates the one being edited. Dedupe on add.
    @discardableResult
    func commit(_ d: DoseDraft) -> ProtocolItem? {
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
        }
        item.doseUnitRaw = d.doseUnit.rawValue
        item.doseAmount = max(0, d.doseAmount)
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

        // Vial (create / update / clear).
        if d.hasVial, d.vialMg > 0, d.waterMl > 0 {
            let v = item.vial ?? { let nv = Vial(); item.vial = nv; return nv }()
            v.compoundSlug = d.compoundSlug
            v.vialMg = d.vialMg
            v.waterMl = d.waterMl
            v.syringeRaw = d.syringe.rawValue
            v.concentrationMgPerMl = ReconstitutionCalculator.concentration(vialMg: d.vialMg, waterMl: d.waterMl)
        } else if let v = item.vial {
            context.delete(v); item.vial = nil
        }

        try? context.save()
        NotificationManager.rebuild(context: context)
        return item
    }

    func remove(_ item: ProtocolItem) {
        context.delete(item)
        try? context.save()
        NotificationManager.rebuild(context: context)
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
    var compoundSlug: String
    var displayName: String
    var categoryRaw: String = PeptideCategory.other.rawValue
    var rxStatusRaw: String = RxStatus.nonRx.rawValue
    var doseUnit: DoseUnit = .mcg
    var doseAmount: Double = 0
    var frequency: Frequency = .daily
    var weekdays: Set<Int> = []                 // 1=Sun…7=Sat
    var times: [Int] = []                       // minutes-from-midnight

    // Optional vial for syringe-unit tracking.
    var hasVial: Bool = false
    var vialMg: Double = 0
    var waterMl: Double = 0
    var syringe: SyringeType = .u100

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

    /// Live "draw to X units" for the current dose + vial draft, or nil.
    var drawUnitsText: String? {
        guard hasVial, vialMg > 0, waterMl > 0,
              let doseMg = doseUnit.toMg(doseAmount), doseMg > 0 else { return nil }
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
