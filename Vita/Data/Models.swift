import Foundation
import SwiftData

// MARK: - CloudKit legality (enforced for forward-compat with sync)
// Every stored property is optional or defaulted; every relationship is optional and
// has exactly one explicit `inverse`; no `@Attribute(.unique)`; delete rules are
// `.cascade`/`.nullify` only. Uniqueness (slug, singletons) is enforced in code, not
// by constraints. Runs in a local-only container today; see VitaContainer.

@Model
final class CatalogCompound {
    var slug: String = ""
    var name: String = ""
    var aliases: [String] = []
    var categoryRaw: String = PeptideCategory.other.rawValue
    var subcategory: String?
    var rxStatusRaw: String = RxStatus.nonRx.rawValue
    var rxRationale: String?
    var doseUnitRaw: String = DoseUnit.mcg.rawValue
    var typicalDoseLow: Double?
    var typicalDoseHigh: Double?
    var defaultCadenceLabel: String?
    var defaultScheduleTypeRaw: String?
    var availableVialSizesMg: [Double] = []
    var defaultVialSizeMg: Double?
    var recommendedWaterMl: Double?
    var reconNote: String?
    /// IU↔mg ratio for HGH-class compounds dosed in IU (e.g. somatropin ≈ 3 IU/mg).
    /// nil for everything dosed in mcg/mg; `VialEngine.doseMg` falls back to
    /// `ReconstitutionCalculator.iuPerMg` (3.0) plus an on-screen approximation caption.
    var iuPerMg: Double?
    var routesRaw: [String] = []
    var mechanismBlurb: String?
    var about: String?            // 2-3 sentence educational description
    var cycleGuidance: String?
    var educationalOnly: Bool = true

    init(slug: String = "") { self.slug = slug }

    var category: PeptideCategory { PeptideCategory(rawValue: categoryRaw) ?? .other }
    var rxStatus: RxStatus { RxStatus(rawValue: rxStatusRaw) ?? .nonRx }
    var doseUnit: DoseUnit { DoseUnit(rawValue: doseUnitRaw) ?? .mcg }
    var primaryRoute: Route? { routesRaw.first.flatMap { Route(rawValue: $0) } }
    var defaultScheduleType: ScheduleType? { defaultScheduleTypeRaw.flatMap { ScheduleType(rawValue: $0) } }

    /// "0.25–2 mg" / "250 mcg" — used in the catalog subtitle + seed-mode Dose card.
    var doseRangeText: String? {
        guard let lo = typicalDoseLow, let hi = typicalDoseHigh else { return nil }
        let u = doseUnit.label
        return lo == hi ? "\(vtFormatNumber(lo)) \(u)" : "\(vtFormatNumber(lo))–\(vtFormatNumber(hi)) \(u)"
    }

    /// "GLP-1 agonist, subcutaneous" — true of the substance, no plan context.
    var subtitle: String {
        let bits = [subcategory, primaryRoute?.label].compactMap { $0 }.filter { !$0.isEmpty }
        return bits.joined(separator: ", ")
    }

    /// Smart monogram for the placeholder tile (BPC, TB, GHK, CJC, MOTS, PT, NAD… else 2 letters).
    var monogram: String {
        let known: [String: String] = [
            "bpc-157": "BPC", "tb-500": "TB", "bpc-157-tb-500": "B+T",
            "ghk-cu": "GHK", "cjc-1295": "CJC", "cjc-1295-dac": "CJC",
            "mots-c": "MOTS", "pt-141": "PT", "nad": "NAD", "igf-1-lr3": "IGF",
            "5-amino-1mq": "5A", "ss-31": "SS", "ll-37": "LL", "aod-9604": "AOD",
            "hgh": "HGH", "hgh-fragment-176-191": "HGF", "hcg": "HCG", "hmg": "HMG",
            "snap-8": "SN8", "vip": "VIP", "dsip": "DSIP", "kpv": "KPV", "aicar": "AIC",
        ]
        if let m = known[slug] { return m }
        let letters = name.filter { $0.isLetter }
        if letters.count >= 2 { return String(letters.prefix(2)).uppercased() }
        return String(letters.prefix(1)).uppercased()
    }
}

