//
//  Post.swift
//  Atacama
//
//  Read-only published-post models, decoded from newslettr's public feed API
//  (GET /api/posts and GET /api/posts/{guid}). The list is intentionally light
//  — a summary per post — and the full rendered body is fetched on demand for
//  the detail view. See docs/backend-api.md.
//

import Foundation

/// A topic reference carried by feed posts (the post's channel).
struct TopicRef: Decodable, Hashable {
    let id: String
    let name: String
}

/// A flat "see also" link to another post, shown on the detail view.
struct PostRef: Decodable, Hashable {
    let id: String
    let title: String
}

/// A post as it appears in the feed list: enough to render a row without the body.
struct PostSummary: Identifiable, Decodable, Hashable {
    /// Post GUID, used to fetch the detail (GET /api/posts/{guid}).
    let id: String
    let title: String
    let excerpt: String
    let publishedAt: Date
    let topic: TopicRef
    /// Reader-facing absolute URL of the post.
    let url: String

    enum CodingKeys: String, CodingKey {
        case id, title, excerpt
        case publishedAt = "published_at"
        case topic, url
    }
}

/// A single post with its server-rendered HTML body, for the detail view.
struct PostDetail: Identifiable, Decodable {
    let id: String
    let title: String
    /// Server-rendered HTML (from the post's AML source); shown as-is in HTMLView.
    let bodyHTML: String
    let publishedAt: Date
    let author: String
    let topic: TopicRef
    /// Flat "see also" links to other posts; may be empty.
    let references: [PostRef]
    let url: String

    enum CodingKeys: String, CodingKey {
        case id, title
        case bodyHTML = "body_html"
        case publishedAt = "published_at"
        case author, topic, references, url
    }
}

/// Response shape of GET /api/posts.
struct PostListResponse: Decodable {
    let posts: [PostSummary]
}
