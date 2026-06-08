import SwiftUI

/// A compound's visual identity: the category-colored vial render, presented in
/// an Apple-style squircle (continuous-corner rounded square at the ~22.4% icon
/// radius). One vial per category. Replaces the old monogram tile.
struct CompoundTile: View {
    let category: PeptideCategory
    var size: CGFloat = 44

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
