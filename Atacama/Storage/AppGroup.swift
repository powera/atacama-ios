//
//  AppGroup.swift
//  Atacama
//
//  The shared App Group that lets the main app and the Share Extension see the
//  same signed-in servers and auth tokens. The extension has no UI for signing
//  in; it reuses whatever the app has stored. Both targets carry the
//  `com.apple.security.application-groups` entitlement for this identifier, which
//  also serves as the Keychain access group (an app group may be used as a
//  keychain-access-group without the team prefix). See KeychainStore / ServerStore.
//

import Foundation

enum AppGroup {
    /// App Group identifier shared by the app and the Share Extension. Must match
    /// the `com.apple.security.application-groups` entitlement on both targets.
    static let identifier = "group.com.yevaud.atacama"

    /// Shared UserDefaults suite backing the (non-secret) server list and default
    /// target, so the extension reads the same configuration the app wrote.
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard
}
