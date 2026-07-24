//
//  ReadingStore.swift
//  Atacama
//
//  Singleton owning the read-only feed state: the content loaded from a newslettr
//  server and the topic/date filters applied to it. Reading is public, so this
//  works without sign-in — it targets a configured server by base URL and hits the
//  public GET /api/{posts,images,links,quotes} feeds. Mirrors DraftStore's
//  @MainActor/@Published conventions. See docs/backend-api.md.
//

import Combine
import Foundation

/// Which content type the reading feed is showing. Posts and photos are
/// topic/date filterable; links and quotes are plain lists.
enum ReadingKind: String, CaseIterable, Identifiable {
    case posts, photos, links, quotes

    var id: String { rawValue }
    var title: String {
        switch self {
        case .posts: return "Posts"
        case .photos: return "Photos"
        case .links: return "Links"
        case .quotes: return "Quotes"
        }
    }

    var systemImage: String {
        switch self {
        case .posts: return "doc.text"
        case .photos: return "photo"
        case .links: return "link"
        case .quotes: return "quote.bubble"
        }
    }

    /// Whether the topic/date filters apply to this kind (the server endpoints only
    /// accept them for posts and images).
    var isFilterable: Bool { self == .posts || self == .photos }
}

@MainActor
final class ReadingStore: ObservableObject {
    static let shared = ReadingStore()

    /// The content type currently shown.
    @Published var kind: ReadingKind = .posts

    /// Loaded content, per kind. Only the active kind's collection is populated.
    @Published private(set) var posts: [PostSummary] = []
    @Published private(set) var images: [AtacamaImage] = []
    @Published private(set) var links: [LinkItem] = []
    @Published private(set) var quotes: [Quote] = []

    @Published private(set) var isLoading = false
    @Published var lastError: String?

    // Filters (apply to posts and photos only).
    /// The topic to restrict to, or nil for all topics.
    @Published var selectedTopic: TopicRef?
    /// Inclusive lower bound on a publish date, or nil for no bound.
    @Published var since: Date?
    /// Inclusive upper bound on a publish date, or nil for no bound.
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

    /// Whether the active kind currently has nothing loaded.
    var isEmpty: Bool {
        switch kind {
        case .posts: return posts.isEmpty
        case .photos: return images.isEmpty
        case .links: return links.isEmpty
        case .quotes: return quotes.isEmpty
        }
    }

    /// The kinds worth offering for the current reading server: posts is always
    /// available; photos/quotes follow the server's advertised capabilities.
    var availableKinds: [ReadingKind] {
        guard let server = readingServer else { return ReadingKind.allCases }
        return ReadingKind.allCases.filter { kind in
            switch kind {
            case .photos: return server.offersImages
            case .quotes: return server.offersQuotes
            default: return true
            }
        }
    }

    /// Topics available for the filter picker, derived from the loaded content so
    /// the picker works without a token (unlike GET /api/channels). De-duplicated
    /// by GUID, sorted by name.
    var availableTopics: [TopicRef] {
        let refs: [TopicRef]
        switch kind {
        case .photos: refs = images.map(\.topic)
        default: refs = posts.map(\.topic)
        }
        var seen = Set<String>()
        var topics: [TopicRef] = []
        for topic in refs where seen.insert(topic.id).inserted {
            topics.append(topic)
        }
        return topics.sorted { $0.name < $1.name }
    }

    /// Load the active kind for the current filters against the reading server.
    func load() async {
        guard let server = readingServer else {
            lastError = "Add a server to read from first."
            clearAll()
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            switch kind {
            case .posts:
                posts = try await APIClient.shared.posts(
                    on: server, topic: selectedTopic?.id, since: since, until: until
                ).posts
            case .photos:
                images = try await APIClient.shared.images(
                    on: server, topic: selectedTopic?.id, since: since, until: until
                ).images
            case .links:
                links = try await APIClient.shared.links(on: server).links
            case .quotes:
                quotes = try await APIClient.shared.quotes(on: server).quotes
            }
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

    private func clearAll() {
        posts = []
        images = []
        links = []
        quotes = []
    }
}
