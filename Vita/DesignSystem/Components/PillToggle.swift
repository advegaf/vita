import SwiftUI

/// The one capsule toggle used across the app (syringe / frequency / timing /
/// side-effects / sex / units). Filled when on (ink by default; an accent where a
/// section color-codes), faint ink when off; 11pt vertical pad, ≥44 tap height,
/// soft haptic, and built-in VoiceOver label + selected trait. Replaces the
/// per-screen bespoke capsule buttons so they stop drifting (9/10/11pt).
struct PillToggle: View {
    let title: String
    let isOn: Bool
    /// Spoken label if it should differ from the visible title (e.g. "Monday" for "M").
    var spoken: String? = nil
    /// Fill color when selected — defaults to the charcoal ink; pass an accent
    /// where a section color-codes (timing yellow, day-block brown).
    var onColor: Color = VT.ink
    /// Stretch to fill its container (grids) vs hug its content (scrolling rows).
    var fillsWidth: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.press()
            action()
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? VT.onInk : VT.body)
                .frame(maxWidth: fillsWidth ? .infinity : nil)
                .padding(.horizontal, fillsWidth ? 4 : 16)
                .padding(.vertical, 11)
                .background(isOn ? onColor : VT.ink.opacity(0.06), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(spoken ?? title)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack(spacing: 12) {
        HStack(spacing: 8) {
            PillToggle(title: "Daily", isOn: true) {}
            PillToggle(title: "Weekly", isOn: false) {}
        }
        HStack(spacing: 8) {
            PillToggle(title: "Morning", isOn: true, onColor: VT.why) {}
            PillToggle(title: "Night", isOn: false, onColor: VT.why) {}
        }
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
