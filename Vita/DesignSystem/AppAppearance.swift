import SwiftUI

/// The user's appearance preference. Defaults to following the system.
enum AppAppearance: String, CaseIterable {
    case system, light, dark

    /// nil means "no preference" — follow the device setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light:  .light
        case .dark:   .dark
        }
    }
    var label: String {
        switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" }
    }
}
