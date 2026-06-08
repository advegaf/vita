import Foundation

/// The forced-tool schema + the two-block system prompt (cached catalog/safety
/// prefix + uncached per-user grounding). Pure string/dictionary builders so the
/// prompt assembly is testable and the cache prefix stays byte-stable.
enum ClaudeSchemas {
    static let toolName = "emit_protocol"

    /// `emit_protocol` — strict JSON, additionalProperties:false. Numbers are
    /// unbounded here (strict mode can't constrain them) and clamped client-side.
    static var emitProtocolTool: [String: Any] {
        [
            "name": toolName,
            "strict": true,
            "description": "Emit an educational starter peptide protocol grounded in the user's goals, picked peptides, profile, and Apple Health context. Use only compound_slug values from the provided catalog. Every dose is an educational range suggestion, never a prescription.",
            "input_schema": [
                "type": "object",
                "additionalProperties": false,
                "required": ["disclaimer", "items"],
                "properties": [
                    "disclaimer": [
                        "type": "string",
                        "description": "One-line educational, not-medical-advice statement.",
                    ],
                    "items": [
                        "type": "array",
                        "description": "Suggested compounds to start tracking.",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["compound_slug", "dose_amount", "dose_unit", "frequency", "weekdays", "times_minutes", "rationale"],
                            "properties": [
                                "compound_slug": ["type": "string", "description": "A slug from the catalog."],
                                "dose_amount": ["type": "number", "description": "Amount in dose_unit, within the catalog's educational range."],
                                "dose_unit": ["type": "string", "enum": ["mcg", "mg", "iu"]],
                                "frequency": ["type": "string", "enum": ["daily", "eod", "weekly", "prn"]],
                                "weekdays": ["type": "array", "description": "1=Sun…7=Sat, only for weekly.", "items": ["type": "integer"]],
                                "times_minutes": ["type": "array", "description": "Clock times as minutes-from-midnight (480=8am).", "items": ["type": "integer"]],
                                "rationale": ["type": "string", "description": "Short educational reason tied to the user's goals."],
                            ],
                        ],
                    ],
                ],
            ],
        ]
    }

    static let userPrompt = "Generate a starter educational protocol now using the emit_protocol tool."

    // MARK: - Lab scan (M8b, forced vision tool)

    static let labsToolName = "interpret_labs"
    static let labsUserPrompt = "Read the attached lab report and extract its values using the interpret_labs tool."

    /// `interpret_labs` — strict JSON, additionalProperties:false (mirrors emit_protocol).
    /// The app recomputes flags from value vs range; the model's flag_raw is verbatim only.
    static var interpretLabsTool: [String: Any] {
        [
            "name": labsToolName,
            "strict": true,
            "description": "Read this lab report image or PDF and extract exactly the marker values printed on the page. Educational reading only; never diagnose or prescribe.",
            "input_schema": [
                "type": "object",
                "additionalProperties": false,
                "required": ["panel_date", "source_lab_name", "values", "summary", "disclaimer"],
                "properties": [
                    "panel_date": ["type": ["string", "null"], "description": "Collection/report date as printed, ISO-8601 (YYYY-MM-DD) if determinable, else null."],
                    "source_lab_name": ["type": ["string", "null"], "description": "Lab/provider name printed on the report, else null."],
                    "values": [
                        "type": "array",
                        "description": "One entry per marker row on the page.",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "required": ["marker_key", "name", "value", "unit", "ref_low", "ref_high", "ref_text", "flag_raw"],
                            "properties": [
                                "marker_key": ["type": "string", "description": "Normalized snake_case key, e.g. glucose_fasting, hdl_cholesterol, tsh, testosterone_total."],
                                "name": ["type": "string", "description": "Marker name exactly as printed."],
                                "value": ["type": "number", "description": "Numeric result as printed."],
                                "unit": ["type": "string", "description": "Unit as printed, e.g. mg/dL, mmol/L, ng/dL."],
                                "ref_low": ["type": ["number", "null"], "description": "Reference range low bound, else null."],
                                "ref_high": ["type": ["number", "null"], "description": "Reference range high bound, else null."],
                                "ref_text": ["type": ["string", "null"], "description": "Reference range text when not a simple low-high (e.g. '<150', 'Negative'), else null."],
                                "flag_raw": ["type": ["string", "null"], "description": "Any H/L/abnormal flag printed verbatim, else null. The app recomputes the flag from value vs range."],
                            ],
                        ],
                    ],
                    "summary": ["type": "string", "description": "2-3 sentence plain-language 'what stands out', educational, no diagnosis."],
                    "disclaimer": ["type": "string", "description": "One-line educational, not-medical-advice statement."],
                ],
            ],
        ]
    }

    /// Cached labs system prefix. NOTE: this is well under the ~4096-token Opus cache
    /// minimum so cache:true will NOT actually fire a cache read — kept for parity, harmless.
    static func labsSystemText() -> String {
        """
        You read lab reports for Vita, an educational peptide-tracking app. You are NOT a clinician and you NEVER \
        diagnose, interpret causation, or prescribe. Extract only what is printed on the page.

        Rules:
        - Transcribe each marker row exactly: name, numeric value, unit, and reference range as printed. Do not invent values, units, or ranges.
        - marker_key is a normalized snake_case identifier so the same marker matches across reports (glucose_fasting, hemoglobin_a1c, hdl_cholesterol, ldl_cholesterol, triglycerides, tsh, testosterone_total, vitamin_d, ferritin, alt, ast, creatinine, etc.). If unsure, derive it from the printed name.
        - When a value is unreadable or ambiguous, omit that row rather than guessing.
        - flag_raw is whatever H/L/abnormal marker is printed verbatim, or null. The app computes the high/low/normal flag itself from value vs reference range; do not rely on your flag.
        - summary is a short, plain, educational "what stands out" (which values sit outside the printed range). No diagnosis, no advice, no imperatives.
        - The disclaimer field is required: a one-line "Educational, not medical advice. Discuss results with your clinician." statement.
        - Never use em dashes or en dashes.
        """
    }

    // MARK: - Chat (M3b)

    static let chatToolName = "suggest_stack_action"

    /// Optional tool the chat model may call (tool_choice auto) to offer one
    /// tappable stack change. Validated client-side; nothing commits without a tap.
    static var suggestStackActionTool: [String: Any] {
        [
            "name": chatToolName,
            "description": "Surface a stack change as a tappable chip. Call this once PER compound you actually recommend the user add or adjust (so when you recommend two options, call it twice). action 'add' = a catalog compound not already in their stack; action 'adjust' = one already in their stack (dose/timing). The app shows an Add chip the user taps to confirm in the dose sheet; nothing changes automatically. Do not call it for compounds you merely explain or compare without recommending.",
            "input_schema": [
                "type": "object",
                "additionalProperties": false,
                "required": ["action", "compound_slug", "reason"],
                "properties": [
                    "action": ["type": "string", "enum": ["add", "adjust"]],
                    "compound_slug": ["type": "string", "description": "A slug from the catalog."],
                    "reason": ["type": "string", "description": "Short, educational reason for the suggestion."],
                ],
            ],
        ]
    }

    /// Cached chat block 1: warm educational voice + safety + the full catalog.
    /// Stable across chat turns (earns the prompt-cache breakpoint).
    static func chatSystemText(_ catalog: [CatalogSummary]) -> String {
        var s = """
        You are vita: a knowledgeable friend who knows peptides cold. Warm, direct, and plain-spoken. \
        Talk TO the user, not at them. Get to the point, share what you actually know, and let a little \
        personality through. No clinical stiffness, no lecturing.

        How to answer:
        - Use the user's real stack, goals, and context. Be specific and confident. Keep it tight (a few sentences or short bullets, not an essay).
        - Recommending: when the user asks what to add, or a compound is a genuine fit for their goal, recommend specific compounds FROM THE CATALOG and call the suggest_stack_action tool once per recommended compound, so an Add chip appears under your reply. Do NOT ask "want me to add one?" in prose; surface the chips. Only recommend compounds that exist in the catalog. Don't chip compounds you merely explain or compare.
        - Dosing: give educational ranges, never a personal prescription.
        - Disclaimers: a standing "Educational, not medical advice." line is always shown in the app. Do NOT repeat "I'm not a doctor" or "consult your clinician" in every reply. Mention a real caution once, plainly, only when it genuinely matters (a prescription compound, or a real interaction), then move on.
        - Never use em dashes (—) or en dashes (–). Use commas, periods, or parentheses instead.

        CATALOG (slug | name | category | status | educational range | route):
        """
        for c in catalog.sorted(by: { $0.slug < $1.slug }) {
            let range = c.rangeText ?? "n/a"
            let rx = c.rxStatusRaw == "rx" ? "℞ prescription" : (c.rxStatusRaw == "ambiguous" ? "status unclear" : "research")
            let route = c.route ?? "subcutaneous"
            s += "\n- \(c.slug) | \(c.name) | \(c.categoryTitle) | \(rx) | \(range) | \(route)"
        }
        return s
    }

    /// Uncached chat block 2: this user's goals, profile, Health, and live stack.
    static func chatGroundingText(goals: [GoalKind], profile: ProfileInput,
                                  health: HealthSnapshot?, stackLines: [String],
                                  diaryLine: String? = nil, labsLine: String? = nil) -> String {
        var s = "USER CONTEXT\n"
        s += "Goals: " + (goals.isEmpty ? "none stated" : goals.map(\.label).joined(separator: ", ")) + "\n"
        s += "Profile: " + profile.summary + "\n"
        s += "Apple Health: " + (health?.summaryLine ?? "not connected") + "\n"
        if let diaryLine { s += "Diary: " + diaryLine + "\n" }
        if let labsLine { s += "Labs: " + labsLine + "\n" }
        s += "Current stack:\n"
        if stackLines.isEmpty {
            s += "- (empty — nothing tracked yet)\n"
        } else {
            for line in stackLines { s += "- \(line)\n" }
        }
        return s
    }

    /// Block 1 (cached): safety rules + the full catalog. Stable across users so
    /// it earns the prompt-cache breakpoint (needs >4096 tokens on Opus 4.8 to
    /// actually cache — verify via usage.cache_read_input_tokens).
    static func catalogSystemText(_ catalog: [CatalogSummary]) -> String {
        var s = """
        You are the educational protocol engine for vita, a personal peptide-tracking app. \
        You are NOT a prescriber and you NEVER give medical advice. Output is educational only.

        Rules:
        - Suggest only compounds whose slug appears in the CATALOG below. Never invent a slug.
        - Keep every dose_amount within that compound's educational range (low–high) and in its listed unit.
        - Prefer non-prescription research peptides that match the user's goals; you may include an ℞ \
        compound only when it is the clearest fit, and your rationale must say to discuss it with a clinician.
        - Choose a sensible frequency and time(s): morning ~480, midday ~780, evening ~1260 (minutes-from-midnight).
        - Keep the set small and focused (about 1–4 compounds). Do not duplicate the user's already-picked peptides.
        - Use no imperatives ("inject", "you must"); frame everything as educational suggestions.
        - The `disclaimer` field is required: a one-line "Educational, not medical advice. Discuss with your clinician." statement.

        CATALOG (slug — name — category — status — educational range — route):
        """
        for c in catalog.sorted(by: { $0.slug < $1.slug }) {
            let range = c.rangeText ?? "n/a"
            let rx = c.rxStatusRaw == "rx" ? "℞ prescription" : (c.rxStatusRaw == "ambiguous" ? "status unclear" : "research")
            let route = c.route ?? "subcutaneous"
            s += "\n- \(c.slug) — \(c.name) — \(c.categoryTitle) — \(rx) — \(range) — \(route)"
        }
        return s
    }

    /// Block 2 (uncached): this user's goals, picked peptides, profile, and Health.
    static func groundingText(goals: [GoalKind], pickedSlugs: [String],
                              profile: ProfileInput, health: HealthSnapshot?,
                              labsLine: String? = nil) -> String {
        var s = "USER CONTEXT\n"
        s += "Goals: " + (goals.isEmpty ? "none stated" : goals.map(\.label).joined(separator: ", ")) + "\n"
        s += "Already tracking: " + (pickedSlugs.isEmpty ? "nothing yet" : pickedSlugs.joined(separator: ", ")) + "\n"
        s += "Profile: " + profile.summary + "\n"
        if let health, let line = health.summaryLine {
            s += "Apple Health (recent): " + line + "\n"
        } else {
            s += "Apple Health: not connected\n"
        }
        if let labsLine { s += "Labs: " + labsLine + "\n" }
        return s
    }
}

