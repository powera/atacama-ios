//
//  KeychainStore.swift
//  Atacama
//
//  Minimal Keychain wrapper for per-server auth tokens. Durable across launches,
//  unlike trakaido's in-memory token holder. Each configured server stores its own
//  bearer token keyed by the server's id. See docs/auth-flow.md.
//

import Foundation
import Security

/// Stores per-server bearer auth tokens in the Keychain as generic passwords.
///
/// Tokens live in the shared App Group's keychain access group so the Share
/// Extension can read the same token the app stored (an app group identifier is
/// a valid keychain access group, and unlike a `keychain-access-groups` entry it
/// carries no team-ID prefix). Every query therefore pins `kSecAttrAccessGroup`.
enum KeychainStore {
    /// Service identifier for our Keychain items.
    private static let service = "com.atacama.ios.auth"

    /// Keychain access group shared with the Share Extension (the App Group id).
    private static let accessGroup = AppGroup.identifier

    /// Account key for a server's token: one entry per server id.
    private static func account(for serverID: UUID) -> String {
        "bearer-token-\(serverID.uuidString)"
    }

    /// Persist the token for a server, replacing any existing value. Returns false on failure.
    @discardableResult
    static func saveToken(_ token: String, for serverID: UUID) -> Bool {
        guard let data = token.data(using: .utf8) else { return false }
        let key = account(for: serverID)

        // Delete any existing item first so this is an upsert.
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    /// Read the stored token for a server, or nil if none is stored.
    static func loadToken(for serverID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else { return nil }
        return token
    }

    /// Remove a server's stored token (sign out / server removed).
    @discardableResult
    static func deleteToken(for serverID: UUID) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: serverID),
            kSecAttrAccessGroup as String: accessGroup,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
