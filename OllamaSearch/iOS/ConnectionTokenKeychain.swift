#if os(iOS)
import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "com.mab.mira", category: "ConnectionTokens")

/// Access tokens for saved connections, one Keychain item per connection URL.
///
/// They used to live inside the saved-connection JSON in iCloud's key-value
/// store, which is not a place for a credential. The items are synchronizable,
/// so they travel through iCloud Keychain, which is end-to-end encrypted, and an
/// iPhone and an iPad that share a pairing keep sharing it. With iCloud Keychain
/// off the item simply stays on the device.
///
/// A failed read is never treated as "no token" by callers that delete: a locked
/// device before its first unlock, or an item that has not synced yet, both read
/// as nothing.
enum ConnectionTokenKeychain {

    private static let service = "com.mab.mira.connection-token"

    private static func query(_ urlString: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: urlString,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    static func read(_ urlString: String) -> String? {
        var q = query(urlString)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound { logger.error("keychain read failed: \(status)") }
            return nil
        }
        let token = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty == false) ? token : nil
    }

    /// Stores or replaces the token. Returns false if the Keychain refused it, so
    /// the caller can keep the token elsewhere instead of losing it.
    @discardableResult
    static func write(_ token: String, for urlString: String) -> Bool {
        let value = Data(token.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let updated = SecItemUpdate(query(urlString) as CFDictionary,
                                    [kSecValueData as String: value] as CFDictionary)
        if updated == errSecSuccess { return true }
        guard updated == errSecItemNotFound else {
            logger.error("keychain update failed: \(updated)")
            return false
        }
        var add = query(urlString)
        add[kSecAttrSynchronizable as String] = true
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        add[kSecValueData as String] = value
        let status = SecItemAdd(add as CFDictionary, nil)
        if status != errSecSuccess { logger.error("keychain write failed: \(status)") }
        return status == errSecSuccess
    }

    static func delete(_ urlString: String) {
        let status = SecItemDelete(query(urlString) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            logger.error("keychain delete failed: \(status)")
        }
    }
}
#endif