@Model
final class Goal {
    var kindRaw: String = ""
    var label: String = ""
    var isSelected: Bool = false
    var sortIndex: Int = 0
    init(kindRaw: String = "", label: String = "", sortIndex: Int = 0) {
        self.kindRaw = kindRaw; self.label = label; self.sortIndex = sortIndex
    }
    var kind: GoalKind? { GoalKind(rawValue: kindRaw) }
}

@Model
final class UserProfile {
    var id: UUID = UserProfile.singletonID
    var createdAt: Date = Date.now
    var selectedGoalKinds: [String] = []
    var consentedAt: Date?      // educational/non-medical-advice consent
    var onboardedAt: Date?      // wizard finished; nil = show onboarding
    // Basic profile (auto-filled from Apple Health, user-editable). Grounds Claude.
    var birthDate: Date?
    var biologicalSexRaw: String?   // "female" | "male" | "other"
    var weightKg: Double?
    var heightCm: Double?
    @Relationship(deleteRule: .cascade, inverse: \AppSettings.profile) var settings: AppSettings?
    @Relationship(deleteRule: .cascade, inverse: \ProtocolPlan.owner) var plans: [ProtocolPlan]?
    init() {}
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
}

@Model
final class AppSettings {
    var id: UUID = AppSettings.singletonID
    var catalogSeedVersion: Int = 0
    /// "slug=rx" / "slug=nonRx" override entries applied over the seed.
    var customRxOverrides: [String] = []
    var rxAcknowledgedSlugs: [String] = []
    var notificationsEnabled: Bool = true
    var labConsentedAt: Date?     // one-time consent: lab images leave the device to be read (M8b)
    var profile: UserProfile?
    init() {}
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
}

@Model
final class ProtocolPlan {
    var id: UUID = UUID()
    var name: String = "My stack"
    var startDate: Date = Date.now
    var createdAt: Date = Date.now
    var isActive: Bool = true
    var owner: UserProfile?
    @Relationship(deleteRule: .cascade, inverse: \ProtocolItem.plan) var items: [ProtocolItem]?
    init(name: String = "My stack") { self.name = name }
}

@Model
final class ProtocolItem {
    var id: UUID = UUID()
    var compoundSlug: String = ""
    var displayName: String = ""
    var categoryRaw: String = PeptideCategory.other.rawValue
    var rxStatusRaw: String = RxStatus.nonRx.rawValue
    var doseAmount: Double = 0
    var doseUnitRaw: String = DoseUnit.mcg.rawValue
    var kindRaw: String = "scheduled" // scheduled | prn
    var cadenceLabel: String = ""
    var sortIndex: Int = 0
    var addedAt: Date = Date.now
    /// Provenance: true while the item is managed by the AI (starter/refine).
    /// Anything the user explicitly adds or edits flips to false and the refine
    /// pass may then only SUGGEST changes, never apply them.
    var aiGenerated: Bool = false
    var plan: ProtocolPlan?
    @Relationship(deleteRule: .cascade, inverse: \ScheduleRule.item) var schedule: ScheduleRule?
    @Relationship(deleteRule: .cascade, inverse: \Vial.item) var vial: Vial?
    init() {}

    var category: PeptideCategory { PeptideCategory(rawValue: categoryRaw) ?? .other }
    var rxStatus: RxStatus { RxStatus(rawValue: rxStatusRaw) ?? .nonRx }
    var doseUnit: DoseUnit { DoseUnit(rawValue: doseUnitRaw) ?? .mcg }
    var doseText: String { "\(vtFormatNumber(doseAmount)) \(doseUnit.label)" }

