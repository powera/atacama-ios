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
enum KeychainStore {
    /// Service identifier for our Keychain items.
    private static let service = "com.atacama.ios.auth"

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
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
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
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