/// Strips em/en dashes from chat output (belt-and-suspenders with the prompt) so
/// replies never show "—". Em dash → comma, en dash → hyphen.
enum ChatText {
    static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: " — ", with: ", ")
            .replacingOccurrences(of: "—", with: ", ")
            .replacingOccurrences(of: " – ", with: ", ")
            .replacingOccurrences(of: "–", with: "-")
    }
}

/// Sendable snapshot of a catalog row passed into the (off-MainActor) service.
struct CatalogSummary: Sendable, Equatable {
    let slug: String
    let name: String
    let categoryRaw: String
    let rxStatusRaw: String
    let doseUnitRaw: String
    let typicalDoseLow: Double?
    let typicalDoseHigh: Double?
    let route: String?
    let defaultScheduleTypeRaw: String?

    var categoryTitle: String { (PeptideCategory(rawValue: categoryRaw) ?? .other).title }
    var doseUnit: DoseUnit { DoseUnit(rawValue: doseUnitRaw) ?? .mcg }
    var rangeText: String? {
        guard let lo = typicalDoseLow, let hi = typicalDoseHigh else { return nil }
        let u = doseUnit.label
        return lo == hi ? "\(vtFormatNumber(lo)) \(u)" : "\(vtFormatNumber(lo))–\(vtFormatNumber(hi)) \(u)"
    }
}

/// Basic profile fields used for grounding.
struct ProfileInput: Sendable, Equatable {
    var ageYears: Int?
    var biologicalSex: String?
    var weightKg: Double?

    var summary: String {
        var bits: [String] = []
        if let ageYears { bits.append("\(ageYears) yrs") }
        if let biologicalSex, !biologicalSex.isEmpty { bits.append(biologicalSex) }
        if let weightKg, weightKg > 0 { bits.append(String(format: "%.0f kg", weightKg)) }
        return bits.isEmpty ? "not provided" : bits.joined(separator: ", ")
    }
}

/// All grounding inputs for one protocol generation.
struct ProtocolInput: Sendable, Equatable {
    var goals: [GoalKind]
    var pickedSlugs: [String]
    var catalog: [CatalogSummary]
    var profile: ProfileInput
    var health: HealthSnapshot?
    var labsLine: String? = nil     // latest panel out-of-range flags (M8b)
}
