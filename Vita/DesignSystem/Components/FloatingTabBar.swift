import SwiftUI

/// M40 navigation: a floating frosted capsule with the four views as icons;
/// the selected view is a solid black pill carrying icon + label (the design
/// language's signature move — black marks "current"). The pill slides between
/// items with a spring.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var pill
    /// Collapse while the keyboard is up (typing hides the bar instead of
    /// stacking it above the keyboard).
    @State private var keyboardUp = false

    var body: some View {
        Group {
            if !keyboardUp {
                HStack(spacing: 4) {
                    ForEach(AppTab.allCases) { tab in
                        item(tab)
                    }
                }
                .padding(6)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.10), radius: 16, y: 6)
                .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.2)) { keyboardUp = false }
        }
    }

    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        Button {
            guard !selected else { return }
            Haptics.segment()
            withAnimation(reduceMotion ? VMotion.reduced : .spring(response: 0.38, dampingFraction: 0.86)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if selected {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(selected ? VT.onInk : VT.body)
            .padding(.horizontal, selected ? 16 : 13)
            .frame(minWidth: 44, minHeight: 44)
            .background {
                if selected {
                    Capsule().fill(VT.ink)
                        .matchedGeometryEffect(id: "selected-pill", in: pill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview("Light") {
    ZStack {
        VT.canvas.ignoresSafeArea()
        VStack {
            Spacer()
            FloatingTabBar(selection: .constant(.today))
        }
    }
}

#Preview("Dark") {
    ZStack {
        VT.canvas.ignoresSafeArea()
        VStack {
            Spacer()
            FloatingTabBar(selection: .constant(.diary))
        }
    }
    .preferredColorScheme(.dark)
}
