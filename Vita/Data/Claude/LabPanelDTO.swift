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
        values = (try? c.decode([Value].self, forKey: .values)) ?? []
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        disclaimer = (try? c.decode(String.self, forKey: .disclaimer))
            ?? "Educational, not medical advice. Discuss results with your clinician."
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
             refText: String? = nil, flagRaw: String? = nil) {
            self.markerKey = markerKey; self.name = name; self.value = value; self.unit = unit
            self.refLow = refLow; self.refHigh = refHigh; self.refText = refText; self.flagRaw = flagRaw
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            markerKey = (try? c.decode(String.self, forKey: .markerKey)) ?? ""
            name = (try? c.decode(String.self, forKey: .name)) ?? ""
            value = (try? c.decode(Double.self, forKey: .value)) ?? 0
            unit = (try? c.decode(String.self, forKey: .unit)) ?? ""
            refLow = try? c.decodeIfPresent(Double.self, forKey: .refLow)
            refHigh = try? c.decodeIfPresent(Double.self, forKey: .refHigh)
            refText = try? c.decodeIfPresent(String.self, forKey: .refText)
            flagRaw = try? c.decodeIfPresent(String.self, forKey: .flagRaw)
        }
    }
}
