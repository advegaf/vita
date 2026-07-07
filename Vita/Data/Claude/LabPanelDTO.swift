import Foundation

/// Strict-JSON shape Claude returns via the forced `interpret_labs` vision tool.
/// Decoded from the tool_use input. Tolerant per-field decode (the model may omit
/// arrays / null a range), mirroring `ProtocolDTO`. The app recomputes each flag
/// deterministically from value vs range — it never trusts the model's `flag_raw`.
struct LabPanelDTO: Codable, Equatable, Sendable {
    var panelDate: String?        // ISO-8601 string or nil; parsed to Date in LabService
    var sourceLabName: String?
    var values: [Value]
    var summary: String
    var disclaimer: String

    enum CodingKeys: String, CodingKey {
        case panelDate = "panel_date"
        case sourceLabName = "source_lab_name"
        case values, summary, disclaimer
    }

    init(panelDate: String? = nil, sourceLabName: String? = nil,
         values: [Value] = [], summary: String = "",
         disclaimer: String = "Educational, not medical advice. Discuss results with your clinician.") {
        self.panelDate = panelDate; self.sourceLabName = sourceLabName
        self.values = values; self.summary = summary; self.disclaimer = disclaimer
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        panelDate = try? c.decodeIfPresent(String.self, forKey: .panelDate)
        sourceLabName = try? c.decodeIfPresent(String.self, forKey: .sourceLabName)
        // Element-tolerant: a single malformed row (a qualitative result, a null value)
        // must NOT drop the whole array. Decoding `[Value].self` is all-or-nothing, so
        // wrap each element in a never-throwing shim and keep the ones that parse.
        let rows = (try? c.decode([LenientValue].self, forKey: .values)) ?? []
        values = rows.compactMap(\.value)
        summary = Self.stripMarkup((try? c.decode(String.self, forKey: .summary)) ?? "")
        disclaimer = Self.stripMarkup((try? c.decode(String.self, forKey: .disclaimer))
            ?? "Educational, not medical advice. Discuss results with your clinician.")
    }

    /// Belt-and-braces: degenerate constrained generation was observed leaking raw
    /// tool-call markup (`<parameter …>` fragments) INTO string field values. Strip
    /// tag-LIKE tokens only (a letter or / after `<`) — lab strings legitimately
    /// contain numeric comparisons like "<150" or ">7.13", which must survive.
    static func stripMarkup(_ s: String) -> String {
        // Em/en dashes are banned app-wide; the model leaks them into summaries
        // and names despite the prompt, so sanitize at this same choke point
        // (every decoded string field already flows through here).
        let dashFree = ChatText.sanitize(s)
        guard dashFree.contains("<") else { return dashFree }
        return dashFree.replacingOccurrences(of: "</?[a-zA-Z][^>]*>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes a `Value` but never throws — a bad element becomes nil (skipped) instead
    /// of failing the entire array decode.
    private struct LenientValue: Decodable {
        let value: Value?
        init(from decoder: Decoder) throws { value = try? Value(from: decoder) }
    }

    /// Merges per-page extractions into one panel: values concatenated in page order
    /// and deduped by marker_key (first occurrence wins — repeated table headers on
    /// later pages must not overwrite), metadata from the first page that has it.
    static func merged(_ pages: [LabPanelDTO]) -> LabPanelDTO {
        var seen = Set<String>()
        var values: [Value] = []
        for page in pages {
            for v in page.values {
                if v.markerKey.isEmpty { values.append(v); continue }
                if seen.insert(v.markerKey).inserted { values.append(v) }
            }
        }
        return LabPanelDTO(
            panelDate: pages.compactMap(\.panelDate).first,
            sourceLabName: pages.compactMap(\.sourceLabName).first,
            values: values,
            summary: pages.map(\.summary).first { !$0.isEmpty } ?? "",
            disclaimer: pages.map(\.disclaimer).first { !$0.isEmpty }
                ?? "Educational, not medical advice. Discuss results with your clinician.")
    }

    struct Value: Codable, Equatable, Sendable {
        var markerKey: String
        var name: String
        var value: Double
        var unit: String
        var refLow: Double?
        var refHigh: Double?
        var refText: String?
        var flagRaw: String?
        /// False when the model returned a qualitative result ("Negative") or null
        /// instead of a number. Such a value must never be flagged numerically.
        var hasNumericValue: Bool
        /// The raw qualitative token ("Negative"/"Positive"/…), shown in place of "0".
        var qualitative: String?

        enum CodingKeys: String, CodingKey {
            case markerKey = "marker_key"
            case name, value, unit
            case refLow = "ref_low"
            case refHigh = "ref_high"
            case refText = "ref_text"
            case flagRaw = "flag_raw"
        }

        init(markerKey: String, name: String, value: Double, unit: String,
             refLow: Double? = nil, refHigh: Double? = nil,
             refText: String? = nil, flagRaw: String? = nil,
             hasNumericValue: Bool = true, qualitative: String? = nil) {
            self.markerKey = markerKey; self.name = name; self.value = value; self.unit = unit
            self.refLow = refLow; self.refHigh = refHigh; self.refText = refText; self.flagRaw = flagRaw
            self.hasNumericValue = hasNumericValue; self.qualitative = qualitative
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            markerKey = LabPanelDTO.stripMarkup((try? c.decode(String.self, forKey: .markerKey)) ?? "")
            name = LabPanelDTO.stripMarkup((try? c.decode(String.self, forKey: .name)) ?? "")
            // A numeric value is the normal case. A qualitative result ("Negative") or
            // null decodes to 0 but is marked non-numeric so it is never flagged LOW.
            if let n = try? c.decode(Double.self, forKey: .value) {
                value = n; hasNumericValue = true; qualitative = nil
            } else {
                value = 0; hasNumericValue = false
                let raw = (try? c.decode(String.self, forKey: .value)).map(LabPanelDTO.stripMarkup) ?? ""
                qualitative = raw.isEmpty ? nil : raw
            }
            unit = LabPanelDTO.stripMarkup((try? c.decode(String.self, forKey: .unit)) ?? "")
            refLow = try? c.decodeIfPresent(Double.self, forKey: .refLow)
            refHigh = try? c.decodeIfPresent(Double.self, forKey: .refHigh)
            refText = (try? c.decodeIfPresent(String.self, forKey: .refText)).map(LabPanelDTO.stripMarkup)
            flagRaw = try? c.decodeIfPresent(String.self, forKey: .flagRaw)
        }
    }
}
