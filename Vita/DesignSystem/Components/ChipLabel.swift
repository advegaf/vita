import SwiftUI

/// Small capsule chip with a leading icon circle and a label (M40, from the
/// finance mockup's "USD / GBP" chips). Used for compact metadata: category,
/// route, cadence.
struct ChipLabel: View {
    var icon: String
    var text: String
    var tint: Color = VT.ink

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18, height: 18)
                .background(tint.opacity(0.12), in: Circle())
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VT.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(VT.card, in: Capsule())
        .overlay(Capsule().strokeBorder(VT.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack {
        ChipLabel(icon: "syringe", text: "Injectable", tint: VT.dose)
        ChipLabel(icon: "calendar", text: "Daily")
        ChipLabel(icon: "moon.stars", text: "Night", tint: VT.why)
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
