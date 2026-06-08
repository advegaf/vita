import Foundation

/// Boundary the onboarding "Generating" step calls. The live service hits Claude;
/// the stub returns a canned fixture so the app is always buildable/demoable
/// without a key or network (VITA_CLAUDE_STUB=1, tests, screenshots).
protocol ClaudeServiceProviding: Sendable {
    func generateProtocol(_ input: ProtocolInput) async throws -> ProtocolDTO
    func streamChat(_ input: ChatInput) -> AsyncThrowingStream<ChatStreamEvent, Error>
    func interpretLabs(_ input: LabScanInput) async throws -> LabPanelDTO
}

/// One prior turn in the rolling conversation window.
struct ChatTurn: Sendable, Equatable {
    var role: String   // "user" | "assistant"
    var text: String
}

/// Everything one chat request needs: the recent turns (last ending with the new
/// user message) + the same grounding used by protocol-gen, plus live stack lines.
struct ChatInput: Sendable, Equatable {
    var turns: [ChatTurn]
    var catalog: [CatalogSummary]
    var goals: [GoalKind]
    var stackLines: [String]
    var profile: ProfileInput
    var health: HealthSnapshot?
    var diaryLine: String? = nil    // recent check-in averages + weight trend (M8a)
    var labsLine: String? = nil     // latest panel out-of-range flags (M8b)
}

/// Live protocol generation via forced tool-use on Opus 4.8.
struct ClaudeService: ClaudeServiceProviding {
    var client = AnthropicClient()
    var maxTokens = 2048

    func generateProtocol(_ input: ProtocolInput) async throws -> ProtocolDTO {
        let system = [
            AnthropicClient.SystemBlock(text: ClaudeSchemas.catalogSystemText(input.catalog), cache: true),
            AnthropicClient.SystemBlock(
                text: ClaudeSchemas.groundingText(goals: input.goals, pickedSlugs: input.pickedSlugs,
                                                  profile: input.profile, health: input.health,
                                                  labsLine: input.labsLine),
                cache: false),
        ]
        let result = try await client.send(
            maxTokens: maxTokens,
            system: system,
            userText: ClaudeSchemas.userPrompt,
            tool: { ClaudeSchemas.emitProtocolTool },
            toolName: ClaudeSchemas.toolName)
        guard let data = result.toolInput else { throw AnthropicClient.AnthropicError.noToolUse }
        #if DEBUG
        NSLog("vita-claude: protocol decoded, cache_read=%d tokens", result.cacheReadTokens)
        #endif
        do {
            return try JSONDecoder().decode(ProtocolDTO.self, from: data)
        } catch {
            throw AnthropicClient.AnthropicError.decode
        }
    }

    var labsMaxTokens = 4096          // comprehensive panels (40-60 markers) overflow 2048

    func interpretLabs(_ input: LabScanInput) async throws -> LabPanelDTO {
        let system = [AnthropicClient.SystemBlock(text: ClaudeSchemas.labsSystemText(), cache: true)]
        let isPDF = input.mediaType == "application/pdf"
        // Hybrid: native `document` block for small clean PDFs (keeps the text layer);
        // rasterize big / many-page PDFs up front; and if a native PDF is rejected (4xx),
        // fall back to rasterized images once.
        let rasterizeFirst = isPDF &&
            (input.imageData.count > 4_000_000 || LabImageEncoder.pdfPageCount(input.imageData) > 5)
        let primary: [(base64: String, mediaType: String)] = {
            if rasterizeFirst { let r = rasterized(input); if !r.isEmpty { return r } }
            return [(input.imageData.base64EncodedString(), input.mediaType)]
        }()
        do {
            return try await run(system: system, attachments: primary)
        } catch let e as AnthropicClient.AnthropicError {
            #if DEBUG
            NSLog("vita-labs: error %@", String(describing: e))
            #endif
            if isPDF, !rasterizeFirst, case .http = e {
                let imgs = rasterized(input)
                if !imgs.isEmpty { return try await run(system: system, attachments: imgs) }
            }
            throw e
        }
    }

    private func rasterized(_ input: LabScanInput) -> [(base64: String, mediaType: String)] {
        LabImageEncoder.imagesFromPDF(input.imageData).map { ($0.base64EncodedString(), "image/jpeg") }
    }

