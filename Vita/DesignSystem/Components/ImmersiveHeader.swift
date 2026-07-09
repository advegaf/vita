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

    /// The ⇕ capsule: a menu of all four views (predictable, one tap direct).
    private var switcher: some View {
        Menu {
            ForEach(AppTab.allCases) { tab in
                Button {
                    select(tab)
                } label: {
                    if tab == selection {
                        Label(tab.title, systemImage: "checkmark")
                    } else {
                        Text(tab.title)
                    }
                }
            }
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.17), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                .contentShape(Circle().inset(by: -4))
        }
        .accessibilityLabel("Switch view")
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
