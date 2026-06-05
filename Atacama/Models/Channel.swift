//
//  Channel.swift
//  Atacama
//
//  A channel the authenticated user may post to. Decoded from GET /api/channels.
//  See docs/backend-api.md.
//

import Foundation

/// A channel option for the post's channel picker.
struct Channel: Identifiable, Decodable, Hashable {
    /// Channel id, sent as the `channel` field of POST /api/messages.
    let name: String
    /// Human-readable label for the picker.
    let displayName: String
    /// Channel group, used to section the picker.
    let group: String
    /// Whether the channel is non-public (informational).
    let requiresAuth: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case group
        case requiresAuth = "requires_auth"
    }
}

/// Response shape of GET /api/channels.
struct ChannelList: Decodable {
    let channels: [Channel]
    /// Channel name pre-selected in the picker.
    let `default`: String
}
