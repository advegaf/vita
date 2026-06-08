import SwiftUI
import UIKit

/// Resigns the current first responder (closes the keyboard) regardless of which
/// field holds focus. The one reliable dismiss path used app-wide.
@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil, from: nil, for: nil)
}

extension View {
    /// Tap anywhere on this view to dismiss the keyboard. Uses a simultaneous tap
    /// so it does NOT swallow button / row / chip taps, and TapGesture ignores
    /// scroll drags so scrolling is unaffected.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
    }
}
