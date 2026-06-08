import SwiftUI

/// A translucent circular icon button — the "+", "…", and back-chevron affordance.
/// Matches the TopBarPill material language so every top-bar control reads the same.
struct CircleIconButton: View {
    let systemName: String
    var label: String
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VT.ink)
                .frame(width: size, height: size)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: 12) {
        CircleIconButton(systemName: "plus", label: "Add") {}
        CircleIconButton(systemName: "ellipsis", label: "Menu") {}
        CircleIconButton(systemName: "chevron.left", label: "Back") {}
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
