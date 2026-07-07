import SwiftUI

/// A thin capsule meter for vial supply. Intentionally single-accent: the fill stays
/// `VT.dose` at every level, because "low" is carried by the words next to it, not by
/// turning the bar into an alarming error meter. Purely decorative for VoiceOver (the
/// VialCard speaks the real numbers).
struct SupplyBar: View {
    /// 0...1 fraction remaining.
    var fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(VT.ink.opacity(0.06))
                Capsule().fill(VT.dose)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 20) {
        SupplyBar(fraction: 0.85)
        SupplyBar(fraction: 0.4)
        SupplyBar(fraction: 0.12)
    }
    .padding()
    .background(VT.canvas)
}
