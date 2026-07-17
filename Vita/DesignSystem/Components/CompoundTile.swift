import SwiftUI

/// A compound's visual identity: the category-colored vial render, presented in
/// an Apple-style squircle (continuous-corner rounded square at the ~22.4% icon
/// radius). One vial per category. Replaces the old monogram tile.
struct CompoundTile: View {
    let category: PeptideCategory
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var colorScheme

    // Apple's home-screen icon superellipse: corner radius ≈ 22.37% of the side.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        Image(category.vialAsset)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .background(VT.card)
            .clipShape(shape)
            // The vial renders carry a baked-in near-white studio backdrop that
            // pops bright on graphite. In dark mode, drop a canvas-toned scrim so
            // the tile settles onto the card instead of glaring off it.
            .overlay { if colorScheme == .dark { shape.fill(VT.canvas).opacity(0.5) } }
            .overlay(shape.strokeBorder(VT.hairline, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 10) {
        ForEach(PeptideCategory.allCases, id: \.self) { c in
            CompoundTile(category: c)
        }
    }
    .padding(30)
    .background(VT.canvas)
}
