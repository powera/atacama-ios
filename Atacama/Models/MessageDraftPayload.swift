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
///
/// `id` is decoded as a string so the one client handles both backends: atacama
/// returns an integer message id, newslettr returns a string GUID (e.g. `pst_…`).
struct CreatedMessage: Decodable {
    let id: String
    let url: String
    let processedContent: String

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case processedContent = "processed_content"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        processedContent = try container.decode(String.self, forKey: .processedContent)
        // Accept either a JSON string (newslettr GUID) or number (atacama id).
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
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
