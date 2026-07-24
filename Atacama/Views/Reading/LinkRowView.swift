//
//  LinkRowView.swift
//  Atacama
//
//  One row in the links feed: the shared link's title and domain, plus the
//  sharer's comment and any pulled quote. Rendered from GET /api/links.
//

import SwiftUI

struct LinkRowView: View {
    let link: LinkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(link.title.isEmpty ? link.domain : link.title)
                .font(.headline)
                .lineLimit(2)
            Text(link.domain)
                .font(.caption)
                .foregroundStyle(.tint)
            if !link.comment.isEmpty {
                Text(link.comment)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
            }
            if !link.quote.isEmpty {
                Text(link.quote)
                    .font(.callout)
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack {
                Text(link.topic.name)
                Spacer()
                Text(link.publishedAt.formatted(date: .abbreviated, time: .omitted))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
