import SwiftUI
import SwiftData

/// Root: shows the onboarding wizard until the profile is onboarded, then the tabs.
struct AppRootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var settingsList: [AppSettings]

    private var onboarded: Bool { profiles.first?.onboardedAt != nil }
    // Empty pre-onboarding query -> nil -> follow the system.
    private var appearance: AppAppearance { settingsList.first?.appearance ?? .system }

    /// Welcome gate: the hero screen shows once before onboarding begins.
    @AppStorage("vita.welcomed") private var welcomed = false
    @State private var showCalcDebug = false

    var body: some View {
        Group {
            if onboarded {
                RootTabView()
            } else if welcomed {
                OnboardingWizard()
                    .transition(.opacity)
            } else {
                HeroWelcomeView { withAnimation(.easeInOut(duration: 0.3)) { welcomed = true } }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboarded)
        // Dark scheme over the welcome photo (light status bar); user preference after.
        .preferredColorScheme((onboarded || welcomed) ? appearance.colorScheme : .dark)
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["VITA_LAB_SELFTEST"] == "1" {
                await LabSelfTest.run(context: context)
            }
            if ProcessInfo.processInfo.environment["VITA_OPEN_CALC"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                showCalcDebug = true
            }
        }
        .sheet(isPresented: $showCalcDebug) {
            ReconCalculatorView(seedVialMg: 5, seedWaterMl: 2, seedDoseMg: 0.25,
                                onSave: { _, _, _ in })
        }
        #endif
    }
}
