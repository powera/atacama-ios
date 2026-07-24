//
//  LinkItem.swift
//  Atacama
//
//  A shared link published on a newslettr site, decoded from the public feed
//  (GET /api/links). A link is a URL plus an optional pulled quote and the
//  sharer's comment, filed under a topic. Reading is public — no token.
//  See docs/backend-api.md.
//

import Foundation

/// A published shared link as it appears in the links feed.
struct LinkItem: Identifiable, Decodable, Hashable {
    /// Link GUID (lnk_…).
    let id: String
    let url: String
    /// The link's host, precomputed by the server for display.
    let domain: String
    let title: String
    /// A pulled excerpt from the linked article; may be empty.
    let quote: String
    /// The sharer's note on why it's worth reading; may be empty.
    let comment: String
    let publishedAt: Date
    let topic: TopicRef

    enum CodingKeys: String, CodingKey {
        case id, url, domain, title, quote, comment
        case publishedAt = "published_at"
        case topic
    }
}

/// Response shape of GET /api/links.
struct LinkListResponse: Decodable {
    let links: [LinkItem]
}
