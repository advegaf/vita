import AppIntents
import WidgetKit

/// The widget's "log this dose" tap. Writes the pending-log ledger + flips the
/// snapshot slot so the widget updates instantly; the app turns it into a real
/// DoseLog on its next activation (WidgetBridge.reconcilePendingLogs).
struct LogDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log dose"
    static let description = IntentDescription("Marks a scheduled dose as taken.")

    @Parameter(title: "Item") var itemID: String
    @Parameter(title: "Day") var dayKey: Int
    @Parameter(title: "Minutes") var minutes: Int

    init() {}
    init(itemID: UUID, dayKey: Int, minutes: Int) {
        self.itemID = itemID.uuidString
        self.dayKey = dayKey
        self.minutes = minutes
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: itemID) else { return .result() }
        WidgetActions.append(.init(itemID: id, dayKey: dayKey, minutes: minutes, loggedAt: Date()))
        WidgetActions.markActedInSnapshot(itemID: id, dayKey: dayKey, minutes: minutes)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
