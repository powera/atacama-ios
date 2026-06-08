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
        case displayName
        case displayNameSnake = "display_name"
        case group
        case requiresAuth
        case requiresAuthSnake = "requires_auth"
    }

    init(name: String, displayName: String? = nil, group: String = "", requiresAuth: Bool = false) {
        self.name = name
        self.displayName = displayName?.isEmpty == false ? displayName! : name
        self.group = group
        self.requiresAuth = requiresAuth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let displayName = try container.decodeIfPresent(String.self, forKey: .displayNameSnake)
            ?? container.decodeIfPresent(String.self, forKey: .displayName)
        let group = try container.decodeIfPresent(String.self, forKey: .group) ?? ""
        let requiresAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresAuthSnake)
            ?? container.decodeIfPresent(Bool.self, forKey: .requiresAuth)
            ?? false

        self.init(name: name, displayName: displayName, group: group, requiresAuth: requiresAuth)
    }
}

/// Response shape of GET /api/channels. Also accepts a bare channel array so the
/// picker can diagnose older/alternate servers instead of silently appearing empty.
struct ChannelList: Decodable {
    let channels: [Channel]
    /// Channel name pre-selected in the picker, if the server provides one.
    let `default`: String?

    enum CodingKeys: String, CodingKey {
        case channels
        case `default`
    }

    init(channels: [Channel], defaultChannel: String? = nil) {
        self.channels = channels
        self.default = defaultChannel
    }

    init(from decoder: Decoder) throws {
        if let bareChannels = try? [Channel](from: decoder) {
            self.init(channels: bareChannels)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let channels = try container.decode([Channel].self, forKey: .channels)
        let defaultChannel = try container.decodeIfPresent(String.self, forKey: .default)
        self.init(channels: channels, defaultChannel: defaultChannel)
    }
}
