import Foundation

/// Pure next-site suggestion for injection rotation. Keyed by compoundSlug, not
/// itemID: StackService re-links orphaned logs by slug on re-add and VialEngine
/// already filters by slug, so slug is the identity that survives edits. Only
/// taken logs with a stamped site count; skipped and legacy logs are invisible.
enum SiteRotation {
    /// The rotation order (alternate sides within a region, then advance region).
    static let order: [InjectionSite] = InjectionSite.allCases

    /// Most recent stamped taken site for a compound. `excluding` skips a specific
    /// log row — needed because DoseLogger UPSERTS: when re-stamping an existing
    /// log, its own old site must not advance the rotation off itself.
    static func lastSite(compoundSlug: String, logs: [DoseLog],
                         excluding logID: UUID? = nil) -> InjectionSite? {
        logs.filter {
            $0.compoundSlug == compoundSlug && $0.status == .taken
                && $0.site != nil && $0.id != logID
        }
        .max { $0.loggedAt < $1.loggedAt }?
        .site
    }

    /// The suggested next site for an item, or nil when it is not injected
    /// (oral/nasal/topical/unknown routes get no rotation).
    static func next(for item: ProtocolItem, logs: [DoseLog],
                     excluding logID: UUID? = nil) -> InjectionSite? {
        guard item.isInjectable else { return nil }
        guard let last = lastSite(compoundSlug: item.compoundSlug, logs: logs,
                                  excluding: logID),
              let idx = order.firstIndex(of: last) else { return order.first }
        return order[(idx + 1) % order.count]
    }
}
