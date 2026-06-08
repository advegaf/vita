import SwiftUI

/// A labeled rounded input shell — a faint rounded field under a micro label.
/// Shared by onboarding (HealthConnectView) and Settings so profile editing is
/// byte-identical in both places.
@ViewBuilder
func vtFieldShell<Content: View>(_ label: String,
                                 @ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(label).font(.system(size: 13)).foregroundStyle(VT.micro)
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(VT.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Tappable cyan unit label inside a field shell (kg↔lb, cm↔ft·in).
func vtUnitTab(_ unit: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(unit).font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
    }
    .buttonStyle(.plain)
    .accessibilityHint("Tap to change unit")
}

/// A plain text field inside a shell (label + value + suffix), bound to a shared
/// focus state so the keyboard-dismiss patterns work uniformly.
func vtPlainField(_ label: String, text: Binding<String>, suffix: String,
                  keyboard: UIKeyboardType, focus: FocusState<Bool>.Binding) -> some View {
    vtFieldShell(label) {
        TextField("", text: text).keyboardType(keyboard).focused(focus)
            .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
        Text(suffix).font(.system(size: 14)).foregroundStyle(VT.micro)
    }
}
