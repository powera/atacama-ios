//
//  ServerConfig.swift
//  Atacama
//
//  A backend the app can author against. The app supports one or more newslettr
//  servers (newslettr.com is seeded as the default; others, such as a local dev
//  instance, are added by base URL) and describes each by its
//  GET /api/atacama-config endpoint. The user picks a server+channel target per
//  post. See docs/backend-api.md.
//

import Foundation

/// Transport-security normalization for backend URLs. ATS blocks plain HTTP on
/// device, so non-local HTTP URLs are upgraded to HTTPS before they are stored
/// or requested. Localhost is left untouched for simulator/development servers.
enum TransportSecurity {
    static func normalizedBaseURL(_ urlString: String) -> String {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutTrailingSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return normalizedURLString(withoutTrailingSlash)
    }

    static func normalizedURLString(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString),
              components.scheme?.lowercased() == "http",
              let host = components.host,
              !isLocalhost(host)
        else {
            return urlString
        }

        components.scheme = "https"
        return components.string ?? urlString
    }

    private static func isLocalhost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost == "localhost"
            || normalizedHost == "127.0.0.1"
            || normalizedHost == "::1"
    }
}

/// A configured backend server, populated from its /api/atacama-config response.
struct ServerConfig: Identifiable, Codable, Hashable {
    let id: UUID
    /// The base URL the user entered (used to fetch /api/atacama-config).
    var baseURL: String
    /// Human-readable name from the config endpoint (falls back to the host).
    var name: String
    /// Absolute API base the client prefixes onto "/api/..." paths.
    var apiBase: String
    /// Authentication flow this server uses: "oauth", "password", or "none".
    /// A reader-only content domain (blog.pow3.com, earlyversion.com, …) reports
    /// "none": it serves the public feeds and has no sign-in to offer.
    var authType: String
    /// Login path opened for the OAuth flow (from the config endpoint). Empty for
    /// an auth type that has no login page, which is why it is not optional here:
    /// callers want "nothing to open", not "unknown".
    var loginPath: String
    /// Whether the server accepts photo uploads (POST /api/images) and serves the
    /// image feed. Nil for servers added before this field existed — treated as
    /// "unknown, allow" so an existing server isn't hidden until re-added.
    var supportsImages: Bool?
    /// Whether the server serves the public quotes feed (GET /api/quotes). Nil is
    /// treated as "unknown, allow", like supportsImages.
    var supportsQuotes: Bool?
    /// Whether the server accepts posts (POST /api/messages) and serves the
    /// channel list. False on a reader-only content domain, which advertises
    /// `messages: false` because authoring lives on the publisher. Nil is
    /// "unknown, allow", like supportsImages.
    var supportsMessages: Bool?
    /// Whether the server renders AML previews (POST /api/preview). Nil is
    /// "unknown, allow", like supportsImages.
    var supportsPreview: Bool?
    /// Absolute URL of this server's AML stylesheet, from `styles.colortext` in
    /// the discovery document. Nil on a server added before the field existed
    /// (or one that does not report it); HTMLView falls back to trying the two
    /// known paths. See `AMLStylesheet`.
    var colortextCSSURL: String?

    init(
        id: UUID = UUID(),
        baseURL: String,
        name: String,
        apiBase: String,
        authType: String,
        loginPath: String,
        supportsImages: Bool? = nil,
        supportsQuotes: Bool? = nil,
        supportsMessages: Bool? = nil,
        supportsPreview: Bool? = nil,
        colortextCSSURL: String? = nil
    ) {
        self.id = id
        self.baseURL = baseURL
        self.name = name
        self.apiBase = apiBase
        self.authType = authType
        self.loginPath = loginPath
        self.supportsImages = supportsImages
        self.supportsQuotes = supportsQuotes
        self.supportsMessages = supportsMessages
        self.supportsPreview = supportsPreview
        self.colortextCSSURL = colortextCSSURL
    }

    /// Whether the app can currently sign in to this server. Only OAuth is wired
    /// up for now; password servers are shown but not yet signable. A server that
    /// reports no login path has nothing to open even if it names a flow, so both
    /// halves are required — otherwise a read-only domain would present a sign-in
    /// button that loads its bare home page.
    var supportsSignIn: Bool { authType == "oauth" && !loginPath.isEmpty }

    /// Whether this server is a reader-only content domain: it advertises no
    /// sign-in flow at all. Distinct from "sign-in not wired up yet" (a password
    /// server), which is a client gap rather than the server's nature.
    var isReadOnly: Bool { authType == "none" }

