//
//  PostRowView.swift
//  Atacama
//
//  Compact feed cell: title, excerpt, topic badge, and relative publish date.
//  Kept light to match the "more data, faster" reading goal — the full body is
//  loaded only when the row is opened (PostDetailView).
//

import SwiftUI

struct PostRowView: View {
    let post: PostSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(post.title)
                .font(.headline)
                .lineLimit(2)

            if !post.excerpt.isEmpty {
                Text(post.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                Text(post.topic.name)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                Spacer()
                Text(post.publishedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
