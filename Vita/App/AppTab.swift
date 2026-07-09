import SwiftUI

/// The three dock destinations (chat is a sheet opened by the AI button, not a tab).
enum AppTab: Hashable {
    case home, data, protocolTab

    /// Initial tab (production: Home). Debug: set VITA_TAB=data|protocol to screenshot that tab.
    static var initialForScreenshots: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["VITA_TAB"] {
        case "data":     return .data
        case "protocol": return .protocolTab
        default:         return .home
        }
        #else
        return .home
        #endif
    }
}
