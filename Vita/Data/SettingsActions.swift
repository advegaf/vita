import Foundation
import SwiftData

/// Settings write + destructive actions. Mirrors DoseLogger / DiaryService so the
/// logic is unit-testable with an in-memory container. No UI here.
@MainActor
struct SettingsActions {
    let context: ModelContext

    // MARK: ℞ overrides

    /// Set or replace a compound's prescription flag (binary rx↔nonRx). Updates the
    /// persisted override list AND the live CatalogCompound so the badge changes now;
    /// CatalogStore.applyRxOverrides re-applies the list across reseeds.
    func setRxOverride(slug: String, isRx: Bool) {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let value = (isRx ? RxStatus.rx : RxStatus.nonRx).rawValue
        var overrides = settings.customRxOverrides.filter {
            $0.split(separator: "=", maxSplits: 1).first.map(String.init) != slug
        }
        overrides.append("\(slug)=\(value)")
        settings.customRxOverrides = overrides
        if let c = (try? context.fetch(FetchDescriptor<CatalogCompound>()))?.first(where: { $0.slug == slug }) {
            c.rxStatusRaw = value
        }
        try? context.save()
    }

    // MARK: Danger zone

    func clearChat() { deleteAll(ChatMessage.self) }

    func clearDoseLogs() {
        deleteAll(DoseLog.self)
        NotificationManager.rebuild(context: context)   // logged occurrences return as reminders
    }

    func resetOnboarding() {
        let s = CatalogStore.fetchOrCreateSettings(context)
        CatalogStore.fetchOrCreateProfile(context, settings: s).onboardedAt = nil
        try? context.save()
    }

    /// Wipe every model back to a fresh-install state, then reseed the catalog +
    /// fresh singletons (onboardedAt == nil → the wizard runs again). The Keychain
    /// API key is intentionally left intact (infrastructure, re-seeds anyway).
    func fullReset() {
        try? context.delete(model: ProtocolPlan.self)
        try? context.delete(model: ProtocolItem.self)
        try? context.delete(model: ScheduleRule.self)
        try? context.delete(model: Vial.self)
        try? context.delete(model: DoseLog.self)
        try? context.delete(model: ChatMessage.self)
        try? context.delete(model: DiaryEntry.self)
        try? context.delete(model: BodyMetric.self)
        try? context.delete(model: LabValue.self)
        try? context.delete(model: LabPanel.self)
        try? context.delete(model: Goal.self)
        try? context.delete(model: CatalogCompound.self)
        try? context.delete(model: UserProfile.self)
        try? context.delete(model: AppSettings.self)
        try? context.save()
        CatalogStore.bootstrap(context)                 // reseed catalog + fresh singletons
        NotificationManager.rebuild(context: context)
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        try? context.delete(model: type)
        try? context.save()
    }
}
