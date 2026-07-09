import SwiftUI

/// The full-bleed photo behind everything (M38 card navigation). A curated,
/// bundled image with a legibility scrim: darker at the top (white header text
/// sits there) and gently darker at the foot. As the card rises (`progress`
/// 0 → 1) the photo drifts up a touch and dims, receding behind the work.
///
/// Photo: "Close-up of dark green leaves and vines" by H&CO, Unsplash
/// (unsplash.com/photos/JVeAqyZ1wrc) — Unsplash License, bundled at build time.
/// Chosen over a warm light-through-leaves candidate (its sun starburst
/// competed with the UI as a focal point) and a misty forest (near-white top
/// half where the white title sits).
struct BackdropView: View {
    var progress: CGFloat
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Image("backdrop-leaves")
                .resizable()
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .offset(y: -18 * min(1, max(0, progress)))
                .overlay(scrim)
                .overlay(Color.black.opacity(0.28 * min(1, max(0, progress))))
        }
        .ignoresSafeArea()
    }

    /// Top-weighted legibility gradient; deeper in dark mode so the card's
    /// contrast against the photo holds in both appearances.
    private var scrim: some View {
        LinearGradient(stops: [
            .init(color: .black.opacity(scheme == .dark ? 0.52 : 0.38), location: 0),
            .init(color: .black.opacity(scheme == .dark ? 0.24 : 0.12), location: 0.4),
            .init(color: .black.opacity(scheme == .dark ? 0.38 : 0.22), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

#Preview("Rest") {
    BackdropView(progress: 0)
}

#Preview("Expanded, dark") {
    BackdropView(progress: 1).preferredColorScheme(.dark)
}
