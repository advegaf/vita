import Foundation

/// The widget→app action ledger. COMPILED INTO BOTH TARGETS (see project.yml).
///
/// The widget has no database (by design — no store migration risk), so its
/// interactive "log dose" button cannot write a real DoseLog. Instead the
/// intent appends a `PendingDoseLog` here (App Group JSON) and flips the slot
/// in the snapshot so the widget updates instantly and truthfully; the APP
/// ingests the ledger into real DoseLogs on its next activation (see
/// `WidgetBridge.reconcilePendingLogs`). Honest limit: a reminder already
/// scheduled for that occurrence keeps firing until the app next opens —
/// extensions can't manage the app's notification center.
enum WidgetActions {
    struct PendingDoseLog: Codable, Equatable {
        var itemID: UUID
        var dayKey: Int      // y*10000+m*100+d, zone-independent
        var minutes: Int
        var loggedAt: Date
    }

    static func ledgerURL(directory: URL? = nil) -> URL? {
        let dir = directory ?? FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroupID)
        return dir?.appendingPathComponent("widget-pending-logs.json")
    }

    static func read(directory: URL? = nil) -> [PendingDoseLog] {
        guard let url = ledgerURL(directory: directory),
              let data = try? Data(contentsOf: url) else { return [] }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([PendingDoseLog].self, from: data)) ?? []
    }

    static func append(_ entry: PendingDoseLog, directory: URL? = nil) {
        guard let url = ledgerURL(directory: directory) else { return }
        var all = read(directory: directory)
        all.append(entry)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try? (try? enc.encode(all))?.write(to: url, options: .atomic)
    }

    static func clear(directory: URL? = nil) {
        guard let url = ledgerURL(directory: directory) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Instant widget truth: flip the matching slot's `acted` in the snapshot
    /// file (the real DoseLog lands when the app reconciles).
    static func markActedInSnapshot(itemID: UUID, dayKey: Int, minutes: Int) {
        guard var snap = WidgetSnapshot.read() else { return }
        for d in snap.days.indices where WidgetSnapshot.dayKey(for: snap.days[d].day) == dayKey {
            for s in snap.days[d].slots.indices
            where snap.days[d].slots[s].minutes == minutes
                && (snap.days[d].slots[s].itemID == nil || snap.days[d].slots[s].itemID == itemID) {
                snap.days[d].slots[s].acted = true
            }
        }
        snap.write()
    }
}
