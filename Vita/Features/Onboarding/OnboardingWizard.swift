import SwiftUI
import SwiftData

/// Full-screen onboarding wizard. Welcome → Goals → Peptides → Labs → Generating
/// → Review → Notifications, then sets `onboardedAt` and the app shows the tabs.
struct OnboardingWizard: View {
    @Environment(\.modelContext) private var context
    @State private var model = OnboardingModel()

    var body: some View {
        ZStack {
            VT.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                stepView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if model.step != .welcome && model.step != .generating {
            HStack(spacing: 12) {
                if model.step.rawValue > OnboardingStep.goals.rawValue {
                    Button { model.back() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                            .frame(width: 36, height: 36).background(.regularMaterial, in: Circle())
                    }.buttonStyle(.plain)
                }
                OnboardingProgressBar(progress: model.progress)
            }
            .padding(.horizontal, VT.sSection).padding(.top, 8)
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch model.step {
        case .welcome:       WelcomeView(model: model)
        case .goals:         GoalsView(model: model)
        case .peptides:      OnboardingPeptidesView(model: model)
        case .labs:          LabsPlaceholderView(model: model)
        case .health:        HealthConnectView(model: model)
        case .generating:    GeneratingView(model: model)
        case .review:        ReviewView(model: model)
        case .notifications: NotificationsView(model: model, onFinish: finish)
        }
    }

    private func finish() {
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        profile.selectedGoalKinds = model.selectedGoals.map(\.rawValue)
        profile.onboardedAt = Date()
        try? context.save()
        NotificationManager.rebuild(context: context)   // schedule reminders for the new stack
    }
}

/// Slim progress bar (thin fill on a track).
struct OnboardingProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(VT.ink.opacity(0.1))
                Capsule().fill(VT.ink)
                    .frame(width: max(8, geo.size.width * progress))
            }
        }
        .frame(height: 5)
    }
}
