import SwiftUI

/// The photo-layer header (M38): a small uppercase eyebrow, the big white view
/// title with the ⇕ switcher capsule, and a contextual subtitle. Lives on the
/// backdrop ABOVE the card; fades and rises away as the card expands. A
/// vertical flick anywhere on the header cycles views (the same axis as the
/// capsule's arrows), so switching never fights the card's own drag: the header
/// zone has no scroll views.
struct ImmersiveHeader: View {
    @Binding var selection: AppTab
    var eyebrow: String
    var subtitle: String?
    var progress: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold)).tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.66))
            HStack(spacing: 12) {
                Text(selection.title)
                    .font(VFont.display(36, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(.white)
                    .id(selection)
                    .transition(reduceMotion ? .opacity :
                        .asymmetric(insertion: .offset(y: 10).combined(with: .opacity),
                                    removal: .offset(y: -10).combined(with: .opacity)))
                switcher
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16, weight: .medium)).vtTabular()
                    .foregroundStyle(.white.opacity(0.88))
                    .contentTransition(.numericText())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .opacity(max(0, 1 - progress * 1.6))
        .offset(y: -26 * min(1, max(0, progress)))
        .gesture(flick)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(selection.title). \(subtitle ?? "")")
    }

    /// The icon picker (M39): all four views as icons in one glass capsule —
    /// with the tab bar gone, this IS the navigation. The selected icon sits
    /// tinted in a subtle well; one tap switches directly.
    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                pickerIcon(tab)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background(.white.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.20), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Switch view")
    }

    private func pickerIcon(_ tab: AppTab) -> some View {
        let selected = tab == selection
        return Button {
            select(tab)
        } label: {
            Image(systemName: tab.icon)
                .font(.system(size: 15, weight: selected ? .semibold : .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? tab.tint : .white.opacity(0.72))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(selected ? AnyShapeStyle(.white.opacity(0.22))
                                           : AnyShapeStyle(.clear))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("picker-\(tab.rawValue)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// Vertical flick on the header cycles views (down = next, up = previous —
    /// content follows the finger's push).
    private var flick: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let dy = value.predictedEndTranslation.height
                guard abs(dy) > 40, abs(dy) > abs(value.predictedEndTranslation.width) else { return }
                select(dy > 0 ? selection.next : selection.previous)
            }
    }

    private func select(_ tab: AppTab) {
        guard tab != selection else { return }
        Haptics.segment()
        withAnimation(reduceMotion ? VMotion.reduced : .spring(response: 0.4, dampingFraction: 1)) {
            selection = tab
        }
    }
}

#Preview {
    ZStack(alignment: .top) {
        BackdropView(progress: 0)
        VStack(alignment: .leading, spacing: 18) {
            ImmersiveHeader(selection: .constant(.today),
                            eyebrow: "Good morning.",
                            subtitle: "Two doses left.",
                            progress: 0)
        }
        .padding(24)
    }
}
