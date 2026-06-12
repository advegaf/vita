import SwiftUI

/// The shared press-state for tappable cards and rows: a calm 0.98 scale + slight
/// dim while pressed (Reduce-Motion: dim only). Cards previously gave no feedback
/// at all on touch — this makes every tappable surface feel tangible without
/// competing with the sacred pin-tap ritual.
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}

#Preview {
    VStack(spacing: 16) {
        Button {} label: {
            Text("Press me").frame(maxWidth: .infinity).padding(VT.sCardPad).vtCard()
        }
        .buttonStyle(.pressableCard)
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
