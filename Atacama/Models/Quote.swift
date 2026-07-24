//
//  Quote.swift
//  Atacama
//
//  A tracked quotation published on a newslettr site, decoded from the public
//  feed (GET /api/quotes). Quotes have no draft concept — they are curated by
//  hand or auto-extracted from posts on publish. Reading is public — no token.
//  See docs/backend-api.md.
//

import Foundation

/// A tracked quotation as it appears in the quotes feed.
struct Quote: Identifiable, Decodable, Hashable {
    /// Quote GUID (quo_…).
    let id: String
    let text: String
    /// One of: personal, reference, snowclone, historical, technical.
    let quoteType: String
    let originalAuthor: String
    let source: String
    /// A free-form date string (e.g. "1964"); not a calendar date.
    let quoteDate: String
    let commentary: String

    enum CodingKeys: String, CodingKey {
        case id, text
        case quoteType = "quote_type"
        case originalAuthor = "original_author"
        case source
        case quoteDate = "quote_date"
        case commentary
    }
}

/// Response shape of GET /api/quotes.
struct QuoteListResponse: Decodable {
    let quotes: [Quote]
}
