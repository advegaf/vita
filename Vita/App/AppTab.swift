import SwiftUI

enum AppTab: String, Hashable, CaseIterable, Identifiable {
    case today, stack, diary, chat

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .stack: "Stack"
        case .diary: "Diary"
        case .chat:  "Chat"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .stack: "pills"
        case .diary: "chart.xyaxis.line"
        case .chat:  "bubble.left.and.text.bubble.right"
        }
    }

    var tint: Color {
        switch self {
        case .today: VT.dose
        case .stack: VT.why
        case .diary: VT.timing
        case .chat:  VT.dose
        }
    }

    /// Wrap-around neighbors for the header's cycle controls and flick gesture.
    var next: AppTab {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
    var previous: AppTab {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + all.count - 1) % all.count]
    }

    /// Initial tab (production: Today). Debug: set VITA_TAB=stack|diary|chat to screenshot that tab.
    static var initialForScreenshots: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["VITA_TAB"] {
        case "stack": return .stack
        case "diary": return .diary
        case "chat":  return .chat
        default:      return .today
        }
        #else
        return .today
        #endif
    }
}
