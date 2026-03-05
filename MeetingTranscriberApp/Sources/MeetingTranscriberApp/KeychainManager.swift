import Foundation
import Security

/// Thin wrapper around the macOS Keychain for storing sensitive values (e.g. API keys).
class KeychainManager {
    static let shared = KeychainManager()
    private init() {}

    private let service = "ai.openclaw.MeetingTranscriber"

    /// Saves `value` for `key`, replacing any existing entry.
    func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key: key)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecValueData:   data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[KeychainManager] Save failed for '\(key)': OSStatus \(status)")
        }
    }

    /// Returns the stored string for `key`, or nil if not found.
    func retrieve(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  kCFBooleanTrue as Any,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    /// Deletes the stored entry for `key`. No-op if not present.
    func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
