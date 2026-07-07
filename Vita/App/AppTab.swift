import SwiftUI

enum AppTab: Hashable {
    case today, stack, shop, diary, chat

    /// Initial tab (production: Today). Debug: set VITA_TAB=stack|shop|diary|chat to screenshot that tab.
    static var initialForScreenshots: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["VITA_TAB"] {
        case "stack": return .stack
        case "shop":  return .shop
        case "diary": return .diary
        case "chat":  return .chat
        default:      return .today
        }
        #else
        return .today
        #endif
    }
}
