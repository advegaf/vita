import Foundation
import SwiftData

/// App-level chat streaming session. The stream and its finalize-and-save belong
/// HERE, not to ChatView, so a reply keeps arriving and lands in SwiftData even
/// if the user browses other tabs mid-stream (the view only observes this).
/// Mirrors NotificationRouter's pattern: a @MainActor singleton whose container
/// is set once in VitaApp.
@MainActor
@Observable
final class ChatSession {
    static let shared = ChatSession()
    var container: ModelContainer?

    var isStreaming = false
    var streamingText = ""
    var pendingSuggestions: [PendingSuggestion] = []
    var retryInput: ChatInput?
    private var streamTask: Task<Void, Never>?

    func send(_ input: ChatInput) {
        isStreaming = true
        streamingText = ""
        pendingSuggestions = []
        retryInput = nil
        let svc = ClaudeServiceFactory.make()
        streamTask = Task { @MainActor in
            do {
                for try await event in svc.streamChat(input) {
                    switch event {
                    case .text(let t):
                        streamingText += t
                    case .suggestion(let action, let slug, _, let dose):
                        if let s = validate(action: action, slug: slug, dose: dose),
                           !pendingSuggestions.contains(where: { $0.slug == s.slug }) {
                            pendingSuggestions.append(s)
                        }
                    case .finished:
                        break
                    }
                }
                finalize(input: input)
            } catch {
                // Keep the partial reply visible; offer retry.
                retryInput = input
                isStreaming = false
            }
        }
    }

    func retry() {
        guard let input = retryInput else { return }
        retryInput = nil
        send(input)
    }

    /// "Clear chat" or any hard reset: stop the stream, drop transient state.
    func cancelAndReset() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        streamingText = ""
        pendingSuggestions = []
        retryInput = nil
    }

    private func finalize(input: ChatInput) {
        defer { isStreaming = false; streamingText = ""; pendingSuggestions = [] }
        guard let context = container?.mainContext else { return }
        let body = ChatText.sanitize(streamingText.trimmingCharacters(in: .whitespacesAndNewlines))
        // An EMPTY completed stream is a failure, not a success: surface retry
        // instead of silently saving nothing.
        guard !body.isEmpty || !pendingSuggestions.isEmpty else {
            retryInput = input
            return
        }
        let msg = ChatMessage()
        msg.roleRaw = "assistant"
        msg.text = body
        msg.suggestionSlugs = pendingSuggestions.map(\.slug)
        msg.suggestionActions = pendingSuggestions.map(\.action)
        msg.suggestionDoses = pendingSuggestions.map { $0.dose ?? -1 }
        context.insert(msg)
        context.saveLogged("ChatSession")
    }

    /// Event-time validation against the LIVE catalog + stack (the session can't
    /// rely on a view's @Query). Same rules as ever: real action only, dose
    /// clamped into the catalog's educational range, never trusted raw.
    private func validate(action: String, slug: String, dose: Double? = nil) -> PendingSuggestion? {
        guard let context = container?.mainContext else { return nil }
        let compounds = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        guard let c = compounds.first(where: { $0.slug == slug }) else { return nil }
        let stackSlugs = Set(((try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []).map(\.compoundSlug))
        guard ChatSuggestion.isValid(action: action, slug: slug,
                                     catalogSlugs: Set(compounds.map(\.slug)),
                                     stackSlugs: stackSlugs) else { return nil }
        var clamped: Double? = nil
        if var d = dose, d > 0 {
            if let lo = c.typicalDoseLow, d < lo { d = lo }
            if let hi = c.typicalDoseHigh, d > hi { d = hi }
            clamped = d
        }
        return PendingSuggestion(action: action, slug: slug, name: c.name, reason: "", dose: clamped)
    }
}