    /// "draw 10u" when a vial is set up and the dose converts to mg. Nil otherwise.
    /// Raw syringe units to draw for the base dose (nil without a vial or a
    /// convertible dose). Routes through `VialEngine.doseMg` so IU items draw too.
    var drawUnits: Double? {
        guard let vial, let doseMg = VialEngine.doseMg(doseAmount, unit: doseUnit), doseMg > 0 else { return nil }
        let u = ReconstitutionCalculator.units(doseMg: doseMg, vialMg: vial.vialMg,
                                               waterMl: vial.waterMl, syringe: vial.syringe)
        return u > 0 ? u : nil
    }

    // M9 titration-aware (date-threaded) variants.
    func effectiveDose(on date: Date, calendar: Calendar = .current) -> Double {
        ScheduleService.activeDose(for: self, on: date, calendar: calendar)
    }
    func effectiveDoseText(on date: Date, calendar: Calendar = .current) -> String {
        "\(vtFormatNumber(effectiveDose(on: date, calendar: calendar))) \(doseUnit.label)"
    }
    func effectiveDrawUnits(on date: Date, calendar: Calendar = .current) -> Double? {
        guard let vial,
              let doseMg = VialEngine.doseMg(effectiveDose(on: date, calendar: calendar), unit: doseUnit),
              doseMg > 0 else { return nil }
        let u = ReconstitutionCalculator.units(doseMg: doseMg, vialMg: vial.vialMg,
                                               waterMl: vial.waterMl, syringe: vial.syringe)
        return u > 0 ? u : nil
    }
    /// The row/pin dose display: "250 mcg • 10u" in the compound's authored unit,
    /// or just the dose when there is no vial. Single source for every dose+draw render.
    func doseWithDrawText(on date: Date, calendar: Calendar = .current) -> String {
        DoseFormat.doseWithDraw(dose: effectiveDoseText(on: date, calendar: calendar),
                                drawUnits: effectiveDrawUnits(on: date, calendar: calendar))
    }
}

@Model
final class Vial {
    var id: UUID = UUID()
    var compoundSlug: String = ""
    var vialMg: Double = 0
    var waterMl: Double = 0
    var syringeRaw: String = SyringeType.u100.rawValue
    var concentrationMgPerMl: Double = 0
    var reconstitutedAt: Date = Date.now
    /// Beyond-use awareness (educational). Day-count since reconstitution the UI
    /// calls out; 28 is a common reference for refrigerated reconstituted peptides.
    var budDays: Int = 28
    /// Set once the user dismisses the "legacy vial" adoption nudge (a vial that
    /// predates numeric dose stamping shows full-remaining until a new vial starts).
    var legacyNudgeDismissedAt: Date?
    var item: ProtocolItem?
    init() {}

    var syringe: SyringeType { SyringeType(rawValue: syringeRaw) ?? .u100 }
}

/// How often a peptide is taken (M2a). Cycles/titration arrive in M4.
enum Frequency: String, Codable, Sendable, CaseIterable {
    case daily, eod, weekly, prn
    var label: String {
        switch self {
        case .daily: "Daily"
        case .eod:   "Every other day"
        case .weekly:"Weekly"
        case .prn:   "As needed"
        }
    }
}

@Model
final class ScheduleRule {
    var id: UUID = UUID()
    var scheduleTypeRaw: String = ScheduleType.daily.rawValue
    var cadenceLabel: String = ""
    var timesPerDay: Int = 1
    var intervalDays: Int = 1

    // M2a scheduling fields (CloudKit-legal: primitives + defaults).
    var frequencyRaw: String = Frequency.daily.rawValue          // daily | eod | weekly | prn
    var timeSlotsMinutes: [Int] = []                             // minutes-from-midnight, e.g. 480 = 8:00
    var weekdays: [Int] = []                                     // 1=Sun … 7=Sat (weekly)
    var anchorDate: Date = Date.now                              // protocol-start anchor (EOD parity + cycle + titration)

