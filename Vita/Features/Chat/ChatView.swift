import SwiftUI
import SwiftData

/// Grounded, streaming chat (M3b). You ask about your stack; vita answers,
/// streamed from Claude Opus 4.8 with the cached catalog/safety prefix + your
/// live context, and can suggest add/adjust stack actions you confirm in the
/// dose sheet. Editorial style: you = ink pill, vita = plain text on canvas.
struct ChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query(sort: \CatalogCompound.name) private var compounds: [CatalogCompound]
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex)]) private var items: [ProtocolItem]
    @Query private var profiles: [UserProfile]
    @Query private var diaryEntries: [DiaryEntry]
    @Query private var bodyMetrics: [BodyMetric]
    @Query private var doseLogs: [DoseLog]
    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue

    @State private var net = Connectivity.shared
    @State private var router = NotificationRouter.shared
    @State private var input = ""
    // The stream lives in the app-level session so it survives tab switches
    // (the old view-owned task was cancelled in onDisappear — replies died the
    // moment the user browsed another tab).
    @State private var session = ChatSession.shared
    @State private var health: HealthSnapshot?
    @State private var ouraSummary: OuraDailySummary?
    @State private var editDraft: DoseDraft?
    @State private var suggestedNote: String?
    @FocusState private var inputFocused: Bool

    private var bySlug: [String: CatalogCompound] {
        Dictionary(compounds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var isThreadEmpty: Bool { messages.isEmpty && !session.isStreaming && session.streamingText.isEmpty }

    var body: some View {
        ZStack {
            // Full-screen canvas behind everything (incl. the keyboard's safe area),
            // so the area revealed behind the keyboard's rounded bevels is cream,
            // not the white system background.
            VT.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                transcript
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        }
        .sheet(item: $editDraft, onDismiss: { suggestedNote = nil }) { d in
            let c = bySlug[d.compoundSlug]
            DoseSetupSheet(draft: d, rangeText: c?.doseRangeText, about: c?.about,
                           aiSuggestedNote: suggestedNote)
        }
        .onAppear { consumePendingPrompt() }
        .onDisappear { router.isChatInputFocused = false }
        .onChange(of: router.pendingChatPrompt) { _, _ in consumePendingPrompt() }
        .onChange(of: inputFocused) { _, focused in
            router.isChatInputFocused = focused
        }
        .task {
            // Unconditional refresh: connecting Apple Health in Settings or
            // onboarding must reach the very next message, not the next relaunch.
            if HealthKitService.isAvailable {
                health = await HealthKitService.shared.snapshot()
            }
            // Ring data for grounding (M49): a week is plenty for one line.
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_OURA_DEMO"] == "1" {
                ouraSummary = .demo(days: 7)
            } else if WearableAuthStore.isConnected(.oura) {
                ouraSummary = try? await OuraService().dailySummary(days: 7)
            }
            #else
            if WearableAuthStore.isConnected(.oura) {
                ouraSummary = try? await OuraService().dailySummary(days: 7)
            }
            #endif
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_CHAT_DEMO"] == "1", messages.isEmpty {
                send("How is my recovery looking this week?")
            }
            if ProcessInfo.processInfo.environment["VITA_CHAT_FOCUS"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                inputFocused = true
            }
            #endif
        }
    }

    /// Cross-links (e.g. a lab marker's "Ask vita") prefill the input; sending is
    /// always the user's tap — never automatic.
    private func consumePendingPrompt() {
        guard let prompt = router.pendingChatPrompt else { return }
        router.pendingChatPrompt = nil
        input = prompt
        inputFocused = true
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
            ScreenHeader(eyebrow: "Chat", title: "Ask about your stack.")
            Spacer()
            Menu {
                Button(role: .destructive, action: clearChat) {
                    Label("Clear chat", systemImage: "trash")
                }
            } label: {
                HeaderActionGlyph(systemName: "ellipsis")
            }
            .disabled(messages.isEmpty)
            .opacity(messages.isEmpty ? 0.4 : 1)
            .accessibilityLabel("Chat options")
        }
        .padding(.horizontal, VT.sSection).padding(.top, 20).padding(.bottom, 2)
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if isThreadEmpty { starterChips }
                    ForEach(messages) { m in
                        messageRow(role: m.roleRaw, text: m.text,
                                   suggestions: suggestions(for: m))
                    }
                    if session.isStreaming || !session.streamingText.isEmpty {
                        liveRow
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .onChange(of: messages.count) { _, _ in scrollToBottom(proxy) }
            .onChange(of: session.streamingText) { _, _ in scrollToBottom(proxy) }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func messageRow(role: String, text: String, suggestions: [PendingSuggestion]) -> some View {
        if role == "user" {
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .font(.system(size: 16)).foregroundStyle(VT.onInk)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(VT.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            assistantBubble(text: text, suggestions: suggestions, streaming: false)
        }
    }

    private var liveRow: some View {
        assistantBubble(text: session.streamingText, suggestions: session.pendingSuggestions, streaming: true)
    }

    @ViewBuilder
    private func assistantBubble(text: String, suggestions: [PendingSuggestion], streaming: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("vita")
                .font(.system(size: 12, weight: .semibold)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            if streaming && text.isEmpty {
                ThinkingDots(reduceMotion: reduceMotion, label: "vita is thinking")
            } else {
                Text(markdown(ChatText.sanitize(text)))
                    .font(.system(size: 16)).foregroundStyle(VT.ink).lineSpacing(3)
                    .textSelection(.enabled)
            }
            ForEach(suggestions, id: \.slug) { suggestionChip($0) }
            if session.retryInput != nil && !streaming {
                Button(action: retry) {
                    Label("Couldn't reach vita. Tap to retry.", systemImage: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.body)
                }
                .buttonStyle(.plain).padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func suggestionChip(_ s: PendingSuggestion) -> some View {
        Button {
            Haptics.press()
            openSuggestion(s)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: s.action == "add" ? "plus.circle.fill" : "slider.horizontal.3")
                Text(s.action == "add" ? "Add \(s.name)" : "Adjust \(s.name)")
            }
            .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(VT.dose.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
        .transition(reduceMotion ? .opacity : .scale.combined(with: .opacity))
    }

    // MARK: Starter chips

    private var starterChips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try asking")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
            ForEach(starterPrompts, id: \.self) { p in
                Button { send(p) } label: {
                    Text(p)
                        .font(.system(size: 15, weight: .medium)).foregroundStyle(VT.ink)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(VT.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VT.hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 4)
    }

    private var starterPrompts: [String] {
        if let first = items.first {
            var out = ["Why am I taking \(first.displayName)?",
                       "Is my \(first.displayName) timing right?"]
            if let g = goals.first { out.append("What helps \(g.label.lowercased())?") }
            else { out.append("What pairs well for recovery?") }
            return out
        }
        return ["What is a peptide?",
                "How does reconstitution work?",
                "What's studied for recovery?"]
    }

    // MARK: Footer (disclaimer + input)

    private var footer: some View {
        VStack(spacing: 8) {
            if !net.isOnline {
                Text("You're offline. Chat needs a connection.")
                    .font(.system(size: 13)).foregroundStyle(VT.body)
            }
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
            inputBar
        }
        .padding(.horizontal, VT.sSection).padding(.top, 6).padding(.bottom, 8)
        // Canvas fade under the footer: scrolled transcript dims out beneath the
        // disclaimer/input instead of bleeding through at full strength, while
        // the top edge stays soft so the pill still reads as floating.
        .background {
            LinearGradient(stops: [.init(color: VT.canvas.opacity(0), location: 0),
                                   .init(color: VT.canvas, location: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask about your stack…", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .font(.system(size: 16)).foregroundStyle(VT.ink)
                .focused($inputFocused)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(VT.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VT.hairline, lineWidth: 1))
            Button(action: { send(input) }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(VT.onInk)
                    .frame(width: 38, height: 38)
                    .background(canSend ? VT.ink : VT.ink.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain).disabled(!canSend)
            .accessibilityLabel("Send")
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !session.isStreaming && net.isOnline
    }

    // MARK: Grounding

    private var goals: [GoalKind] {
        (profiles.first?.selectedGoalKinds ?? []).compactMap { GoalKind(rawValue: $0) }
    }

    private func summaries() -> [CatalogSummary] {
        compounds.map { c in
            CatalogSummary(slug: c.slug, name: c.name, categoryRaw: c.categoryRaw,
                           rxStatusRaw: c.rxStatusRaw, doseUnitRaw: c.doseUnitRaw,
                           typicalDoseLow: c.typicalDoseLow, typicalDoseHigh: c.typicalDoseHigh,
                           route: c.primaryRoute?.label, defaultScheduleTypeRaw: c.defaultScheduleTypeRaw)
        }
    }

    /// One grounding line per stack item, now including real adherence so vita can
    /// answer "am I being consistent?" and weigh advice against actual usage.
    private func stackLines() -> [String] {
        items.map { item in
            let cadence = item.cadenceLabel.isEmpty ? "no schedule set" : item.cadenceLabel
            // " | " separators, not em dashes (dash-heavy grounding primes the
            // model to echo them back into replies).
            var line = "\(item.displayName) | \(item.doseText) | \(cadence)"
            let itemLogs = doseLogs.filter { $0.itemID == item.id }
            if item.schedule?.frequency == .prn {
                let n = Adherence.prnCount(item: item, logs: itemLogs)
                if n > 0 { line += " | used \(n)x in the last 30 days" }
            } else {
                let s = Adherence.summary(item: item, logs: itemLogs)
                if s.scheduled > 0 { line += " | logged \(s.logged) of \(s.scheduled) scheduled days in the last 30" }
            }
            return line
        }
    }

    private func profileInput() -> ProfileInput {
        guard let p = profiles.first else { return ProfileInput() }
        var age: Int?
        if let dob = p.birthDate {
            age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        }
        return ProfileInput(ageYears: age, biologicalSex: p.biologicalSexRaw, weightKg: p.weightKg)
    }

    // MARK: Send / stream

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !session.isStreaming, net.isOnline else { return }
        Haptics.press()
        inputFocused = false
        input = ""

        // Build the rolling window BEFORE inserting (so it ends with this user turn).
        var turns = messages.suffix(9).map {
            ChatTurn(role: $0.isUser ? "user" : "assistant", text: $0.text)
        }
        turns.append(ChatTurn(role: "user", text: text))

        let userMsg = ChatMessage()
        userMsg.roleRaw = "user"; userMsg.text = text
        context.insert(userMsg)
        context.saveLogged("ChatView")

        let diaryParts = [DiaryGrounding.summaryLine(
                              entries: diaryEntries, metrics: bodyMetrics,
                              weightUnit: WeightUnit(rawValue: weightUnitRaw) ?? .lb),
                          OuraGrounding.summaryLine(ouraSummary)].compactMap(\.self)
        let diaryLine = diaryParts.isEmpty ? nil : diaryParts.joined(separator: " ")
        let labsLine = LabGrounding.summaryLine(panels: LabService(context: context).panels())
        let chatInput = ChatInput(turns: turns, catalog: summaries(), goals: goals,
                                  stackLines: stackLines(), profile: profileInput(), health: health,
                                  diaryLine: diaryLine, labsLine: labsLine)
        session.send(chatInput)
    }

    private func retry() {
        session.retry()
    }

    private func clearChat() {
        session.cancelAndReset()
        // Batch delete via the shared action: iterating-and-deleting the same
        // models the live transcript is rendering can trap mid-render.
        SettingsActions(context: context).clearChat()
    }

    // MARK: Suggestion validation + open

    /// A suggestion is valid only if it maps to a real action: add a catalog
    /// compound not in the stack, or adjust one already in it. A suggested dose is
    /// never trusted raw — clamped into the catalog's educational range.
    private func validate(action: String, slug: String, dose: Double? = nil) -> PendingSuggestion? {
        guard let c = bySlug[slug] else { return nil }
        let stackSlugs = Set(items.map(\.compoundSlug))
        guard ChatSuggestion.isValid(action: action, slug: slug,
                                     catalogSlugs: Set(bySlug.keys), stackSlugs: stackSlugs)
        else { return nil }
        var clamped: Double? = nil
        if var d = dose, d > 0 {
            if let lo = c.typicalDoseLow, d < lo { d = lo }
            if let hi = c.typicalDoseHigh, d > hi { d = hi }
            clamped = d
        }
        return PendingSuggestion(action: action, slug: slug, name: c.name, reason: "", dose: clamped)
    }

    private func suggestions(for m: ChatMessage) -> [PendingSuggestion] {
        var out: [PendingSuggestion] = []
        for (i, slug) in m.suggestionSlugs.enumerated() {
            let action = i < m.suggestionActions.count ? m.suggestionActions[i] : "add"
            let dose = i < m.suggestionDoses.count && m.suggestionDoses[i] > 0 ? m.suggestionDoses[i] : nil
            if let v = validate(action: action, slug: slug, dose: dose),
               !out.contains(where: { $0.slug == v.slug }) {
                out.append(v)
            }
        }
        return out
    }

    private func openSuggestion(_ s: PendingSuggestion) {
        let svc = StackService(context: context)
        if s.action == "add", let c = bySlug[s.slug] {
            var d = svc.draft(for: c)
            if let dose = s.dose {
                d.doseAmount = dose
                suggestedNote = "vita suggested \(vtFormatNumber(dose)) \(c.doseUnit.label) to start."
            }
            editDraft = d
        } else if s.action == "adjust", let item = items.first(where: { $0.compoundSlug == s.slug }) {
            if let dose = s.dose {
                suggestedNote = "vita suggested \(vtFormatNumber(dose)) \(item.doseUnit.label)."
            }
            editDraft = svc.draft(for: item)
        }
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}

/// A validated, tappable stack-action suggestion.
struct PendingSuggestion: Equatable {
    let action: String   // "add" | "adjust"
    let slug: String
    let name: String
    let reason: String
    var dose: Double? = nil   // vita's suggested starting dose, clamped to the catalog range
}

// ThinkingDots now lives in DesignSystem/Components/Misc.swift (shared with onboarding).
