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
    /// Authentication flow this server uses: "oauth" or "password".
    var authType: String
    /// Login path opened for the OAuth flow (from the config endpoint).
    var loginPath: String
    /// Whether the server accepts photo uploads (POST /api/images) and serves the
    /// image feed. Nil for servers added before this field existed — treated as
    /// "unknown, allow" so an existing server isn't hidden until re-added.
    var supportsImages: Bool?
    /// Whether the server serves the public quotes feed (GET /api/quotes). Nil is
    /// treated as "unknown, allow", like supportsImages.
    var supportsQuotes: Bool?

    init(
        id: UUID = UUID(),
        baseURL: String,
        name: String,
        apiBase: String,
        authType: String,
        loginPath: String,
        supportsImages: Bool? = nil,
        supportsQuotes: Bool? = nil
    ) {
        self.id = id
        self.baseURL = baseURL
        self.name = name
        self.apiBase = apiBase
        self.authType = authType
        self.loginPath = loginPath
        self.supportsImages = supportsImages
        self.supportsQuotes = supportsQuotes
    }

    /// Whether the app can currently sign in to this server. Only OAuth is wired
    /// up for now; password servers are shown but not yet signable.
    var supportsSignIn: Bool { authType == "oauth" }

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

    /// Whether to offer photo upload for this server. Absent capability info
    /// (older stored servers) is treated as allowed; only an explicit false hides it.
    var offersImages: Bool { supportsImages != false }
    /// Whether to offer the quotes feed for this server (same nil-as-allowed rule).
    var offersQuotes: Bool { supportsQuotes != false }

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
            supportsQuotes: supportsQuotes
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

    struct Auth: Decodable {
        let type: String
        let loginPath: String

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

    enum CodingKeys: String, CodingKey {
        case name
        case apiBase = "api_base"
        case auth
        case capabilities
    }
}
