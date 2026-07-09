import SwiftUI

/// The floating liquid-glass tab bar (M38): appears only when the card is
/// pulled up to the expanded detent (and never while the keyboard is up).
/// A material capsule with the four views — direct switching for the expanded,
/// heads-down state; at rest the photo header's arrows do the navigating.
struct GlassTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                item(tab)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }

    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            guard !selected else { return }
            Haptics.segment()
            withAnimation(reduceMotion ? VMotion.reduced : .spring(response: 0.4, dampingFraction: 1)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .medium))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? tab.tint : VT.micro)
            .frame(width: 64, height: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableCard)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Light") {
    ZStack {
        VT.canvas.ignoresSafeArea()
        GlassTabBar(selection: .constant(.today))
    }
}

#Preview("Dark") {
    ZStack {
        VT.canvas.ignoresSafeArea()
        GlassTabBar(selection: .constant(.diary))
    }
    .preferredColorScheme(.dark)
}
