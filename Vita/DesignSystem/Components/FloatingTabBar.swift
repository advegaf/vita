import SwiftUI

/// M44 navigation: a floating Liquid Glass capsule with the four views as
/// icons; the selected view is a solid black pill carrying icon + label (the
/// design language's signature move — black marks "current"). The pill glides
/// between items on selection; the app window itself never animates.
struct FloatingTabBar: View {
    @Binding var selection: AppTab
    var hidesForChatInput = false
    /// Collapse while the keyboard is up (typing hides the bar instead of
    /// stacking it above the keyboard).
    @State private var keyboardUp = false
    @Namespace private var pillNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if !keyboardUp && !hidesForChatInput {
                GlassEffectContainer {
                    HStack(spacing: 0) {
                        ForEach(AppTab.allCases) { tab in
                            item(tab)
                        }
                    }
                    .padding(6)
                    .glassEffect(.regular, in: .capsule)
                }
                .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // REMOTE keyboards (keyboardIsLocalUserInfoKey == false) must never hide
        // the bar: the ASWebAuthenticationSession sign-in sheet raises its own
        // out-of-process keyboard whose terminal hide notification is not
        // delivered to this app, which left the bar hidden forever (M47).
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { note in
            guard note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true else { return }
            keyboardUp = true
        }
        // The software keyboard can resize an iOS scene without delivering a
        // reliable will-show event to every SwiftUI subtree. Frame changes make
        // the bar's interaction state deterministic in both paths.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard note.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool ?? true else { return }
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            keyboardUp = frame.minY < UIScreen.main.bounds.height
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardUp = false
        }
        // Safety net: whatever a dismissed system sheet did to keyboard state,
        // returning to an active scene must always bring the bar back.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { keyboardUp = false }
        }
    }

    /// Equal fixed slots: every item is 84x44 regardless of selection, so the bar's
    /// total width is constant — nothing reflows or re-centers. The ink pill glides
    /// between the stationary slots via matched geometry and the label crossfades
    /// INSIDE the pill; page content is not animated. (Width-hugging items made the
    /// end tabs translate ~35pt on selection, which read as "out of thin air".)
    @ViewBuilder
    private func item(_ tab: AppTab) -> some View {
        let selected = tab == selection
        Button {
            guard !selected else { return }
            Haptics.segment()
            withAnimation(reduceMotion ? VMotion.reduced : VMotion.tabSelect) {
                selection = tab
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                if selected {
                    Text(tab.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .foregroundStyle(selected ? VT.onInk : VT.body)
            .frame(width: 84, height: 44)
                .background {
                    if selected {
                        Capsule()
                            .fill(VT.ink)
                            .matchedGeometryEffect(id: "pill", in: pillNS)
                    }
                }
            .contentShape(Capsule())
        }
        .buttonStyle(TabPressStyle())
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab-\(tab.rawValue)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Tactile press feedback: a subtle 0.96 scale, fast ease-out, transform-only.
private struct TabPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
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
