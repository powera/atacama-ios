//
//  ReadingStore.swift
//  Atacama
//
//  Singleton owning the read-only feed state: the content loaded from a newslettr
//  server, the topic/date filters applied to it, and the channels the reader has
//  muted. Reading is public, so this works without sign-in — it targets a
//  configured server by base URL and hits the public GET /api/{posts,images,links,
//  quotes} feeds. Mirrors DraftStore's @MainActor/@Published conventions.
//  See docs/backend-api.md.
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

    /// Whether muting a channel hides anything here. Posts, photos and links each
    /// carry a topic; quotes have none at all in the API, so they are never hidden.
    var respectsMuting: Bool { self != .quotes }
}

@MainActor
final class ReadingStore: ObservableObject {
    static let shared = ReadingStore()

    /// The content type currently shown.
    @Published var kind: ReadingKind = .posts

    // Loaded content, per kind, exactly as the server returned it. Only the
    // active kind's collection is populated. Views read the muted-channel-aware
    // `posts` / `images` / `links` below instead: keeping the unfiltered lists
    // here is what lets a muted channel still be named — and un-muted — in the
    // mute UI after it has disappeared from the feed.
    @Published private(set) var allPosts: [PostSummary] = []
    @Published private(set) var allImages: [AtacamaImage] = []
    @Published private(set) var allLinks: [LinkItem] = []
    /// Quotes carry no topic, so there is nothing to filter and no `allQuotes`.
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

    // MARK: - Muted channels

    /// Channel slugs hidden from the reading feed, keyed by server id.
    ///
    /// This lives on the device rather than on the server because the read feeds
    /// are **public**: `GET /api/posts` and friends carry no token, so the server
    /// has no user identity to hang a per-reader preference on. It is also not
    /// the same thing as newslettr's `topics.access_level` / `topic_access`,
    /// which is access control — hiding a channel there hides it from every
    /// reader on the web, not just from this phone.
    ///
    /// Keyed per server because a slug only means something within one server's
    /// topic namespace, and because a server-persisted version would be
    /// per-user-per-server too.
    @Published private(set) var mutedChannels: [UUID: Set<String>] = [:]

    /// Every channel seen in a server's feeds so far, keyed by server id, in the
    /// order first encountered. Accumulated on each load purely so the mute UI
    /// can list channels with their display names — including ones the current
    /// filters or an existing mute have removed from the feed.
    @Published private(set) var knownChannels: [UUID: [TopicRef]] = [:]

    /// Non-secret reading preferences sit in the same App Group suite the server
    /// list uses, so the app has one defaults suite rather than two. Nothing in
    /// the Share Extension reads them.
    private let defaults: UserDefaults
    private static let mutedChannelsKey = "atacama.reading.mutedChannels"
    private static let knownChannelsKey = "atacama.reading.knownChannels"

