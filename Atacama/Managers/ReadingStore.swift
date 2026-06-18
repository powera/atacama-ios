//
//  ReadingStore.swift
//  Atacama
//
//  Singleton owning the read-only feed state: the posts loaded from a newslettr
//  server and the topic/date filters applied to them. Reading is public, so this
//  works without sign-in — it targets a configured server by base URL and hits
//  the public GET /api/posts feed. Mirrors DraftStore's @MainActor/@Published
//  conventions. See docs/backend-api.md.
//

import Combine
import Foundation

@MainActor
final class ReadingStore: ObservableObject {
    static let shared = ReadingStore()

    /// Posts currently shown, newest first.
    @Published private(set) var posts: [PostSummary] = []
    @Published private(set) var isLoading = false
    @Published var lastError: String?

    // Filters.
    /// The topic to restrict to, or nil for all topics.
    @Published var selectedTopic: TopicRef?
    /// Inclusive lower bound on a post's publish date, or nil for no bound.
    @Published var since: Date?
    /// Inclusive upper bound on a post's publish date, or nil for no bound.
    @Published var until: Date?

    private init() {}

    /// The server reads target: the default target's server if set, else the
    /// first configured server. Reading needs no token, so a server the user
    /// cannot sign into (e.g. password-auth newslettr) is still readable.
    var readingServer: ServerConfig? {
        let store = ServerStore.shared
        if let id = store.defaultTarget?.serverID, let server = store.server(id: id) {
            return server
        }
        return store.servers.first
    }

    /// Topics available for the filter picker, derived from the loaded posts so
    /// the picker works without a token (unlike GET /api/channels). De-duplicated
    /// by GUID, sorted by name.
    var availableTopics: [TopicRef] {
        var seen = Set<String>()
        var topics: [TopicRef] = []
        for post in posts where seen.insert(post.topic.id).inserted {
            topics.append(post.topic)
        }
        return topics.sorted { $0.name < $1.name }
    }

    /// Load the feed for the current filters against the reading server.
    func load() async {
        guard let server = readingServer else {
            lastError = "Add a server to read from first."
            posts = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await APIClient.shared.posts(
                on: server,
                topic: selectedTopic?.id,
                since: since,
                until: until
            )
            posts = response.posts
            lastError = nil
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Fetch a single post's full detail (rendered body) for the detail view.
    func detail(for id: String) async throws -> PostDetail {
        guard let server = readingServer else {
            throw APIError.invalidURL
        }
        return try await APIClient.shared.post(guid: id, on: server)
    }
}
