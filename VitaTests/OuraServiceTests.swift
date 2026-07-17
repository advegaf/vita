import XCTest
@testable import Vita

/// Oura API v2 integration: request building, token validation (200/401),
/// two-endpoint decode with next_token pagination, and score clamping / dropping
/// of malformed records. No live network: a URLProtocol stub serves fixtures.
final class OuraServiceTests: XCTestCase {

    override func tearDown() {
        OuraStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OuraStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func service(_ session: URLSession, token: String = "tok-123") -> OuraService {
        OuraService(session: session, tokenProvider: { token })
    }

    /// A provider that throws, standing in for "not connected" (no OAuth tokens).
    private func disconnectedService(_ session: URLSession) -> OuraService {
        OuraService(session: session,
                    tokenProvider: { throw WearableAuthStore.AuthError.notConnected })
    }

    // MARK: Request building

    func testMakeRequestURLBearerAndQuery() {
        let req = OuraService.makeRequest(
            path: "daily_readiness", token: "tok-123",
            queryItems: [URLQueryItem(name: "start_date", value: "2026-07-01"),
                         URLQueryItem(name: "end_date", value: "2026-07-13")])
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer tok-123")
        let url = req.url?.absoluteString ?? ""
        XCTAssertTrue(url.hasPrefix("https://api.ouraring.com/v2/usercollection/daily_readiness?"), url)
        XCTAssertTrue(url.contains("start_date=2026-07-01"), url)
        XCTAssertTrue(url.contains("end_date=2026-07-13"), url)
    }

    func testDayStringIsUTCISO() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 13
        comps.hour = 12; comps.minute = 0
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: comps)!
        XCTAssertEqual(OuraService.dayString(date), "2026-07-13")
        // Round-trips through the parser to the day's UTC start.
        XCTAssertEqual(OuraService.parseDay("2026-07-13").map(OuraService.dayString), "2026-07-13")
    }

    // MARK: token provider (OAuth-backed since M46)

    func testThrowingTokenProviderSurfacesNoTokenWithoutNetwork() async {
        OuraStubURLProtocol.handler = { _ in
            XCTFail("disconnected service must not hit the network"); return (200, Data())
        }
        do {
            _ = try await disconnectedService(stubbedSession()).dailySummary(days: 7)
            XCTFail("expected noToken")
        } catch let e as OuraService.OuraError {
            XCTAssertEqual(e, .noToken)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testEmptyTokenIsNoTokenWithoutNetwork() async {
        OuraStubURLProtocol.handler = { _ in
            XCTFail("empty token must not hit the network"); return (200, Data())
        }
        do {
            _ = try await service(stubbedSession(), token: "").dailySummary(days: 7)
            XCTFail("expected noToken")
        } catch let e as OuraService.OuraError {
            XCTAssertEqual(e, .noToken)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    // MARK: dailySummary decode across both endpoints

    func testDailySummaryDecodesReadinessAndSleep() async throws {
        OuraStubURLProtocol.handler = { req in
            let path = req.url?.path ?? ""
            if path.hasSuffix("daily_readiness") {
                return (200, Data("""
                {"data":[
                  {"day":"2026-07-11","score":72,"temperature_deviation":-0.2},
                  {"day":"2026-07-12","score":80,"temperature_deviation":0.3}
                ],"next_token":null}
                """.utf8))
            }
            if path.hasSuffix("daily_sleep") {
                return (200, Data("""
                {"data":[
                  {"day":"2026-07-11","score":68},
                  {"day":"2026-07-12","score":75}
                ],"next_token":null}
                """.utf8))
            }
            if path.hasSuffix("/sleep") {
                return (200, Data("""
                {"data":[
                  {"day":"2026-07-12","total_sleep_duration":26100,
                   "average_hrv":51.0,"lowest_heart_rate":53.0,"average_breath":13.4}
                ],"next_token":null}
                """.utf8))
            }
            XCTFail("unexpected path \(path)"); return (404, Data())
        }
        let summary = try await service(stubbedSession()).dailySummary(days: 30)
        XCTAssertEqual(summary.readiness.map(\.score), [72, 80])
        XCTAssertEqual(summary.sleepScore.map(\.score), [68, 75])
        XCTAssertEqual(summary.temperatureDeviation.map(\.value), [-0.2, 0.3])
        // Sorted ascending by day, so latest is last (what the card shows).
        XCTAssertEqual(summary.readiness.last?.score, 80)
        // The sleep-periods endpoint feeds the vitals series (M48).
        XCTAssertEqual(summary.vitals.sleepHours.first?.value ?? 0, 7.25, accuracy: 0.001)
        XCTAssertEqual(summary.vitals.hrvMs.first?.value, 51.0)
    }

    func testPaginationFollowsNextToken() async throws {
        OuraStubURLProtocol.handler = { req in
            let query = req.url?.query ?? ""
            if req.url?.path.hasSuffix("daily_readiness") == true {
                if query.contains("next_token=page2") {
                    return (200, Data("""
                    {"data":[{"day":"2026-07-12","score":90}],"next_token":null}
                    """.utf8))
                }
                return (200, Data("""
                {"data":[{"day":"2026-07-11","score":70}],"next_token":"page2"}
                """.utf8))
            }
            // sleep: single empty page
            return (200, Data("{\"data\":[],\"next_token\":null}".utf8))
        }
        let summary = try await service(stubbedSession()).dailySummary(days: 30)
        XCTAssertEqual(summary.readiness.map(\.score), [70, 90])
        XCTAssertTrue(summary.sleepScore.isEmpty)
    }

    func testClampsScoresAndDropsMalformedRecords() async throws {
        OuraStubURLProtocol.handler = { req in
            if req.url?.path.hasSuffix("daily_readiness") == true {
                return (200, Data("""
                {"data":[
                  {"day":"2026-07-11","score":150,"temperature_deviation":0.1},
                  {"day":null,"score":50},
                  {"day":"2026-07-12","score":-8},
                  {"day":"2026-07-13"}
                ],"next_token":null}
                """.utf8))
            }
            return (200, Data("{\"data\":[],\"next_token\":null}".utf8))
        }
        let summary = try await service(stubbedSession()).dailySummary(days: 30)
        // 150 -> 100, -8 -> 0; null-day and score-less records dropped.
        XCTAssertEqual(summary.readiness.map(\.score), [100, 0])
        XCTAssertEqual(summary.temperatureDeviation.count, 1)
    }

    func testHTTPErrorThrows() async {
        OuraStubURLProtocol.handler = { _ in (500, Data()) }
        do {
            _ = try await service(stubbedSession()).dailySummary(days: 7)
            XCTFail("expected an error on 500")
        } catch {
            XCTAssertEqual(error as? OuraService.OuraError, .http(500))
        }
    }

    func testStubReturnsPlausibleValues() async throws {
        let summary = try await OuraServiceStub().dailySummary(days: 30)
        XCTAssertFalse(summary.readiness.isEmpty)
        for s in summary.readiness { XCTAssertTrue((0...100).contains(s.score)) }
        XCTAssertFalse(summary.vitals.isEmpty, "demo must exercise the Oura vitals path")
        for v in summary.vitals.sleepHours { XCTAssertTrue((0...14).contains(v.value)) }
    }

    // MARK: Sleep-period vitals aggregation (M48)

    private func period(_ day: String, seconds: Int?, hrv: Double? = nil,
                        rhr: Double? = nil, breath: Double? = nil) -> OuraSleepPeriodResponse.Row {
        let dayField: String = (day == "nil") ? "null" : "\"" + day + "\""
        let secondsField: String = seconds.map { String($0) } ?? "null"
        let hrvField: String = hrv.map { String($0) } ?? "null"
        let rhrField: String = rhr.map { String($0) } ?? "null"
        let breathField: String = breath.map { String($0) } ?? "null"
        let json = "{\"day\": " + dayField
            + ", \"total_sleep_duration\": " + secondsField
            + ", \"average_hrv\": " + hrvField
            + ", \"lowest_heart_rate\": " + rhrField
            + ", \"average_breath\": " + breathField + "}"
        return try! JSONDecoder().decode(OuraSleepPeriodResponse.Row.self, from: Data(json.utf8))
    }

    func testSleepPeriodDTODecodes() throws {
        let json = """
        {"data": [{"day": "2026-07-13", "total_sleep_duration": 27000,
                   "average_hrv": 55.5, "lowest_heart_rate": 52, "average_breath": 13.2}],
         "next_token": null}
        """
        let page = try JSONDecoder().decode(OuraSleepPeriodResponse.self, from: Data(json.utf8))
        XCTAssertEqual(page.rows.count, 1)
        XCTAssertEqual(page.rows.first?.totalSleepDuration, 27000)
        XCTAssertEqual(page.rows.first?.averageHrv, 55.5)
        XCTAssertEqual(page.rows.first?.lowestHeartRate, 52)
        XCTAssertEqual(page.rows.first?.averageBreath, 13.2)
    }

    func testVitalsAggregationSumsHoursAndPrefersLongestPeriod() {
        let rows = [
            period("2026-07-13", seconds: 25200, hrv: 60, rhr: 50, breath: 13),   // main: 7h
            period("2026-07-13", seconds: 3600, hrv: 90, rhr: 70, breath: 18),    // nap: 1h
        ]
        let v = OuraService.vitals(fromPeriods: rows)
        XCTAssertEqual(v.sleepHours.first?.value ?? 0, 8.0, accuracy: 0.001, "hours sum across periods")
        XCTAssertEqual(v.hrvMs.first?.value, 60, "rates come from the longest period")
        XCTAssertEqual(v.restingHR.first?.value, 50)
        XCTAssertEqual(v.respiratoryRate.first?.value, 13)
    }

    func testVitalsAggregationDropsImplausibleAndSortsDays() {
        let rows = [
            period("2026-07-13", seconds: 25200, hrv: 900, rhr: 10, breath: 60), // all implausible
            period("2026-07-12", seconds: 21600, hrv: 48, rhr: 55, breath: 14),
        ]
        let v = OuraService.vitals(fromPeriods: rows)
        XCTAssertEqual(v.sleepHours.count, 2, "hours still chart even when rates are dropped")
        XCTAssertEqual(v.hrvMs.count, 1, "implausible HRV dropped")
        XCTAssertEqual(v.restingHR.count, 1)
        XCTAssertEqual(v.respiratoryRate.count, 1)
        XCTAssertTrue(v.sleepHours[0].day < v.sleepHours[1].day, "days sorted ascending")
    }

    func testVitalsAggregationSkipsMalformedDays() {
        let rows = [period("nil", seconds: 25200, hrv: 50)]
        XCTAssertTrue(OuraService.vitals(fromPeriods: rows).isEmpty)
    }
}

/// Serves canned responses for OuraService's injected URLSession. The handler maps
/// a request to (status, body); nil handler means the test forgot to set one.
final class OuraStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = OuraStubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
