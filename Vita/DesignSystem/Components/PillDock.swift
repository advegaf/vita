import SwiftUI

/// The floating bottom navigation: a rounded pill dock with the three destinations
/// plus a separate circular AI button that opens chat. Replaces the system tab bar
/// (reference language: white floating dock, soft shadow, selected = ink).
struct PillDock: View {
    @Binding var selection: AppTab
    var onAI: () -> Void

    private let items: [(tab: AppTab, title: String, symbol: String)] = [
        (.home, "Home", "house.fill"),
        (.data, "Data", "chart.bar.fill"),
        (.protocolTab, "Protocol", "list.bullet.rectangle.portrait.fill"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(items, id: \.tab) { item in
                    dockItem(item.tab, item.title, item.symbol)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(VT.card, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
            .vtCardShadow()

            Button {
                Haptics.press()
                onAI()
            } label: {
                Image(systemName: "sparkle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(VT.dose)
                    .frame(width: 64, height: 64)
                    .background(VT.card, in: Circle())
            }
            .buttonStyle(.pressableCard)
            .vtCardShadow()
            .accessibilityLabel("Ask Vita")
            .accessibilityHint("Opens chat")
        }
        .padding(.horizontal, VT.sSection)
    }

    private func dockItem(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let selected = selection == tab
        return Button {
            if !selected { Haptics.press() }
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .medium))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(selected ? VT.ink : VT.micro)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack {
        Spacer()
        PillDock(selection: .constant(.home), onAI: {})
    }
    .background(VT.canvas)
}
