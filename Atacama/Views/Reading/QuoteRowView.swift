//
//  QuoteRowView.swift
//  Atacama
//
//  One row in the quotes feed: the quotation, its attribution (author/source),
//  the type badge, and any curator commentary. Rendered from GET /api/quotes.
//

import SwiftUI

struct QuoteRowView: View {
    let quote: Quote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("“\(quote.text)”")
                .font(.body)
                .italic()
            if !attribution.isEmpty {
                Text(attribution)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if !quote.commentary.isEmpty {
                Text(quote.commentary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !quote.quoteType.isEmpty {
                Text(quote.quoteType.capitalized)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    /// "— Author, Source (date)" from whichever attribution fields are present.
    private var attribution: String {
        var parts: [String] = []
        if !quote.originalAuthor.isEmpty { parts.append(quote.originalAuthor) }
        if !quote.source.isEmpty { parts.append(quote.source) }
        if !quote.quoteDate.isEmpty { parts.append(quote.quoteDate) }
        return parts.isEmpty ? "" : "— " + parts.joined(separator: ", ")
    }
}
