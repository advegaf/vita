import SwiftUI

/// A thin capsule meter for vial supply. The fill is `VT.dose` at normal levels; when
/// supply is low it thickens slightly and switches to the `VT.overdue` terracotta so it
/// reads "calm but visible," matching how overdue doses signal without alarming. Purely
/// decorative for VoiceOver (the VialCard speaks the real numbers).
struct SupplyBar: View {
    /// 0...1 fraction remaining.
    var fraction: Double
    /// At/below the low-supply threshold (from `VialEngine.Status.isLow`): thicker track + terracotta fill.
    var isLow: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(VT.ink.opacity(0.06))
                Capsule().fill(isLow ? VT.overdue : VT.dose)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: isLow ? 6 : 4)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        SupplyBar(fraction: 0.85)
        SupplyBar(fraction: 0.4)
        SupplyBar(fraction: 0.12, isLow: true)
    }
    .padding()
    .background(VT.canvas)
}
