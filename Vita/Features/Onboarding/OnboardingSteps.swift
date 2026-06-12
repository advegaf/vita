import SwiftUI
import SwiftData

// MARK: - Shared chrome

/// A standard onboarding step: scrollable content + a docked charcoal Continue pill,
/// with an optional Skip.
private struct StepScaffold<Content: View>: View {
    var eyebrow: String
    var title: String
    var subtitle: String? = nil
    var continueTitle: String = "Continue"
    var canContinue: Bool = true
    var onContinue: () -> Void
    var onSkip: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sCardGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(eyebrow)
                            .font(.system(size: 12, weight: .medium)).tracking(0.4)
                            .textCase(.uppercase).foregroundStyle(VT.micro)
                        Text(title).vtHeadlineStyle()
                        if let subtitle {
                            Text(subtitle).font(.system(size: 16)).foregroundStyle(VT.body)
                                .padding(.top, 2)
                        }
                    }
                    .padding(.top, 8)
                    content()
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: 10) {
                CharcoalPillButton(title: continueTitle, action: onContinue)
                    .opacity(canContinue ? 1 : 0.4)
                    .allowsHitTesting(canContinue)
                if let onSkip {
                    Button("Skip for now", action: onSkip)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.micro)
                }
            }
            .padding(.horizontal, VT.sSection).padding(.bottom, 8)
        }
    }
}

// MARK: - Welcome / consent

struct WelcomeView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(spacing: VT.sSection) {
            Spacer()
            VitaWordmark(size: 40, weight: .heavy, relativeTo: .largeTitle)
            VStack(spacing: 8) {
                Text("Track your peptides.\nLearn as you go.")
                    .font(VFont.display(24, weight: .bold, relativeTo: .title))
                    .multilineTextAlignment(.center).foregroundStyle(VT.ink)
                    .lineSpacing(2)
            }
            Spacer()
            VStack(spacing: 14) {
                Text("Educational only, not medical advice. Always discuss your plan with a clinician.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                CharcoalPillButton(title: "I understand, continue") {
                    let settings = CatalogStore.fetchOrCreateSettings(context)
                    let p = CatalogStore.fetchOrCreateProfile(context, settings: settings)
                    p.consentedAt = Date(); try? context.save()
                    model.advance()
                }
                .padding(.horizontal, VT.sSection)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Goals

struct GoalsView: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepScaffold(eyebrow: "Step 1", title: "What are your goals?",
                     subtitle: "Pick at least one. They shape your suggestions.",
                     canContinue: model.canContinue,
                     onContinue: model.advance) {
            VStack(spacing: VT.sCardGap) {
                ForEach(GoalKind.allCases, id: \.self) { goal in
                    goalCard(goal)
                }
            }
        }
    }

    private func goalCard(_ goal: GoalKind) -> some View {
        let on = model.selectedGoals.contains(goal)
        return Button {
            if on { model.selectedGoals.remove(goal) } else { model.selectedGoals.insert(goal) }
            Haptics.press()
        } label: {
            HStack(spacing: 12) {
                Text(goal.label)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                Spacer()
                ZStack {
                    Circle().stroke(on ? Color.clear : VT.body.opacity(0.3), lineWidth: 2)
                    Circle().fill(VT.ink).opacity(on ? 1 : 0)
                    if on {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 26, height: 26)
            }
            .padding(.horizontal, 18).padding(.vertical, 18)
            .vtCard()
        }
        .buttonStyle(.plain)
        .animation(VMotion.pinCommit, value: on)
    }
}

// MARK: - Labs placeholder

struct LabsPlaceholderView: View {
    @Bindable var model: OnboardingModel
    @State private var showScan = false
    @State private var saved = false

    var body: some View {
        StepScaffold(eyebrow: "Step 3", title: "Import your labs?",
                     subtitle: "Scan your bloodwork so Vita can factor your numbers in. Optional.",
                     continueTitle: "Continue", canContinue: true,
                     onContinue: model.advance, onSkip: model.advance) {
            VStack(alignment: .leading, spacing: 12) {
                // Mirrors the Apple Health step's connected state, then moves on.
                Image(systemName: saved ? "checkmark.seal.fill" : "doc.text.viewfinder")
                    .font(.system(size: 34)).foregroundStyle(saved ? VT.why : VT.dose)
                Text(saved
                     ? "Labs imported."
                     : "Take a photo or import a PDF of recent labs. Vita reads the values for you to review before anything is saved.")
                    .font(.system(size: 16)).foregroundStyle(VT.body).lineSpacing(3)
                if !saved {
                    Button { showScan = true } label: {
                        Text("Scan labs →").font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.dose)
                    }
                    .buttonStyle(.plain)
                }
                Text("Educational, not medical advice.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
        }
        .sheet(isPresented: $showScan) {
            LabScanFlow(offersChatReview: false, onSaved: {
                withAnimation(.easeInOut(duration: 0.2)) { saved = true }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    // Don't double-advance if Continue was tapped during the beat.
                    guard model.step == .labs else { return }
                    model.advance()
                }
            })
        }
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Bindable var model: OnboardingModel
    var onFinish: () -> Void
    @Environment(\.modelContext) private var context

    var body: some View {
        StepScaffold(eyebrow: "Last step", title: "Reminders to pin?",
                     subtitle: nil, continueTitle: "Enable reminders", canContinue: true,
                     onContinue: enable, onSkip: finish) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 34)).foregroundStyle(VT.timing)
                Text("Get a calm nudge when a dose is due, so you never miss your timing. You can log right from the notification.")
                    .font(.system(size: 16)).foregroundStyle(VT.body).lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
        }
    }

    private func enable() {
        Task {
            let granted = await NotificationService.requestPermission()
            let settings = CatalogStore.fetchOrCreateSettings(context)
            settings.notificationsEnabled = granted
            try? context.save()
            finish()
        }
    }
    private func finish() { onFinish() }
}
