import Foundation
import SwiftData

extension ModelContext {
    /// Save that surfaces failures instead of silently dropping them. A failed save
    /// (disk full, store corruption) previously vanished behind `try?` — the user's
    /// dose appeared logged but wasn't. The write paths can't reasonably recover,
    /// but the failure must at least be visible in diagnostics.
    func saveLogged(_ site: StaticString) {
        do {
            try save()
        } catch {
            NSLog("vita-save-FAILED at %@: %@", String(describing: site), String(describing: error))
            assertionFailure("SwiftData save failed at \(site): \(error)")
        }
    }
}
