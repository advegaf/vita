import SwiftUI

/// 8px category identity dot. Superseded by CompoundTile vials on rows; kept for
/// compact contexts (legends, the gallery).
struct CategoryDot: View {
    var category: PeptideCategory
    var size: CGFloat = 8
    var body: some View {
        Circle().fill(category.tint).frame(width: size, height: size)
    }
}

/// Calm outlined prescription badge. Shown only for true prescription compounds.
/// Never filled, never blocks.
struct RxBadge: View {
    var body: some View {
        Text("℞").font(.system(size: 11, weight: .bold))
            .foregroundStyle(VT.micro)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(VT.micro.opacity(0.5), lineWidth: 1))
            .accessibilityLabel("Prescription")
    }
}

#Preview {
    HStack(spacing: 16) {
        CategoryDot(category: .cognitive)
        CategoryDot(category: .sexualHealth)
        RxBadge()
    }
    .padding(40)
    .background(VT.canvas)
}
