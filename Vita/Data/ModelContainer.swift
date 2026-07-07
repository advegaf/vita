import SwiftData

/// Versioned schema (migration plan deferred until a real V2 exists).
enum VitaSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [CatalogCompound.self, Goal.self, UserProfile.self, AppSettings.self,
         ProtocolPlan.self, ProtocolItem.self, ScheduleRule.self, Vial.self,
         ChatMessage.self, DoseLog.self,
         DiaryEntry.self, BodyMetric.self,
         LabPanel.self, LabValue.self,
         ShopCartItem.self]
    }
}

@MainActor
enum VitaContainer {
    /// Local-only today. Models are CloudKit-legal, so enabling sync later means adding
    /// the iCloud entitlement + `cloudKitDatabase: .automatic` (and splitting local-only
    /// models like CatalogCompound into their own configuration) — no model rework.
    static func make(inMemory: Bool = false) -> ModelContainer {
        let schema = Schema(VitaSchemaV1.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Vita ModelContainer failed to initialize: \(error)")
        }
    }
}