    // M9 cycle envelope + titration ladder (CloudKit-legal: primitives, defaulted).
    var cycleOnDays: Int = 0                                     // stored in DAYS; 0/0 = continuous
    var cycleOffDays: Int = 0
    var cycleUnitRaw: String = CycleUnit.weeks.rawValue          // LABELING only (days vs weeks)
    var titrationDayStarts: [Int] = []                          // (weekN-1)*7, sorted; parallel to doses
    var titrationDoses: [Double] = []

    // Not expanded into persistent DoseEvents until M4 (SchedulingEngine).
    var item: ProtocolItem?
    init() {}

    var scheduleType: ScheduleType { ScheduleType(rawValue: scheduleTypeRaw) ?? .daily }
    var frequency: Frequency { Frequency(rawValue: frequencyRaw) ?? .daily }

    // M9 conveniences (non-stored).
    var cycleUnit: CycleUnit { CycleUnit(rawValue: cycleUnitRaw) ?? .weeks }
    var protocolStart: Date { anchorDate }
    var hasCycle: Bool { cycleOnDays > 0 && cycleOffDays > 0 }
    var hasTitration: Bool { !titrationDayStarts.isEmpty && titrationDayStarts.count == titrationDoses.count }
    /// Titration steps zipped + sorted by start; defends against array-length desync.
    var titrationSteps: [(dayStart: Int, dose: Double)] {
        zip(titrationDayStarts, titrationDoses).map { (dayStart: $0.0, dose: $0.1) }
            .sorted { $0.dayStart < $1.dayStart }
    }
}

/// One message in the single ongoing Chat thread (M3b). CloudKit-legal. An
/// assistant message may carry one suggested stack action the UI renders as a chip.
@Model
final class ChatMessage {
    var id: UUID = UUID()
    var roleRaw: String = "user"        // user | assistant
    var text: String = ""
    var createdAt: Date = Date.now
    // One entry per recommended Add/Adjust chip (parallel arrays, CloudKit-legal).
    var suggestionSlugs: [String] = []
    var suggestionActions: [String] = []
    var suggestionDoses: [Double] = []   // parallel; <= 0 means "no dose suggested"
    init() {}

    var isUser: Bool { roleRaw == "user" }
}

/// An append-only record that a dose was taken or skipped (M4). CloudKit-legal,
/// denormalized (no relationship) so history survives item edits/removal. For a
/// scheduled dose the (itemID, scheduledDayStart, scheduledMinutes) triple keys
/// the occurrence; PRN logs set `isPRN` and append freely (multiple per day).
@Model
final class DoseLog {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var compoundSlug: String = ""
    var displayName: String = ""
    var doseText: String = ""
    /// Numeric dose stamped at log time (M37), titration-aware, so supply math
    /// survives later dose/titration edits. SENTINEL: `doseAmount == 0` means an
    /// unstamped legacy log (created before M37) — it contributes 0 mg to vial
    /// consumption by construction. A real logged dose is always > 0. This sentinel
    /// is load-bearing; a versioned V2 schema is required before CloudKit ships.
    var doseAmount: Double = 0
    var doseUnitRaw: String = ""
    var categoryRaw: String = PeptideCategory.other.rawValue
    var scheduledDayStart: Date = Date.now    // startOfDay of the scheduled day
    var scheduledMinutes: Int = 0             // slot, minutes-from-midnight
    var statusRaw: String = DoseStatus.taken.rawValue
    var isPRN: Bool = false
    var loggedAt: Date = Date.now
    init() {}

    var status: DoseStatus { DoseStatus(rawValue: statusRaw) ?? .taken }
    var category: PeptideCategory { PeptideCategory(rawValue: categoryRaw) ?? .other }
    /// nil for legacy logs (empty `doseUnitRaw`); a stamped unit otherwise.
    var doseUnit: DoseUnit? { doseUnitRaw.isEmpty ? nil : DoseUnit(rawValue: doseUnitRaw) }
}