    /// Whether this server is the one at `baseURL`. Duplicate detection compares
    /// the *identity* of the URL rather than the exact string the user typed, so
    /// "newslettr.com", "https://NEWSLETTR.com" and a trailing slash are one
    /// server and not three rows in the list.
    func matches(baseURL other: String) -> Bool {
        ServerConfig.identity(of: self.baseURL) == ServerConfig.identity(of: other)
    }

    /// Canonical comparison key for a base URL: scheme-insensitive host plus port
    /// and path, lowercased, without a trailing slash. Scheme is excluded because
    /// TransportSecurity may have upgraded one of the two to https.
    static func identity(of urlString: String) -> String {
        let normalized = TransportSecurity.normalizedBaseURL(urlString)
        guard let components = URLComponents(string: normalized), let host = components.host else {
            return normalized.lowercased()
        }
        var key = host.lowercased()
        if let port = components.port {
            key += ":\(port)"
        }
        let path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        return key + path.lowercased()
    }

    /// Whether to offer the image feed for this server. Absent capability info
    /// (older stored servers) is treated as allowed; only an explicit false hides it.
    ///
    /// This is the *reading* capability. A reader-only domain reports
    /// `images: true` because it serves the photo feed while accepting no
    /// uploads, so the Photo tab must gate on `offersAuthoring` as well.
    var offersImages: Bool { supportsImages != false }
    /// Whether to offer the quotes feed for this server (same nil-as-allowed rule).
    var offersQuotes: Bool { supportsQuotes != false }
    /// Whether this server can accept content at all: it takes posts and can list
    /// the channels to file them under. A reader-only content domain reports
    /// `messages: false`, and every authoring POST against it 404s, so it must not
    /// appear as a post target.
    var offersAuthoring: Bool { supportsMessages != false }
    /// Whether to ask this server to render an AML preview (same nil-as-allowed rule).
    var offersPreview: Bool { supportsPreview != false }
    /// Whether to offer photo *upload* here — authoring, so it needs both the
    /// image capability and the ability to accept content.
    var offersImageUpload: Bool { offersImages && offersAuthoring }

    /// Copy with ATS-safe base URLs. This also fixes servers saved before the
    /// client enforced HTTPS for non-local backends.
    func usingSecureTransportDefaults() -> ServerConfig {
        ServerConfig(
            id: id,
            baseURL: TransportSecurity.normalizedBaseURL(baseURL),
            name: name,
            apiBase: TransportSecurity.normalizedBaseURL(apiBase),
            authType: authType,
            loginPath: loginPath,
            supportsImages: supportsImages,
            supportsQuotes: supportsQuotes,
            supportsMessages: supportsMessages,
            supportsPreview: supportsPreview,
            colortextCSSURL: colortextCSSURL.map(TransportSecurity.normalizedURLString)
        )
    }
}

/// Where a post is sent: a configured server plus an optional channel name.
/// `channel` is nil to use the server's default channel.
struct PostTarget: Codable, Hashable {
    var serverID: UUID
    var channel: String?
}

/// Decodable shape of GET /api/atacama-config, served by the newslettr backend.
/// The endpoint keeps its historical name — it is a live contract with shipped
/// clients.
struct ServerConfigResponse: Decodable {
    let name: String
    let apiBase: String
    let auth: Auth
    let capabilities: Capabilities?
    /// Where this host serves the assets a client needs to render server HTML.
    /// Absent on older backends.
    let styles: Styles?

    struct Auth: Decodable {
        let type: String
        /// Absent when the server offers no sign-in. A reader-only content domain
        /// answers `{"type": "none"}` with no `login_path` at all, so requiring
        /// this key made discovery throw for every content domain — the one thing
        /// those hosts exist to support.
        let loginPath: String?

        enum CodingKeys: String, CodingKey {
            case type
            case loginPath = "login_path"
        }
    }

    struct Capabilities: Decodable {
        let preview: Bool?
        let messages: Bool?
        let channels: Bool?
        /// Whether the server accepts shared links via POST /api/links (backs the
        /// Share Extension). Absent on older backends.
        let links: Bool?
        /// Whether the server accepts photo uploads and serves the image feed.
        let images: Bool?
        /// Whether the server serves the public quotes feed.
        let quotes: Bool?
    }

    /// Stylesheet URLs the server publishes for its own rendered HTML.
    struct Styles: Decodable {
        /// Absolute URL of the AML stylesheet. Which path serves it differs per
        /// app and only one is public per host — /reader/static/ is anonymous on
        /// a content domain but sits behind the author gate on the publisher —
        /// so the server names it rather than the client assuming.
        let colortext: String?
    }

    enum CodingKeys: String, CodingKey {
        case name
        case apiBase = "api_base"
        case auth
        case capabilities
        case styles
    }
}
