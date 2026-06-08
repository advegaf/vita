import SwiftUI

/// The single primary action. Full-width ink pill, white bold label.
/// The only "filled" surface in the design system.
struct CharcoalPillButton: View {
    var title: String
    var action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: {
            Haptics.press()
            action()
        }) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(VT.ink, in: Capsule())
                .scaleEffect(pressed ? 0.98 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
    }
}

#Preview {
    VStack {
        CharcoalPillButton(title: "Log today's dose") {}
        CharcoalPillButton(title: "Got it") {}
    }
    .padding(24)
    .background(VT.canvas)
}
