import Foundation
import Security

// MARK: - KeychainStore — OAuth credentials at rest
//
// The Google refresh token is a long-lived key to the user's calendar, so it
// does not go in UserDefaults. The client ID and secret live here too: for an
// installed app Google's "secret" is not truly confidential (it ships inside
// every copy of a desktop client), but it is still an account identifier and
// there is no reason to leave it in a plist.
//
// The app is not sandboxed, so this is the plain login keychain with no access
// group.

enum KeychainStore {
    private static let service = "com.notchsnap.app.google"

    static func set(_ value: String?, for key: String) {
        guard let value, !value.isEmpty else { remove(key); return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: Data(value.utf8),
            // Needed after first unlock so a refresh can run without the user
            // having just typed their login password.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { a, _ in a } as CFDictionary, nil)
        }
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }

    // Keys used by the Google integration.
    enum Key {
        static let clientID = "clientID"
        static let clientSecret = "clientSecret"
        static let refreshToken = "refreshToken"
        static let account = "account"
    }
}
