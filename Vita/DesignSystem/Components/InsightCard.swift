import SwiftUI

/// The AI surface (M40): a lavender card with a sparkle and a purple lead —
/// the design language's "Lumina Insight" pattern. Two variants: a soft
/// gradient fill (hero contexts) and a dashed outline (inline/journal
/// contexts). Educational voice; never medical advice.
struct InsightCard: View {
    enum Style { case fill, dashed }

    var lead: String = "Vita insight"
    var text: String
    var style: Style = .fill
    var onTap: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VT.aiText)
                .frame(width: 30, height: 30)
                .background(VT.card.opacity(0.7), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(lead)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(VT.aiText)
                Text(text)
                    .font(.system(size: 14))
                    .foregroundStyle(VT.body)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundShape)
        .contentShape(RoundedRectangle(cornerRadius: VT.rCard, style: .continuous))
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var backgroundShape: some View {
        let shape = RoundedRectangle(cornerRadius: VT.rCard, style: .continuous)
        switch style {
        case .fill:
            shape.fill(
                LinearGradient(colors: [VT.aiTint, VT.aiTint.opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
        case .dashed:
            shape.fill(VT.aiTint.opacity(0.45))
                .overlay(
                    shape.strokeBorder(VT.aiText.opacity(0.45),
                                       style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                )
        }
    }
}

#Preview {
    VStack(spacing: VT.sCardGap) {
        InsightCard(text: "You've felt calmer this week than last week.")
        InsightCard(text: "You completed yesterday's plan. Keep it up.", style: .dashed)
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
