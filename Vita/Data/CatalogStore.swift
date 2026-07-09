import Foundation
import SwiftData

/// Codable shape of one `catalog.json` entry.
struct CatalogSeed: Codable {
    var slug: String
    var name: String
    var aliases: [String]?
    var category: String
    var subcategory: String?
    var rxStatus: String
    var rxRationale: String?
    var doseUnit: String
    var typicalDoseLow: Double?
    var typicalDoseHigh: Double?
    var defaultCadenceLabel: String?
    var defaultScheduleType: String?
    var availableVialSizesMg: [Double]?
    var defaultVialSizeMg: Double?
    var recommendedWaterMl: Double?
    var reconNote: String?
    var routes: [String]?
    var mechanismBlurb: String?
    var about: String?
    var cycleGuidance: String?
}

/// Resolves the bundle that actually contains catalog.json (app vs. test host).
final class VitaBundleMarker {}

@MainActor
enum CatalogStore {
    static let seedVersion = 3   // v3: + Vial entity in schema

    /// Idempotent first-launch bootstrap: singletons, goals, catalog, RX overrides.
    static func bootstrap(_ context: ModelContext) {
        let settings = fetchOrCreateSettings(context)
        _ = fetchOrCreateProfile(context, settings: settings)
        seedGoalsIfNeeded(context)
        if settings.catalogSeedVersion < seedVersion {
            seedCatalog(context)
            settings.catalogSeedVersion = seedVersion
        }
        applyRxOverrides(context, settings: settings)
        backfillRoutes(context)
        try? context.save()
    }

    /// Idempotent: items created before `ProtocolItem.routeRaw` existed get their
    /// route from the catalog by slug (unknown slugs stay empty; rotation just hides).
    static func backfillRoutes(_ context: ModelContext) {
        let items = ((try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? [])
            .filter { $0.routeRaw.isEmpty }
        guard !items.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        let bySlug = Dictionary(all.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        for item in items {
            if let route = bySlug[item.compoundSlug]?.primaryRoute {
                item.routeRaw = route.rawValue
            }
        }
    }

    // MARK: Singletons (fixed-id fetch-or-create)

    // Singletons: fetch-all + first. A UUID `#Predicate` traps in SwiftData, and the
    // fixed default id still lets a future CloudKit merge dedupe naturally.
    static func fetchOrCreateSettings(_ context: ModelContext) -> AppSettings {
        if let s = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first { return s }
        let s = AppSettings(); context.insert(s); return s
    }

    static func fetchOrCreateProfile(_ context: ModelContext, settings: AppSettings) -> UserProfile {
        if let p = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first { return p }
        let p = UserProfile(); p.settings = settings; context.insert(p); return p
    }

    // MARK: Goals

    static func seedGoalsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Goal>())) ?? []
        guard existing.isEmpty else { return }
        for k in GoalKind.allCases {
            context.insert(Goal(kindRaw: k.rawValue, label: k.label, sortIndex: k.sortIndex))
        }
    }

    // MARK: Catalog (idempotent upsert by slug)

    static func seedCatalog(_ context: ModelContext) {
        guard let seeds = loadSeeds() else {
            #if DEBUG
            print("Vita: catalog.json missing or invalid. Catalog not seeded.")
            #endif
            return
        }
        let existing = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        var bySlug = Dictionary(existing.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        for s in seeds {
            let c: CatalogCompound
            if let found = bySlug[s.slug] {
                c = found
            } else {
                c = CatalogCompound(slug: s.slug)
                context.insert(c)
                bySlug[s.slug] = c
            }
            apply(s, to: c)
        }
    }

    static func loadSeeds() -> [CatalogSeed]? {
        for b in [Bundle.main, Bundle(for: VitaBundleMarker.self)] {
            if let url = b.url(forResource: "catalog", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let seeds = try? JSONDecoder().decode([CatalogSeed].self, from: data) {
                return seeds
            }
        }
        return nil
    }

    private static func apply(_ s: CatalogSeed, to c: CatalogCompound) {
        c.name = s.name
        c.aliases = s.aliases ?? []
        c.categoryRaw = s.category
        c.subcategory = s.subcategory
        c.rxStatusRaw = s.rxStatus
        c.rxRationale = s.rxRationale
        c.doseUnitRaw = s.doseUnit
        c.typicalDoseLow = s.typicalDoseLow
        c.typicalDoseHigh = s.typicalDoseHigh
        c.defaultCadenceLabel = s.defaultCadenceLabel
        c.defaultScheduleTypeRaw = s.defaultScheduleType
        c.availableVialSizesMg = s.availableVialSizesMg ?? []
        c.defaultVialSizeMg = s.defaultVialSizeMg
        c.recommendedWaterMl = s.recommendedWaterMl
        c.reconNote = s.reconNote
        c.routesRaw = s.routes ?? []
        c.mechanismBlurb = s.mechanismBlurb
        c.about = s.about
        c.cycleGuidance = s.cycleGuidance
        c.educationalOnly = true
    }

    // MARK: RX overrides ("slug=rx" / "slug=nonRx" / "slug=ambiguous")

    static func applyRxOverrides(_ context: ModelContext, settings: AppSettings) {
        guard !settings.customRxOverrides.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        let bySlug = Dictionary(all.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        for entry in settings.customRxOverrides {
            let parts = entry.split(separator: "=", maxSplits: 1).map(String.init)
            guard parts.count == 2,
                  let c = bySlug[parts[0]],
                  RxStatus(rawValue: parts[1]) != nil else { continue } // tolerate orphans
            c.rxStatusRaw = parts[1]
        }
    }
}
