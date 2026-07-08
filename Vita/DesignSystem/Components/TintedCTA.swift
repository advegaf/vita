import SwiftUI

/// A filled tinted call-to-action capsule (white label on an accent) with press
/// feedback and a >=44pt target. Real button chrome for links that used to be bare
/// tinted text ("Connect Apple Health", "Ask vita about this").
struct TintedCTA: View {
    let title: String
    var tint: Color = VT.dose
    var accessibilityHintText: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.press(); action() }) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(tint, in: Capsule())
        }
        .buttonStyle(.pressableCard)
        .accessibilityHint(accessibilityHintText ?? "")
    }
}

#Preview {
    VStack(spacing: 16) {
        TintedCTA(title: "Connect Apple Health") {}
        TintedCTA(title: "Ask vita about this", tint: VT.why) {}
    }
    .padding()
    .background(VT.canvas)
}
