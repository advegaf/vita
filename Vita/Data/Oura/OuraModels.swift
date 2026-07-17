import Foundation

// MARK: - Domain values (what the Diary cards render)

/// One day's Oura score (readiness / sleep), 0...100.
struct OuraDayScore: Sendable, Equatable { let day: Date; let score: Int }

/// One day's Oura scalar (temperature deviation, degrees C from baseline).
struct OuraDayValue: Sendable, Equatable { let day: Date; let value: Double }

/// The wearable series Vita reads from Oura. Never persisted.
struct OuraDailySummary: Sendable, Equatable {
    var readiness: [OuraDayScore]
    var sleepScore: [OuraDayScore]
    var temperatureDeviation: [OuraDayValue]   // degrees C, +/- from baseline
    /// Sleep hours, HRV, resting HR, and breath derived from the `sleep`
    /// (periods) endpoint (M48) — same shape the Apple Health path produces,
    /// so the Diary cards can render either source unchanged.
    var vitals: VitalsSeries = VitalsSeries()

    var isEmpty: Bool {
        readiness.isEmpty && sleepScore.isEmpty && temperatureDeviation.isEmpty
            && vitals.isEmpty
    }
}

extension OuraDailySummary {
    /// Deterministic demo summary for previews and VITA_OURA_DEMO screenshots,
    /// generated without touching the network.
    static func demo(days: Int = 30, asOf now: Date = .now) -> OuraDailySummary {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let span = max(days, 1)
        func scores(_ base: Double, _ swing: Double) -> [OuraDayScore] {
            (0..<span).reversed().compactMap { back in
                guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
                let phase = Double(back) * 0.7
                let raw = base + swing * (0.6 * sin(phase) + 0.4 * cos(phase * 1.7))
                return OuraDayScore(day: day, score: min(max(Int(raw.rounded()), 0), 100))
            }
        }
        func deviations(_ swing: Double) -> [OuraDayValue] {
            (0..<span).reversed().compactMap { back in
                guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
                let phase = Double(back) * 0.5
                let raw = swing * sin(phase)
                return OuraDayValue(day: day, value: (raw * 10).rounded() / 10)
            }
        }
        func values(_ base: Double, _ swing: Double, decimals: Double = 10) -> [DatedValue] {
            (0..<span).reversed().compactMap { back in
                guard let day = cal.date(byAdding: .day, value: -back, to: today) else { return nil }
                let phase = Double(back) * 0.6
                let raw = base + swing * (0.5 * sin(phase) + 0.5 * cos(phase * 1.3))
                return DatedValue(day: day, value: (raw * decimals).rounded() / decimals)
            }
        }
        return OuraDailySummary(readiness: scores(78, 9),
                                sleepScore: scores(81, 8),
                                temperatureDeviation: deviations(0.3),
                                vitals: VitalsSeries(hrvMs: values(52, 12, decimals: 1),
                                                     restingHR: values(56, 4, decimals: 1),
                                                     respiratoryRate: values(13.6, 1.1),
                                                     sleepHours: values(7.4, 0.9)))
    }
}

// MARK: - Wire DTOs (Oura API v2 responses)

/// `daily_readiness` page. Temperature deviation lives on the readiness record.
struct OuraReadinessResponse: Decodable, OuraPage {
    let data: [Row]
    let nextToken: String?

    struct Row: Decodable, Sendable {
        let day: String?
        let score: Int?
        let temperatureDeviation: Double?
        enum CodingKeys: String, CodingKey {
            case day, score
            case temperatureDeviation = "temperature_deviation"
        }
    }
    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
    var rows: [Row] { data }
    var next: String? { nextToken }
}

/// `daily_sleep` page.
struct OuraSleepResponse: Decodable, OuraPage {
    let data: [Row]
    let nextToken: String?

    struct Row: Decodable, Sendable {
        let day: String?
        let score: Int?
    }
    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
    var rows: [Row] { data }
    var next: String? { nextToken }
}

/// `sleep` (periods) page: one row per sleep period (main sleep + naps), keyed
/// by the wake day. Carries the vitals the Diary cards need (M48).
struct OuraSleepPeriodResponse: Decodable, OuraPage {
    let data: [Row]
    let nextToken: String?

    struct Row: Decodable, Sendable {
        let day: String?
        let totalSleepDuration: Int?     // seconds
        let averageHrv: Double?          // ms
        let lowestHeartRate: Double?     // bpm (Oura's resting HR)
        let averageBreath: Double?       // breaths/min
        enum CodingKeys: String, CodingKey {
            case day
            case totalSleepDuration = "total_sleep_duration"
            case averageHrv = "average_hrv"
            case lowestHeartRate = "lowest_heart_rate"
            case averageBreath = "average_breath"
        }
    }
    enum CodingKeys: String, CodingKey {
        case data
        case nextToken = "next_token"
    }
    var rows: [Row] { data }
    var next: String? { nextToken }
}

/// A paged Oura collection response: a `data` array plus an optional `next_token`.
protocol OuraPage: Decodable, Sendable {
    associatedtype Row: Sendable
    var rows: [Row] { get }
    var next: String? { get }
}
