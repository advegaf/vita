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
                HStack(spacing: 2) {
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

    /// Compact items (M43): unselected = icon-only 48pt; selected = a hugging
    /// black pill with icon + label. One critically-damped spring animates the
    /// WHOLE bar's relayout, `.geometryGroup()` keeps each item's children from
    /// jumping independently, and the label fades with the expansion instead of
    /// popping in — calm, not jumpy, not sprawling.
    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        Button {
            guard !selected else { return }
            Haptics.segment()
            withAnimation(reduceMotion ? VMotion.reduced : .spring(duration: 0.35, bounce: 0)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(tab.title)
                    .font(.system(size: 13, weight: .semibold))
                    .fixedSize()
                    .frame(width: selected ? nil : 0, alignment: .leading)
                    .clipped()
                    .opacity(selected ? 1 : 0)
            }
            .foregroundStyle(selected ? VT.onInk : VT.body)
            .padding(.horizontal, selected ? 15 : 12)
            .frame(minWidth: 48, minHeight: 44)
            .background {
                if selected {
                    Capsule().fill(VT.ink)
                        .matchedGeometryEffect(id: "selected-pill", in: pill)
                }
            }
            .contentShape(Capsule())
            .geometryGroup()
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
