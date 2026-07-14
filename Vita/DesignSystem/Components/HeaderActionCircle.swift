import SwiftUI

/// THE standard trailing header control (M43): a 38pt translucent circle with
/// an ink glyph — the same recipe as TopBarPill's ellipsis, so every tab's
/// header wears identical hardware. Content can be a plain action or a Menu
/// (pass the label through `menu:`).
struct HeaderActionCircle: View {
    var systemName: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderActionGlyph(systemName: systemName)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The bare glyph-in-circle, reusable as a Menu label.
struct HeaderActionGlyph: View {
    var systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(VT.ink)
            .frame(width: 38, height: 38)
            .background(.regularMaterial, in: Circle())
    }
}

#Preview {
    HStack(spacing: 14) {
        HeaderActionCircle(systemName: "plus", label: "Add a peptide") {}
        HeaderActionCircle(systemName: "ellipsis", label: "More") {}
        HeaderActionCircle(systemName: "scalemass", label: "Log a measurement") {}
    }
    .padding(VT.sSection)
    .background(VT.canvas)
}
