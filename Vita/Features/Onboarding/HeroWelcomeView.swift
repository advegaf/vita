import SwiftUI

/// The first screen a new user sees: a full-bleed hero photo, the Vita wordmark,
/// and a single Get-started pill into onboarding. Local-first — no accounts.
/// (The hero is a curated placeholder; a brand video can replace it later.)
struct HeroWelcomeView: View {
    var onGetStarted: () -> Void

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Image("welcome-hero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .ignoresSafeArea()

            // Scrims so the wordmark and buttons always read over the photo.
            LinearGradient(colors: [.black.opacity(0.45), .clear],
                           startPoint: .top, endPoint: .center)
                .ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .center, endPoint: .bottom)
                .ignoresSafeArea()

            VStack {
                HStack(spacing: 2) {
                    Text("Vita")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                    Circle().fill(Color(hex: "2BB3F3")).frame(width: 7, height: 7)
                        .offset(y: 8)
                }
                .padding(.top, 16)
                .accessibilityLabel("Vita")

                Spacer()

                VStack(spacing: 14) {
                    Button {
                        Haptics.commit()
                        onGetStarted()
                    } label: {
                        Text("Get started")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color(hex: "111111"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(.white, in: Capsule())
                    }
                    .buttonStyle(.pressableCard)

                    Text("Your health protocol, in one place. Educational, not medical advice.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, VT.sSection)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview { HeroWelcomeView(onGetStarted: {}) }
