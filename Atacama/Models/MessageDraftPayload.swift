//
//  MessageDraftPayload.swift
//  Atacama
//
//  Request/response bodies for the authoring endpoints. See docs/backend-api.md.
//

import Foundation

/// Body of POST /api/messages.
struct MessageDraftPayload: Encodable {
    let subject: String
    /// Raw AML markup (colortext footnotes embedded inline).
    let content: String
    /// Optional; server defaults to its configured default channel when nil.
    let channel: String?
    /// Optional parent message id for threaded chains.
    let parentId: Int?

    enum CodingKeys: String, CodingKey {
        case subject
        case content
        case channel
        case parentId = "parent_id"
    }
}

/// Response of POST /api/messages (201).
struct CreatedMessage: Decodable {
    let id: Int
    let url: String
    let processedContent: String

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case processedContent = "processed_content"
    }
}

/// Body of POST /api/preview.
struct PreviewRequest: Encodable {
    let content: String
}

/// Response of POST /api/preview.
struct PreviewResponse: Decodable {
    let processedContent: String

    enum CodingKeys: String, CodingKey {
        case processedContent = "processed_content"
    }
}