    private func run(system: [AnthropicClient.SystemBlock],
                     attachments: [(base64: String, mediaType: String)]) async throws -> LabPanelDTO {
        let result = try await client.sendVision(
            maxTokens: labsMaxTokens, system: system, userText: ClaudeSchemas.labsUserPrompt,
            attachments: attachments, tool: { ClaudeSchemas.interpretLabsTool },
            toolName: ClaudeSchemas.labsToolName)
        guard let data = result.toolInput else { throw AnthropicClient.AnthropicError.noToolUse }
        #if DEBUG
        NSLog("vita-labs: interpreted via %d attachment(s), cache_read=%d", attachments.count, result.cacheReadTokens)
        #endif
        do { return try JSONDecoder().decode(LabPanelDTO.self, from: data) }
        catch { throw AnthropicClient.AnthropicError.decode }
    }

    func streamChat(_ input: ChatInput) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let system = [
            AnthropicClient.SystemBlock(text: ClaudeSchemas.chatSystemText(input.catalog), cache: true),
            AnthropicClient.SystemBlock(
                text: ClaudeSchemas.chatGroundingText(goals: input.goals, profile: input.profile,
                                                      health: input.health, stackLines: input.stackLines,
                                                      diaryLine: input.diaryLine, labsLine: input.labsLine),
                cache: false),
        ]
        let messages = Self.windowedMessages(input.turns)
        return client.streamChat(maxTokens: 2048, system: system, messages: messages,
                                 tool: { ClaudeSchemas.suggestStackActionTool })
    }

    /// The window must start with a user turn (API requirement); trim leading
    /// assistant turns and map to wire messages. Pure + testable.
    static func windowedMessages(_ turns: [ChatTurn]) -> [[String: String]] {
        Array(turns.drop(while: { $0.role != "user" }))
            .map { ["role": $0.role, "content": $0.text] }
    }
}

/// Pure validation for a model-suggested stack action: the slug must be in the
/// catalog, and 'add' requires it NOT already in the stack while 'adjust' requires
/// it IS. Extracted so it's unit-testable away from the view.
enum ChatSuggestion {
    static func isValid(action: String, slug: String,
                        catalogSlugs: Set<String>, stackSlugs: Set<String>) -> Bool {
        guard catalogSlugs.contains(slug) else { return false }
        switch action {
        case "add": return !stackSlugs.contains(slug)
        case "adjust": return stackSlugs.contains(slug)
        default: return false
        }
    }
}

/// Chooses the live service or the stub. No key (or no network in tests) is fine:
/// the live path throws and the caller falls back to the rule-based starter.
enum ClaudeServiceFactory {
    static func make() -> ClaudeServiceProviding {
        #if DEBUG
        if ProcessInfo.processInfo.environment["VITA_CLAUDE_STUB"] == "1" {
            return StubClaudeService()
        }
        #endif
        return ClaudeService()
    }
}

// MARK: - Validation + mapping (pure, testable)

