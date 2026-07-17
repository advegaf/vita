import Foundation
import Security

/// Minimal Keychain wrapper for the embedded Anthropic key. The key is seeded
/// once from the gitignored xcconfig → Info.plist on first launch, then the
/// Keychain is the only runtime source of truth. Never logged.
enum Keychain {
    static let service = Bundle.main.bundleIdentifier ?? "com.example.vita"
    static let apiKeyAccount = "anthropic_api_key"

    static var apiKey: String? { value(for: apiKeyAccount) }

    /// Whether a key is present, without exposing it (for the Settings status row).
    static func hasAPIKey() -> Bool { (apiKey ?? "").isEmpty == false }

    @discardableResult
    static func setAPIKey(_ key: String) -> Bool { set(key, for: apiKeyAccount) }

    // Wearable OAuth tokens (access/refresh/expiry per vendor) use the generic
    // accessors below with WearableVendor's account names; see WearableAuth.swift.

    // MARK: - Generic accessors

    static func value(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    @discardableResult
    static func set(_ value: String, for account: String) -> Bool {
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func delete(_ account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        return SecItemDelete(query as CFDictionary) == errSecSuccess
    }
}

/// Copies the embedded key from Info.plist into the Keychain once on first launch.
enum KeychainSeeder {
    static func seedIfNeeded() {
        guard (Keychain.apiKey ?? "").isEmpty else { return }
        guard let v = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
              !v.isEmpty, v != "$(ANTHROPIC_API_KEY)" else { return }
        Keychain.setAPIKey(v)
    }
}
