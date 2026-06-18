//
//  PostDetailView.swift
//  Atacama
//
//  Full post view: fetches the rendered HTML body on appear and shows it in the
//  shared HTMLView (the same WKWebView used for authoring previews — the app
//  never reimplements AML rendering). "See also" references navigate to other
//  posts. Reading is public, so no sign-in is required.
//

import SwiftUI

struct PostDetailView: View {
    let postID: String
    /// Title to show in the nav bar before the body loads (from the list row).
    var fallbackTitle: String = ""

    @EnvironmentObject private var reading: ReadingStore
    @State private var detail: PostDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let detail {
                loaded(detail)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView("Couldn't load post", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else {
                Color.clear
            }
        }
        .navigationTitle(detail?.title ?? fallbackTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: postID) { await load() }
    }

    @ViewBuilder
    private func loaded(_ detail: PostDetail) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(detail.topic.name)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint.opacity(0.15), in: Capsule())
                Text(detail.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail.publishedAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.top, 8)

            HTMLView(html: bodyWithReferences(detail), baseURL: reading.readingServer?.baseURL)
        }
    }

    /// Append the "see also" references as a small HTML list after the body, so
    /// they render inline with the post in the same web view. Each links to the
    /// reader-facing post URL.
    private func bodyWithReferences(_ detail: PostDetail) -> String {
        guard !detail.references.isEmpty else { return detail.bodyHTML }
        let items = detail.references
            .map { "<li>\($0.title)</li>" }
            .joined()
        return detail.bodyHTML + "<hr><h3>See also</h3><ul>\(items)</ul>"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            detail = try await reading.detail(for: postID)
            errorMessage = nil
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
