import Foundation
import CryptoKit
import AuthenticationServices
import UIKit

/// OAuth2 sign-in for wearable vendors ("Connect your wearables" in Diary).
/// Authorization-code + PKCE for every vendor; Oura additionally requires its
/// client secret on the token exchange (confidential client), Fitbit is a pure
/// PKCE public client. Tokens live only in the Keychain; client IDs arrive via
/// the gitignored Secrets.xcconfig -> Info.plist like the Anthropic key.
enum WearableVendor: String, CaseIterable, Identifiable, Sendable {
    // Fitbit was built in M46 and removed from support by request the same day
    // (shelved; ROADMAP has it next to Whoop). New vendors add a case + arms.
    case oura

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oura: "Oura"
        }
    }

    var authorizeURL: URL {
        switch self {
        case .oura: URL(string: "https://cloud.ouraring.com/oauth/authorize")!
        }
    }

    var tokenURL: URL {
        switch self {
        case .oura: URL(string: "https://api.ouraring.com/oauth/token")!
        }
    }

    /// Space-joined scope string per vendor's published scope names.
    var scopes: String {
        switch self {
        case .oura: "daily personal"
        }
    }

    var clientIDKey: String {
        switch self {
        case .oura: "OURA_CLIENT_ID"
        }
    }

    /// Only confidential clients carry a secret (PKCE public clients return nil).
    var clientSecretKey: String? {
        switch self {
        case .oura: "OURA_CLIENT_SECRET"
        }
    }

    var clientID: String? { WearableConfig.value(clientIDKey) }
    var clientSecret: String? { clientSecretKey.flatMap { WearableConfig.value($0) } }

    /// A Connect row is actionable only when the developer app is registered.
    var isConfigured: Bool { clientID != nil }

    // Keychain accounts (access/refresh/expiry per vendor).
    var accessAccount: String { "\(rawValue)_oauth_access" }
    var refreshAccount: String { "\(rawValue)_oauth_refresh" }
    var expiryAccount: String { "\(rawValue)_oauth_expiry" }
}

/// Reads a Secrets.xcconfig-injected Info.plist value, treating empty and
/// unexpanded `$(VAR)` placeholders as absent.
enum WearableConfig {
    static func value(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !v.isEmpty, !v.hasPrefix("$(")
        else { return nil }
        return v
    }
}

// MARK: - Pure OAuth builders (testable without network or UI)

enum WearableOAuth {
    static let redirectURI = "vita://wearable-callback"
    static let callbackScheme = "vita"

    /// RFC 7636 code verifier: 64 random bytes, base64url without padding.
    static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    /// S256 challenge: BASE64URL(SHA256(ASCII(verifier))).
    static func codeChallenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded()
    }

    static func makeState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded()
    }

    static func authorizationURL(vendor: WearableVendor, clientID: String,
                                 state: String, challenge: String) -> URL {
        var comps = URLComponents(url: vendor.authorizeURL, resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: vendor.scopes),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        return comps.url!
    }

    static func exchangeRequest(vendor: WearableVendor, clientID: String,
                                code: String, verifier: String) -> URLRequest {
        var form = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ]
        if let secret = vendor.clientSecret { form["client_secret"] = secret }
        return formPOST(vendor.tokenURL, form: form)
    }

    static func refreshRequest(vendor: WearableVendor, clientID: String,
                               refreshToken: String) -> URLRequest {
        var form = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ]
        if let secret = vendor.clientSecret { form["client_secret"] = secret }
        return formPOST(vendor.tokenURL, form: form)
    }

    /// RFC 3986 unreserved characters; everything else percent-encodes.
    private static let formAllowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func formPOST(_ url: URL, form: [String: String]) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = form
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return req
    }

    struct TokenResponse: Decodable, Equatable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: Double?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token store (Keychain-backed, auto-refresh)

