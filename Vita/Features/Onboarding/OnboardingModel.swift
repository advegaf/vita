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
    /// Claude is refining the starter in the background (Review's charcoal pill
    /// shows "Refining with AI…"; tapping it cancels and proceeds with the starter).
    var refining = false
    /// The in-flight refine task, so Review's pill (and a re-entered Generating
    /// step) can cancel it. Cleared when the task finishes.
    var refineTask: Task<Void, Never>?
    /// Claude's plan replaced the starter (Review shows "Refined with AI.").
    var refinedByAI = false
    /// Refine suggestions for the USER'S OWN items (never auto-applied): itemID →
    /// Claude's draft. Review renders a tappable "vita suggests …" line per entry.
    var refineSuggestions: [UUID: DoseDraft] = [:]
    /// Step 2's pushed-detail navigation path (compound slugs). Lives here so
    /// `back()` can pop an open detail instead of leaving the step — the wizard
    /// chevron is the ONLY back button (the pushed detail hides the system one).
    var peptidesPath: [String] = []

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
        // Render Step 2 with a pushed compound detail, e.g. VITA_ONB_DETAIL=bpc-157.
        if let slug = ProcessInfo.processInfo.environment["VITA_ONB_DETAIL"] {
            step = .peptides
            selectedGoals = [.fatLoss, .recoveryHealing]
            peptidesPath = [slug]
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
        // Layered: with a peptide detail open on Step 2, back closes the detail.
        if step == .peptides, !peptidesPath.isEmpty {
            peptidesPath.removeLast()
            return
        }
        // Generating auto-advances, so backing into it would just bounce the user
        // straight back to Review. Skip over it; going FORWARD through it again
        // (Health → Continue) legitimately re-runs the refine.
        if step == .review {
            withAnimation(.easeInOut(duration: 0.25)) { step = .health }
            return
        }
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