    private init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        mutedChannels = Self.decodeMuted(from: defaults, key: Self.mutedChannelsKey)
        knownChannels = Self.decodeKnown(from: defaults, key: Self.knownChannelsKey)
    }

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

    // MARK: - Visible content

    /// Muted slugs on the current reading server.
    private var mutedSlugs: Set<String> {
        guard let server = readingServer else { return [] }
        return mutedChannels[server.id] ?? []
    }

    /// Whether a channel slug is muted on the current reading server.
    func isMuted(_ slug: String) -> Bool { mutedSlugs.contains(slug) }

    /// Whether anything is muted on the current reading server.
    var hasMutedChannels: Bool { !mutedSlugs.isEmpty }

    /// Posts to show: the loaded feed minus every muted channel.
    var posts: [PostSummary] {
        let muted = mutedSlugs
        return muted.isEmpty ? allPosts : allPosts.filter { !muted.contains($0.topic.id) }
    }

    /// Photos to show, minus every muted channel.
    var images: [AtacamaImage] {
        let muted = mutedSlugs
        return muted.isEmpty ? allImages : allImages.filter { !muted.contains($0.topic.id) }
    }

    /// Links to show, minus every muted channel.
    var links: [LinkItem] {
        let muted = mutedSlugs
        return muted.isEmpty ? allLinks : allLinks.filter { !muted.contains($0.topic.id) }
    }

    /// Whether the active kind currently has nothing left to show. Asked of the
    /// *visible* content, so muting every loaded channel reads as empty rather
    /// than as a list that renders nothing.
    var isEmpty: Bool {
        switch kind {
        case .posts: return posts.isEmpty
        case .photos: return images.isEmpty
        case .links: return links.isEmpty
        case .quotes: return quotes.isEmpty
        }
    }

    /// Whether the feed is hiding content the server did return, because every
    /// loaded item is in a muted channel. Distinguishes "nothing published" from
    /// "you muted all of it", which are the same empty list otherwise.
    var isEmptyOnlyBecauseOfMuting: Bool {
        guard isEmpty, kind.respectsMuting else { return false }
        switch kind {
        case .posts: return !allPosts.isEmpty
        case .photos: return !allImages.isEmpty
        case .links: return !allLinks.isEmpty
        case .quotes: return false
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

    /// Topics offered in the filter picker, derived from the loaded content so the
    /// picker works without a token (unlike GET /api/channels). De-duplicated by
    /// slug, muted channels dropped — offering to filter *to* a channel the reader
    /// has hidden would only ever produce an empty feed — and sorted by name.
    var availableTopics: [TopicRef] {
        let refs: [TopicRef]
        switch kind {
        case .photos: refs = allImages.map(\.topic)
        case .links: refs = allLinks.map(\.topic)
        default: refs = allPosts.map(\.topic)
        }
        let muted = mutedSlugs
        return Self.deduplicated(refs).filter { !muted.contains($0.id) }
    }

    /// Channels the mute UI lists for the current server: everything seen in this
    /// server's feeds so far, plus any muted slug that predates the cache (shown
    /// by its slug), so a mute is always reversible.
    var manageableChannels: [TopicRef] {
        guard let server = readingServer else { return [] }
        var refs = knownChannels[server.id] ?? []
        let known = Set(refs.map(\.id))
        for slug in (mutedChannels[server.id] ?? []).sorted() where !known.contains(slug) {
            refs.append(TopicRef(id: slug, name: slug))
        }
        return Self.deduplicated(refs)
    }

    // MARK: - Mutations

    /// Mute or un-mute a channel on the current reading server. Takes effect
    /// immediately without a reload — the feed is filtered from content already
    /// in hand — and clears the topic filter if it pointed at the channel being
    /// muted, which would otherwise leave the feed empty with no visible cause.
    func setMuted(_ muted: Bool, channel slug: String) {
        guard let server = readingServer else { return }
        var slugs = mutedChannels[server.id] ?? []
        if muted {
            guard slugs.insert(slug).inserted else { return }
            if selectedTopic?.id == slug { selectedTopic = nil }
        } else {
            guard slugs.remove(slug) != nil else { return }
        }
        if slugs.isEmpty {
            mutedChannels.removeValue(forKey: server.id)
        } else {
            mutedChannels[server.id] = slugs
        }
        persistMutedChannels()
    }

    /// Un-mute every channel on the current reading server.
    func unmuteAll() {
        guard let server = readingServer, mutedChannels[server.id] != nil else { return }
        mutedChannels.removeValue(forKey: server.id)
        persistMutedChannels()
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
                allPosts = try await APIClient.shared.posts(
                    on: server, topic: selectedTopic?.id, since: since, until: until
                ).posts
                remember(allPosts.map(\.topic), for: server.id)
            case .photos:
                allImages = try await APIClient.shared.images(
                    on: server, topic: selectedTopic?.id, since: since, until: until
                ).images
                remember(allImages.map(\.topic), for: server.id)
            case .links:
                allLinks = try await APIClient.shared.links(on: server).links
                remember(allLinks.map(\.topic), for: server.id)
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
        allPosts = []
        allImages = []
        allLinks = []
        quotes = []
    }

    /// Fold the topics of a freshly loaded feed into the per-server channel cache.
    /// Only new slugs are appended, so the cache keeps first-seen order and a
    /// load that returns nothing new writes nothing.
    private func remember(_ refs: [TopicRef], for serverID: UUID) {
        var cached = knownChannels[serverID] ?? []
        var slugs = Set(cached.map(\.id))
        var added = false
        for ref in refs where !ref.id.isEmpty && slugs.insert(ref.id).inserted {
            cached.append(ref)
            added = true
        }
        guard added else { return }
        knownChannels[serverID] = cached
        persistKnownChannels()
    }

    /// De-duplicate topic refs by slug, keeping the first of each, sorted by
    /// display name the way a picker wants them.
    private static func deduplicated(_ refs: [TopicRef]) -> [TopicRef] {
        var seen = Set<String>()
        var topics: [TopicRef] = []
        for ref in refs where seen.insert(ref.id).inserted {
            topics.append(ref)
        }
        return topics.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Persistence

    // Both maps are keyed by server UUID, which JSONEncoder would otherwise write
    // as a flat alternating array. Converting to uuidString keys keeps the stored
    // JSON an object, so it stays readable and survives a decode of either shape.

    private func persistMutedChannels() {
        let raw = mutedChannels.reduce(into: [String: [String]]()) { out, entry in
            out[entry.key.uuidString] = entry.value.sorted()
        }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.mutedChannelsKey)
        }
    }

    private func persistKnownChannels() {
        let raw = knownChannels.reduce(into: [String: [TopicRef]]()) { out, entry in
            out[entry.key.uuidString] = entry.value
        }
        if let data = try? JSONEncoder().encode(raw) {
            defaults.set(data, forKey: Self.knownChannelsKey)
        }
    }

    private static func decodeMuted(from defaults: UserDefaults, key: String) -> [UUID: Set<String>] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return [:] }
        return raw.reduce(into: [UUID: Set<String>]()) { out, entry in
            if let id = UUID(uuidString: entry.key), !entry.value.isEmpty {
                out[id] = Set(entry.value)
            }
        }
    }

    private static func decodeKnown(from defaults: UserDefaults, key: String) -> [UUID: [TopicRef]] {
        guard let data = defaults.data(forKey: key),
              let raw = try? JSONDecoder().decode([String: [TopicRef]].self, from: data)
        else { return [:] }
        return raw.reduce(into: [UUID: [TopicRef]]()) { out, entry in
            if let id = UUID(uuidString: entry.key) {
                out[id] = entry.value
            }
        }
    }
}
