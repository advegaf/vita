import SwiftUI
import SwiftData

enum OnboardingStep: Int, CaseIterable {
    case welcome, goals, peptides, labs, health, generating, review, notifications

    /// Steps shown in the progress bar (welcome + generating are not "choices").
    static var progressSteps: [OnboardingStep] { [.goals, .peptides, .labs, .health, .review, .notifications] }
}

/// Drives the onboarding wizard: current step + accumulated selections.
@MainActor
@Observable
final class OnboardingModel {
    var step: OnboardingStep = .welcome
    var selectedGoals: Set<GoalKind> = []

    /// Apple Health vitals captured on the Health step (nil if skipped/unavailable).
    var healthSnapshot: HealthSnapshot?
    /// Set when protocol generation fell back to the rule-based starter (no key /
    /// network / valid output) so Review can show a calm "Built offline" note.
    var builtOffline = false

    init() {
        #if DEBUG
        // Debug-only: jump to a step for screenshots, e.g. VITA_ONB_STEP=goals.
        if let raw = ProcessInfo.processInfo.environment["VITA_ONB_STEP"] {
            switch raw {
            case "goals": step = .goals
            case "peptides": step = .peptides; selectedGoals = [.fatLoss, .recoveryHealing]
            case "labs": step = .labs
            case "health": step = .health; selectedGoals = [.fatLoss, .recoveryHealing]
            case "generating": step = .generating; selectedGoals = [.fatLoss, .recoveryHealing]
            case "review": step = .review; selectedGoals = [.fatLoss, .recoveryHealing]
            case "notifications": step = .notifications
            default: break
            }
        }
        #endif
    }

    var canContinue: Bool {
        switch step {
        case .goals: return !selectedGoals.isEmpty   // ≥1 goal required
        default: return true
        }
    }

    func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = next }
        }
    }

    func back() {
        if let prev = OnboardingStep(rawValue: step.rawValue - 1) {
            withAnimation(.easeInOut(duration: 0.25)) { step = prev }
        }
    }

    /// Progress 0...1 across the choice steps (welcome=0, finish=1).
    var progress: Double {
        guard let idx = OnboardingStep.progressSteps.firstIndex(where: { $0.rawValue >= step.rawValue })
        else { return 1 }
        return Double(idx) / Double(OnboardingStep.progressSteps.count - 1)
    }
}
