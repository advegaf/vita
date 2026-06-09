import SwiftUI
import SwiftData

/// Root: shows the onboarding wizard until the profile is onboarded, then the tabs.
struct AppRootView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    private var onboarded: Bool { profiles.first?.onboardedAt != nil }

    @State private var showCalcDebug = false

    var body: some View {
        Group {
            if onboarded {
                RootTabView()
            } else {
                OnboardingWizard()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: onboarded)
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
