import Foundation

/// Strict-JSON shape Claude returns via the forced `emit_protocol` tool. Decoded
/// from the tool_use block's `input`. Numbers are validated/clamped client-side
/// afterwards (strict mode can't bound them).
struct ProtocolDTO: Codable, Equatable, Sendable {
    var disclaimer: String
    var items: [Item]

    struct Item: Codable, Equatable, Sendable {
        var compoundSlug: String
        var doseAmount: Double
        var doseUnit: String
        var frequency: String
        var weekdays: [Int]
        var timesMinutes: [Int]
        var rationale: String?

        enum CodingKeys: String, CodingKey {
            case compoundSlug = "compound_slug"
            case doseAmount = "dose_amount"
            case doseUnit = "dose_unit"
            case frequency
            case weekdays
            case timesMinutes = "times_minutes"
            case rationale
        }

        init(compoundSlug: String, doseAmount: Double, doseUnit: String,
             frequency: String, weekdays: [Int] = [], timesMinutes: [Int] = [],
             rationale: String? = nil) {
            self.compoundSlug = compoundSlug
            self.doseAmount = doseAmount
            self.doseUnit = doseUnit
            self.frequency = frequency
            self.weekdays = weekdays
            self.timesMinutes = timesMinutes
            self.rationale = rationale
        }

        // Tolerant decode: arrays/rationale may be omitted by the model.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            compoundSlug = try c.decode(String.self, forKey: .compoundSlug)
            doseAmount = (try? c.decode(Double.self, forKey: .doseAmount)) ?? 0
            doseUnit = (try? c.decode(String.self, forKey: .doseUnit)) ?? "mcg"
            frequency = (try? c.decode(String.self, forKey: .frequency)) ?? "daily"
            weekdays = (try? c.decode([Int].self, forKey: .weekdays)) ?? []
            timesMinutes = (try? c.decode([Int].self, forKey: .timesMinutes)) ?? []
            rationale = try? c.decodeIfPresent(String.self, forKey: .rationale)
        }
    }
}
