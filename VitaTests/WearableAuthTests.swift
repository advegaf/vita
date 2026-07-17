import XCTest
@testable import Vita

/// M46 wearable OAuth engine: PKCE correctness, vendor request building, and
/// the Keychain-backed token store's exchange/refresh lifecycle (stubbed
/// transport, no live network, no sign-in UI).
final class WearableAuthTests: XCTestCase {

    override func tearDown() {
        for vendor in WearableVendor.allCases { WearableAuthStore.disconnect(vendor) }
        WearableStubURLProtocol.handler = nil
        super.tearDown()
    }

    private func stubbedStore(clientID: String? = "cid-test") -> WearableAuthStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [WearableStubURLProtocol.self]
        return WearableAuthStore(session: URLSession(configuration: config),
                                 clientIDProvider: { _ in clientID })
    }

    // MARK: PKCE

    func testCodeVerifierIsBase64URLAndLongEnough() {
        let v = WearableOAuth.makeCodeVerifier()
        XCTAssertGreaterThanOrEqual(v.count, 43, "RFC 7636 wants 43-128 chars")
        XCTAssertNil(v.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")),
                     "must be base64url without padding")
        XCTAssertNotEqual(WearableOAuth.makeCodeVerifier(), v, "verifiers are random")
    }

    func testCodeChallengeMatchesKnownVector() {
        // SHA256("test") base64url = n4bQgYhMfWWaL-qgxVrQFaO_TxsrC4Is0V1sFbDwCgg
        XCTAssertEqual(WearableOAuth.codeChallenge(for: "test"),
                       "n4bQgYhMfWWaL-qgxVrQFaO_TxsrC4Is0V1sFbDwCgg")
    }

    // MARK: Authorization URL

    func testAuthorizationURLPerVendor() {
        for vendor in WearableVendor.allCases {
            let url = WearableOAuth.authorizationURL(vendor: vendor, clientID: "cid-test",
                                                     state: "st4te", challenge: "ch4llenge")
            let s = url.absoluteString
            XCTAssertTrue(s.hasPrefix(vendor.authorizeURL.absoluteString), s)
            XCTAssertTrue(s.contains("response_type=code"), s)
            XCTAssertTrue(s.contains("client_id=cid-test"), s)
            XCTAssertTrue(s.contains("state=st4te"), s)
            XCTAssertTrue(s.contains("code_challenge=ch4llenge"), s)
            XCTAssertTrue(s.contains("code_challenge_method=S256"), s)
            XCTAssertTrue(s.contains("redirect_uri=vita://wearable-callback")
                          || s.contains("redirect_uri=vita%3A%2F%2Fwearable-callback"), s)
        }
    }

    // MARK: Token requests

    func testExchangeRequestFormFields() throws {
        let req = WearableOAuth.exchangeRequest(vendor: .oura, clientID: "cid-test",
                                                code: "abc", verifier: "ver1fier")
        XCTAssertEqual(req.httpMethod, "POST")
        XCTAssertEqual(req.url, WearableVendor.oura.tokenURL)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"),
                       "application/x-www-form-urlencoded")
        let body = String(data: try XCTUnwrap(req.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("grant_type=authorization_code"), body)
        XCTAssertTrue(body.contains("code=abc"), body)
        XCTAssertTrue(body.contains("code_verifier=ver1fier"), body)
        XCTAssertTrue(body.contains("client_id=cid-test"), body)
        // In the test bundle no OURA_CLIENT_SECRET is injected, so the form
        // must simply omit the field rather than sending an empty secret.
        if WearableVendor.oura.clientSecret == nil {
            XCTAssertFalse(body.contains("client_secret"), body)
        }
    }

    func testRefreshRequestFormFields() throws {
        let req = WearableOAuth.refreshRequest(vendor: .oura, clientID: "cid-test",
                                               refreshToken: "rtok")
        let body = String(data: try XCTUnwrap(req.httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("refresh_token=rtok"), body)
        XCTAssertTrue(body.contains("client_id=cid-test"), body)
    }

    func testTokenResponseDecodesSnakeCase() throws {
        let json = #"{"access_token":"at","refresh_token":"rt","expires_in":3600,"token_type":"Bearer"}"#
        let t = try JSONDecoder().decode(WearableOAuth.TokenResponse.self, from: Data(json.utf8))
        XCTAssertEqual(t, .init(accessToken: "at", refreshToken: "rt", expiresIn: 3600))
    }

    // MARK: Store lifecycle (stubbed transport, real Keychain in the test host)

    func testExchangeStoresTokensAndConnects() async throws {
        WearableStubURLProtocol.handler = { req in
            XCTAssertEqual(req.url, WearableVendor.oura.tokenURL)
            return (200, Data(#"{"access_token":"at1","refresh_token":"rt1","expires_in":3600}"#.utf8))
        }
        XCTAssertFalse(WearableAuthStore.isConnected(.oura))
        try await stubbedStore().exchange(vendor: .oura, code: "code", verifier: "v")
        XCTAssertTrue(WearableAuthStore.isConnected(.oura))
        let token = try await stubbedStore().validAccessToken(.oura)
        XCTAssertEqual(token, "at1", "fresh token must be served without a refresh call")
    }

    func testRefreshRotatesAccessAndKeepsRefreshWhenOmitted() async throws {
        WearableStubURLProtocol.handler = { _ in
            (200, Data(#"{"access_token":"at1","refresh_token":"rt1","expires_in":-10}"#.utf8))
        }
        try await stubbedStore().exchange(vendor: .oura, code: "code", verifier: "v")
        // Expired immediately (-10s): next validAccessToken must refresh. The
        // refresh response omits refresh_token; the stored rt1 must survive.
        WearableStubURLProtocol.handler = { req in
            let body = String(data: req.httpBody ?? req.bodyStreamData() ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("refresh_token=rt1"), body)
            return (200, Data(#"{"access_token":"at2","expires_in":3600}"#.utf8))
        }
        let token = try await stubbedStore().validAccessToken(.oura)
        XCTAssertEqual(token, "at2")
        XCTAssertTrue(WearableAuthStore.isConnected(.oura))
        // A later forced refresh still finds rt1.
        WearableStubURLProtocol.handler = { req in
            let body = String(data: req.httpBody ?? req.bodyStreamData() ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("refresh_token=rt1"), body)
            return (200, Data(#"{"access_token":"at3","expires_in":3600}"#.utf8))
        }
        let again = try await stubbedStore().refresh(.oura)
        XCTAssertEqual(again, "at3")
    }

    func testRefreshWithoutConnectionThrowsNotConnected() async {
        do {
            _ = try await stubbedStore().validAccessToken(.oura)
            XCTFail("expected notConnected")
        } catch let e as WearableAuthStore.AuthError {
            XCTAssertEqual(e, .notConnected)
        } catch { XCTFail("unexpected \(error)") }
    }

    func testMissingClientIDThrowsNotConfigured() async {
        do {
            try await stubbedStore(clientID: nil).exchange(vendor: .oura, code: "c", verifier: "v")
            XCTFail("expected notConfigured")
        } catch let e as WearableAuthStore.AuthError {
            XCTAssertEqual(e, .notConfigured)
        } catch { XCTFail("unexpected \(error)") }
    }

    func testDisconnectClearsEverything() async throws {
        WearableStubURLProtocol.handler = { _ in
            (200, Data(#"{"access_token":"at1","refresh_token":"rt1","expires_in":3600}"#.utf8))
        }
        try await stubbedStore().exchange(vendor: .oura, code: "c", verifier: "v")
        XCTAssertTrue(WearableAuthStore.isConnected(.oura))
        WearableAuthStore.disconnect(.oura)
        XCTAssertFalse(WearableAuthStore.isConnected(.oura))
    }
}

/// Canned token-endpoint responses for the injected URLSession.
final class WearableStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = WearableStubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (status, data) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension URLRequest {
    /// URLSession moves form bodies into a stream by the time URLProtocol sees
    /// them; drain it so tests can assert on the form fields.
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open(); defer { stream.close() }
        var data = Data()
        let size = 1024
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buf.deallocate() }
        while stream.hasBytesAvailable {
            let n = stream.read(buf, maxLength: size)
            if n <= 0 { break }
            data.append(buf, count: n)
        }
        return data
    }
}