extension ClaudeService {
    /// Validates the model's output against the catalog and maps it to commit-ready
    /// drafts. Drops unknown slugs; clamps doses into the educational range; coerces
    /// the unit to the catalog's; backfills weekday/time defaults. Identity (name,
    /// category, ℞) always comes from the catalog, never the model.
    static func buildDrafts(from dto: ProtocolDTO, catalog: [CatalogSummary]) -> [DoseDraft] {
        let bySlug = Dictionary(catalog.map { ($0.slug.lowercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<String>()
        var out: [DoseDraft] = []

        for item in dto.items {
            let key = item.compoundSlug.lowercased()
            guard let c = bySlug[key], !seen.contains(key) else { continue }
            seen.insert(key)

            var d = DoseDraft(compoundSlug: c.slug, displayName: c.name)
            d.categoryRaw = c.categoryRaw
            d.rxStatusRaw = c.rxStatusRaw
            d.doseUnit = c.doseUnit                                  // trust catalog unit
            d.doseAmount = clamp(item.doseAmount, c.typicalDoseLow, c.typicalDoseHigh)
            d.frequency = Frequency(rawValue: item.frequency) ?? .daily

            if d.frequency == .prn {
                d.times = []
                d.weekdays = []
            } else {
                let times = item.timesMinutes.filter { (0...1439).contains($0) }
                d.times = times.isEmpty ? [DayBlock.morning.defaultMinutes] : times.sorted()
                if d.frequency == .weekly {
                    let wds = item.weekdays.filter { (1...7).contains($0) }
                    d.weekdays = wds.isEmpty ? [2] : Set(wds).sorted().reduce(into: Set<Int>()) { $0.insert($1) }
                } else {
                    d.weekdays = []
                }
            }
            out.append(d)
        }
        return out
    }

    private static func clamp(_ v: Double, _ lo: Double?, _ hi: Double?) -> Double {
        var x = max(0, v)
        if let lo, x < lo { x = lo }
        if let hi, x > hi { x = hi }
        return x
    }
}

// MARK: - Stub

/// Canned, deterministic protocol for tests/screenshots/no-network. Tailors a
/// tiny set to the user's goals so the demo looks grounded.
struct StubClaudeService: ClaudeServiceProviding {
    func generateProtocol(_ input: ProtocolInput) async throws -> ProtocolDTO {
        try? await Task.sleep(nanoseconds: 250_000_000)
        let slugs = StarterSuggester.slugs(for: input.goals).isEmpty
            ? ["bpc-157"] : StarterSuggester.slugs(for: input.goals)
        let bySlug = Dictionary(input.catalog.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
        let items: [ProtocolDTO.Item] = slugs.compactMap { slug in
            guard let c = bySlug[slug] else { return nil }
            let dose = midpoint(c) ?? 250
            let isWeekly = slug.contains("semaglutide") || slug.contains("tirzepatide")
            return ProtocolDTO.Item(
                compoundSlug: slug,
                doseAmount: dose,
                doseUnit: c.doseUnitRaw,
                frequency: isWeekly ? "weekly" : "daily",
                weekdays: isWeekly ? [2] : [],
                timesMinutes: [DayBlock.morning.defaultMinutes],
                rationale: "Commonly explored for your goals. Educational only.")
        }
        return ProtocolDTO(
            disclaimer: "Educational, not medical advice. Discuss any protocol with your clinician.",
            items: items)
    }

    func interpretLabs(_ input: LabScanInput) async throws -> LabPanelDTO {
        try? await Task.sleep(nanoseconds: 250_000_000)
        return LabPanelDTO(
            panelDate: "2026-05-20",
            sourceLabName: "Quest Diagnostics",
            values: [
                .init(markerKey: "glucose_fasting", name: "Glucose, Fasting", value: 104, unit: "mg/dL", refLow: 70, refHigh: 99, flagRaw: "H"),
                .init(markerKey: "hdl_cholesterol", name: "HDL Cholesterol", value: 41, unit: "mg/dL", refLow: 40, refHigh: nil),
                .init(markerKey: "ldl_cholesterol", name: "LDL Cholesterol", value: 138, unit: "mg/dL", refLow: nil, refHigh: 100, flagRaw: "H"),
                .init(markerKey: "triglycerides", name: "Triglycerides", value: 90, unit: "mg/dL", refLow: nil, refHigh: 150),
                .init(markerKey: "tsh", name: "TSH", value: 2.1, unit: "mIU/L", refLow: 0.4, refHigh: 4.0),
                .init(markerKey: "vitamin_d", name: "Vitamin D, 25-OH", value: 22, unit: "ng/mL", refLow: 30, refHigh: 100, flagRaw: "L"),
                .init(markerKey: "testosterone_total", name: "Testosterone, Total", value: 612, unit: "ng/dL", refLow: 264, refHigh: 916),
            ],
            summary: "A few values sit outside the printed ranges: fasting glucose and LDL read high, vitamin D reads low. Educational only.",
            disclaimer: "Educational, not medical advice. Discuss results with your clinician.")
    }

    private func midpoint(_ c: CatalogSummary) -> Double? {
        if let lo = c.typicalDoseLow, let hi = c.typicalDoseHigh { return (lo + hi) / 2 }
        return c.typicalDoseLow ?? c.typicalDoseHigh
    }

    func streamChat(_ input: ChatInput) -> AsyncThrowingStream<ChatStreamEvent, Error> {
        let q = (input.turns.last(where: { $0.role == "user" })?.text ?? "").lowercased()
        let inCatalog = Set(input.catalog.map(\.slug))

        // Pick recommended slugs by keyword (only ones present in the catalog), so
        // the demo shows one Add chip per recommendation.
        let recommend: [String] = {
            var r: [String] = []
            if q.contains("tan") { r = ["melanotan-1", "melanotan-2"] }
            else if q.contains("recover") || q.contains("heal") || q.contains("pair") { r = ["tb-500", "bpc-157"] }
            else if q.contains("add") || q.contains("recommend") || q.contains("suggest") { r = ["bpc-157"] }
            return r.filter { inCatalog.contains($0) }
        }()

        let reply = recommend.isEmpty
            ? "Happy to talk it through. Tell me a goal and I will point you at what is worth a look."
            : "For that, a couple of options worth a look. Tap one to set it up and you can tweak the dose before it lands in your stack."

        return AsyncThrowingStream { continuation in
            let task = Task {
                for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                    try? await Task.sleep(nanoseconds: 28_000_000)
                    if Task.isCancelled { continuation.finish(); return }
                    continuation.yield(.text(String(word) + " "))
                }
                for slug in recommend {
                    continuation.yield(.suggestion(action: "add", slug: slug, reason: "A fit for your goal."))
                }
                continuation.yield(.finished)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
