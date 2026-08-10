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
    /// Channel group, used to section the picker. Newslettr sends "" until the
    /// topic→site mapping is a real reverse lookup, so treat it as optional.
    let group: String
    /// Whether the channel is non-public. Newslettr now reports the channel's
    /// real access level here (it used to hardcode false), so this can be true
    /// for a restricted channel the user does hold a grant for — the list is
    /// already filtered to what the caller may post to, so it labels rather than
    /// excludes.
    let requiresAuth: Bool

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case displayName = "display_name"
        case group
        case requiresAuth = "requires_auth"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? name
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? ""
        requiresAuth = try c.decodeIfPresent(Bool.self, forKey: .requiresAuth) ?? false
    }
}

/// Response shape of GET /api/channels.
///
/// Newslettr answers with a `topics` key (its native spelling); atacama used
/// `channels`. Both are accepted so one client decodes either backend — the same
/// rule the Share Extension's `TopicsResponse` already follows.
struct ChannelList: Decodable {
    let channels: [Channel]
    /// Channel name pre-selected in the picker. Absent when the server offers no
    /// channels at all.
    let `default`: String?

    enum CodingKeys: String, CodingKey {
        case topics, channels
        case `default`
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        channels = (try? c.decode([Channel].self, forKey: .topics))
            ?? (try? c.decode([Channel].self, forKey: .channels))
            ?? []
        `default` = try? c.decodeIfPresent(String.self, forKey: .default)
    }
}
