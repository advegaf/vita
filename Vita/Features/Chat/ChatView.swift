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
    @AppStorage("vita.weightUnit") private var weightUnitRaw = WeightUnit.lb.rawValue

    @State private var net = Connectivity.shared
    @State private var input = ""
    @State private var streamingText = ""
    @State private var isStreaming = false
    @State private var pendingSuggestions: [PendingSuggestion] = []
    @State private var retryInput: ChatInput?
    @State private var streamTask: Task<Void, Never>?
    @State private var health: HealthSnapshot?
    @State private var editDraft: DoseDraft?
    @FocusState private var inputFocused: Bool

    private var bySlug: [String: CatalogCompound] {
        Dictionary(compounds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var isThreadEmpty: Bool { messages.isEmpty && !isStreaming && streamingText.isEmpty }

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
        .toolbar(inputFocused ? .hidden : .automatic, for: .tabBar)
        .sheet(item: $editDraft) { d in
            let c = bySlug[d.compoundSlug]
            DoseSetupSheet(draft: d, rangeText: c?.doseRangeText, about: c?.about)
        }
        .task {
            if health == nil, HealthKitService.isAvailable {
                health = await HealthKitService.shared.snapshot()
            }
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_CHAT_DEMO"] == "1", messages.isEmpty {
                send("What can I add for better tanning?")
            }
            if ProcessInfo.processInfo.environment["VITA_CHAT_FOCUS"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                inputFocused = true
            }
            #endif
        }
        .onDisappear { streamTask?.cancel() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ScreenHeader(eyebrow: "Chat", title: "Ask about your stack.")
            Spacer()
            Menu {
                Button(role: .destructive, action: clearChat) {
                    Label("Clear chat", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                    .frame(width: 38, height: 38).background(.regularMaterial, in: Circle())
            }
            .disabled(messages.isEmpty)
            .opacity(messages.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, VT.sSection).padding(.top, 8).padding(.bottom, 4)
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
                    if isStreaming || !streamingText.isEmpty {
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
            .onChange(of: streamingText) { _, _ in scrollToBottom(proxy) }
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
                    .font(.system(size: 16)).foregroundStyle(.white)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .background(VT.ink, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        } else {
            assistantBubble(text: text, suggestions: suggestions, streaming: false)
        }
    }

    private var liveRow: some View {
        assistantBubble(text: streamingText, suggestions: pendingSuggestions, streaming: true)
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
            if retryInput != nil && !streaming {
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
        // No opaque fill: the input pill floats on the app canvas, so nothing is
        // painted behind the keyboard (just the standard iOS keyboard + canvas).
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
                    .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(canSend ? VT.ink : VT.ink.opacity(0.25), in: Circle())
            }
            .buttonStyle(.plain).disabled(!canSend)
        }
    }

    private var canSend: Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming && net.isOnline
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

    private func stackLines() -> [String] {
        items.map { item in
            let cadence = item.cadenceLabel.isEmpty ? "no schedule set" : item.cadenceLabel
            return "\(item.displayName) — \(item.doseText) — \(cadence)"
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
        guard !text.isEmpty, !isStreaming, net.isOnline else { return }
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
        try? context.save()

        let diaryLine = DiaryGrounding.summaryLine(
            entries: diaryEntries, metrics: bodyMetrics,
            weightUnit: WeightUnit(rawValue: weightUnitRaw) ?? .lb)
        let labsLine = LabGrounding.summaryLine(panels: LabService(context: context).panels())
        let chatInput = ChatInput(turns: turns, catalog: summaries(), goals: goals,
                                  stackLines: stackLines(), profile: profileInput(), health: health,
                                  diaryLine: diaryLine, labsLine: labsLine)
        startStreaming(chatInput)
    }

    private func startStreaming(_ chatInput: ChatInput) {
        isStreaming = true
        streamingText = ""
        pendingSuggestions = []
        retryInput = nil
        let svc = ClaudeServiceFactory.make()
        streamTask = Task {
            do {
                for try await event in svc.streamChat(chatInput) {
                    switch event {
                    case .text(let t):
                        streamingText += t
                    case .suggestion(let action, let slug, _):
                        if let s = validate(action: action, slug: slug),
                           !pendingSuggestions.contains(where: { $0.slug == s.slug }) {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                                pendingSuggestions.append(s)
                            }
                        }
                    case .finished:
                        break
                    }
                }
                finalizeAssistant()
            } catch {
                // Keep the partial reply visible; offer retry.
                retryInput = chatInput
                isStreaming = false
            }
        }
    }

    private func finalizeAssistant() {
        defer { isStreaming = false; streamingText = ""; pendingSuggestions = [] }
        let body = ChatText.sanitize(streamingText.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !body.isEmpty || !pendingSuggestions.isEmpty else { return }
        let msg = ChatMessage()
        msg.roleRaw = "assistant"
        msg.text = body
        msg.suggestionSlugs = pendingSuggestions.map(\.slug)
        msg.suggestionActions = pendingSuggestions.map(\.action)
        context.insert(msg)
        try? context.save()
    }

    private func retry() {
        guard let chatInput = retryInput else { return }
        retryInput = nil
        startStreaming(chatInput)
    }

    private func clearChat() {
        streamTask?.cancel()
        isStreaming = false; streamingText = ""; pendingSuggestions = []; retryInput = nil
        for m in messages { context.delete(m) }
        try? context.save()
    }

    // MARK: Suggestion validation + open

    /// A suggestion is valid only if it maps to a real action: add a catalog
    /// compound not in the stack, or adjust one already in it.
    private func validate(action: String, slug: String) -> PendingSuggestion? {
        guard let c = bySlug[slug] else { return nil }
        let stackSlugs = Set(items.map(\.compoundSlug))
        guard ChatSuggestion.isValid(action: action, slug: slug,
                                     catalogSlugs: Set(bySlug.keys), stackSlugs: stackSlugs)
        else { return nil }
        return PendingSuggestion(action: action, slug: slug, name: c.name, reason: "")
    }

    private func suggestions(for m: ChatMessage) -> [PendingSuggestion] {
        var out: [PendingSuggestion] = []
        for (i, slug) in m.suggestionSlugs.enumerated() {
            let action = i < m.suggestionActions.count ? m.suggestionActions[i] : "add"
            if let v = validate(action: action, slug: slug),
               !out.contains(where: { $0.slug == v.slug }) {
                out.append(v)
            }
        }
        return out
    }

    private func openSuggestion(_ s: PendingSuggestion) {
        let svc = StackService(context: context)
        if s.action == "add", let c = bySlug[s.slug] {
            editDraft = svc.draft(for: c)
        } else if s.action == "adjust", let item = items.first(where: { $0.compoundSlug == s.slug }) {
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
}

// ThinkingDots now lives in DesignSystem/Components/Misc.swift (shared with onboarding).
