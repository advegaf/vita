import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum Haptics {
    static func press() {
        #if canImport(UIKit)
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare(); g.impactOccurred()
        #endif
    }

    static func segment() {
        #if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
    }

    static func commit() {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
}