/// Owns wearable OAuth tokens: stores exchange results, answers "connected?",
/// and hands services a valid access token (refreshing when expired).
actor WearableAuthStore {
    static let shared = WearableAuthStore()

    enum AuthError: Error, Equatable {
        case notConfigured
        case notConnected
        case http(Int)
        case transport
        case decode
        case userCancelled
        case badCallback
    }

    private let session: URLSession
    private let clientIDProvider: @Sendable (WearableVendor) -> String?

    init(session: URLSession = .shared,
         clientIDProvider: @escaping @Sendable (WearableVendor) -> String? = { $0.clientID }) {
        self.session = session
        self.clientIDProvider = clientIDProvider
    }

    /// Sync, Keychain-only check for UI gating (no network).
    nonisolated static func isConnected(_ vendor: WearableVendor) -> Bool {
        Keychain.value(for: vendor.refreshAccount) != nil
            || Keychain.value(for: vendor.accessAccount) != nil
    }

    nonisolated static func disconnect(_ vendor: WearableVendor) {
        Keychain.delete(vendor.accessAccount)
        Keychain.delete(vendor.refreshAccount)
        Keychain.delete(vendor.expiryAccount)
    }

    /// A valid access token, refreshing via the stored refresh token when the
    /// stored one is expired (60s safety margin) or missing.
    func validAccessToken(_ vendor: WearableVendor) async throws -> String {
        if let access = Keychain.value(for: vendor.accessAccount),
           let expiry = Keychain.value(for: vendor.expiryAccount).flatMap(Double.init),
           Date(timeIntervalSince1970: expiry) > Date().addingTimeInterval(60) {
            return access
        }
        return try await refresh(vendor)
    }

    /// Forces a refresh (also the 401 recovery path for services).
    func refresh(_ vendor: WearableVendor) async throws -> String {
        guard let clientID = clientIDProvider(vendor) else { throw AuthError.notConfigured }
        guard let refreshToken = Keychain.value(for: vendor.refreshAccount) else {
            throw AuthError.notConnected
        }
        let req = WearableOAuth.refreshRequest(vendor: vendor, clientID: clientID,
                                               refreshToken: refreshToken)
        let token = try await performTokenRequest(req)
        store(token, for: vendor, previousRefresh: refreshToken)
        return token.accessToken
    }

    /// Exchanges an authorization code (from the sign-in sheet) for tokens.
    func exchange(vendor: WearableVendor, code: String, verifier: String) async throws {
        guard let clientID = clientIDProvider(vendor) else { throw AuthError.notConfigured }
        let req = WearableOAuth.exchangeRequest(vendor: vendor, clientID: clientID,
                                                code: code, verifier: verifier)
        let token = try await performTokenRequest(req)
        store(token, for: vendor, previousRefresh: nil)
    }

    private func performTokenRequest(_ req: URLRequest) async throws -> WearableOAuth.TokenResponse {
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: req) }
        catch { throw AuthError.transport }
        guard let http = response as? HTTPURLResponse else { throw AuthError.transport }
        guard (200...299).contains(http.statusCode) else { throw AuthError.http(http.statusCode) }
        guard let token = try? JSONDecoder().decode(WearableOAuth.TokenResponse.self, from: data) else {
            throw AuthError.decode
        }
        return token
    }

    private func store(_ token: WearableOAuth.TokenResponse, for vendor: WearableVendor,
                       previousRefresh: String?) {
        Keychain.set(token.accessToken, for: vendor.accessAccount)
        // Vendors may rotate or omit the refresh token on refresh; keep the old
        // one when omitted so the connection survives.
        if let newRefresh = token.refreshToken ?? previousRefresh {
            Keychain.set(newRefresh, for: vendor.refreshAccount)
        }
        let expiry = Date().addingTimeInterval(token.expiresIn ?? 3600).timeIntervalSince1970
        Keychain.set(String(expiry), for: vendor.expiryAccount)
    }
}

// MARK: - Sign-in sheet (ASWebAuthenticationSession)

/// Presents the vendor's sign-in page and completes the code exchange.
/// UI-facing: `try await WearableConnector.shared.connect(.oura)`.
@MainActor
final class WearableConnector: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WearableConnector()

    func connect(_ vendor: WearableVendor) async throws {
        guard let clientID = vendor.clientID else { throw WearableAuthStore.AuthError.notConfigured }
        let verifier = WearableOAuth.makeCodeVerifier()
        let state = WearableOAuth.makeState()
        let url = WearableOAuth.authorizationURL(
            vendor: vendor, clientID: clientID,
            state: state, challenge: WearableOAuth.codeChallenge(for: verifier))

        let callback: URL = try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(
                url: url,
                callback: .customScheme(WearableOAuth.callbackScheme)
            ) { url, error in
                if let url { cont.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError,
                        error.code == .canceledLogin {
                    cont.resume(throwing: WearableAuthStore.AuthError.userCancelled)
                } else {
                    cont.resume(throwing: WearableAuthStore.AuthError.transport)
                }
            }
            session.presentationContextProvider = self
            session.start()
        }

        let comps = URLComponents(url: callback, resolvingAgainstBaseURL: false)
        guard comps?.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw WearableAuthStore.AuthError.badCallback }

        try await WearableAuthStore.shared.exchange(vendor: vendor, code: code, verifier: verifier)
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                .first ?? ASPresentationAnchor()
        }
    }
}
