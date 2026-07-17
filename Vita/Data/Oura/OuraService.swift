import Foundation

/// Reads Oura Ring API v2 daily summaries over raw URLSession (there is no Swift
/// Oura SDK). Bearer-token auth via the WearableAuthStore OAuth tokens (M46;
/// supplied lazily through an async closure so tests can inject a fixed token).
/// Mirrors AnthropicClient's shape: an actor, static pure request builders, and
/// a small typed error enum. The app works identically when not connected:
/// callers gate on WearableAuthStore.isConnected before asking.
protocol OuraServiceProviding: Sendable {
    /// Last N days via daily_readiness + daily_sleep, merged into one summary.
    func dailySummary(days: Int) async throws -> OuraDailySummary
}

actor OuraService: OuraServiceProviding {
    enum Const {
        static let base = URL(string: "https://api.ouraring.com/v2/usercollection/")!
        static let maxPages = 5   // defensive next_token loop ceiling
    }

    enum OuraError: Error, Equatable {
        case noToken
        case http(Int)
        case transport
        case decode
    }

    private nonisolated let session: URLSession
    private nonisolated let tokenProvider: @Sendable () async throws -> String

    init(session: URLSession = .shared,
         tokenProvider: @escaping @Sendable () async throws -> String = {
             try await WearableAuthStore.shared.validAccessToken(.oura)
         }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    // MARK: - Pure builders (testable without network)

    static func makeRequest(path: String, token: String,
                            queryItems: [URLQueryItem] = []) -> URLRequest {
        let url = Const.base.appendingPathComponent(path)
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { comps?.queryItems = queryItems }
        var req = URLRequest(url: comps?.url ?? url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// Oura "day" strings and query dates are plain yyyy-MM-dd in UTC.
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

    /// Parse an Oura "day" into that day's start (UTC). Nil (dropped) if malformed.
    static func parseDay(_ s: String?) -> Date? {
        guard let s, let d = dayFormatter.date(from: s) else { return nil }
        return d
    }

    static func clampScore(_ s: Int) -> Int { min(max(s, 0), 100) }

    // MARK: - Daily summary

    func dailySummary(days: Int) async throws -> OuraDailySummary {
        var token = try await fetchToken()
        do {
            return try await dailySummary(days: days, token: token)
        } catch OuraError.http(401) {
            // Access token revoked/expired early: refresh once and retry.
            token = try await WearableAuthStore.shared.refresh(.oura)
            return try await dailySummary(days: days, token: token)
        }
    }

    private func fetchToken() async throws -> String {
        guard let token = try? await tokenProvider(), !token.isEmpty else {
            throw OuraError.noToken
        }
        return token
    }

    private func dailySummary(days: Int, token: String) async throws -> OuraDailySummary {
        let cal = Calendar.current
        let end = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -(max(days, 1) - 1), to: end) ?? end
        let range = [
            URLQueryItem(name: "start_date", value: Self.dayString(start)),
            URLQueryItem(name: "end_date", value: Self.dayString(end)),
        ]

        var readiness: [OuraDayScore] = []
        var temperature: [OuraDayValue] = []
        for row in try await fetchAll(OuraReadinessResponse.self, path: "daily_readiness",
                                      token: token, query: range) {
            guard let day = Self.parseDay(row.day) else { continue }
            if let score = row.score {
                readiness.append(OuraDayScore(day: day, score: Self.clampScore(score)))
            }
            if let dev = row.temperatureDeviation, dev.isFinite {
                temperature.append(OuraDayValue(day: day, value: dev))
            }
        }

        var sleep: [OuraDayScore] = []
        for row in try await fetchAll(OuraSleepResponse.self, path: "daily_sleep",
                                      token: token, query: range) {
            guard let day = Self.parseDay(row.day), let score = row.score else { continue }
            sleep.append(OuraDayScore(day: day, score: Self.clampScore(score)))
        }

        let periods = try await fetchAll(OuraSleepPeriodResponse.self, path: "sleep",
                                         token: token, query: range)

        return OuraDailySummary(
            readiness: readiness.sorted { $0.day < $1.day },
            sleepScore: sleep.sorted { $0.day < $1.day },
            temperatureDeviation: temperature.sorted { $0.day < $1.day },
            vitals: Self.vitals(fromPeriods: periods))
    }

    /// Folds sleep periods (main sleep + naps, keyed by wake day) into the
    /// Diary's per-day vitals: hours are summed across the day's periods; HRV,
    /// resting HR, and breath come from the LONGEST period (the main sleep).
    /// Implausible values are dropped rather than charted.
    static func vitals(fromPeriods rows: [OuraSleepPeriodResponse.Row]) -> VitalsSeries {
        struct DayAgg { var seconds = 0; var longest = -1
                        var hrv: Double?; var rhr: Double?; var breath: Double? }
        var byDay: [Date: DayAgg] = [:]
        for row in rows {
            guard let day = parseDay(row.day) else { continue }
            var agg = byDay[day] ?? DayAgg()
            let duration = max(row.totalSleepDuration ?? 0, 0)
            agg.seconds += duration
            if duration > agg.longest {
                agg.longest = duration
                agg.hrv = row.averageHrv.flatMap { (0...500).contains($0) ? $0 : nil }
                agg.rhr = row.lowestHeartRate.flatMap { (20...150).contains($0) ? $0 : nil }
                agg.breath = row.averageBreath.flatMap { (4...40).contains($0) ? $0 : nil }
            }
            byDay[day] = agg
        }
        let days = byDay.keys.sorted()
        var out = VitalsSeries()
        for day in days {
            guard let agg = byDay[day] else { continue }
            if agg.seconds > 0 {
                out.sleepHours.append(DatedValue(day: day, value: Double(agg.seconds) / 3600))
            }
            if let v = agg.hrv { out.hrvMs.append(DatedValue(day: day, value: v)) }
            if let v = agg.rhr { out.restingHR.append(DatedValue(day: day, value: v)) }
            if let v = agg.breath { out.respiratoryRate.append(DatedValue(day: day, value: v)) }
        }
        return out
    }

    // MARK: - Paged fetch

    /// Follows next_token defensively (max `Const.maxPages`) and flattens the rows.
    private func fetchAll<P: OuraPage>(_ type: P.Type, path: String, token: String,
                                       query: [URLQueryItem]) async throws -> [P.Row] {
        var rows: [P.Row] = []
        var nextToken: String? = nil
        var page = 0
        repeat {
            var q = query
            if let nextToken { q.append(URLQueryItem(name: "next_token", value: nextToken)) }
            let (data, response) = try await perform(
                Self.makeRequest(path: path, token: token, queryItems: q))
            guard let http = response as? HTTPURLResponse else { throw OuraError.transport }
            guard (200...299).contains(http.statusCode) else { throw OuraError.http(http.statusCode) }
            guard let decoded = try? JSONDecoder().decode(P.self, from: data) else {
                throw OuraError.decode
            }
            rows.append(contentsOf: decoded.rows)
            nextToken = (decoded.next?.isEmpty == false) ? decoded.next : nil
            page += 1
        } while nextToken != nil && page < Const.maxPages
        return rows
    }

    /// Wraps the transport so URLErrors surface as a single typed `.transport`.
    private func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do { return try await session.data(for: request) }
        catch { throw OuraError.transport }
    }
}

/// Fixed, plausible values for previews and demo mode. Never hits the network.
struct OuraServiceStub: OuraServiceProviding {
    func dailySummary(days: Int) async throws -> OuraDailySummary { .demo(days: days) }
}
