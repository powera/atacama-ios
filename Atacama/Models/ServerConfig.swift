//
//  ServerConfig.swift
//  Atacama
//
//  A backend the app can author against. The app supports one or more servers
//  (e.g. atacama at earlyversion.com and the newslettr Go backend); each is added
//  by base URL and described by its GET /api/atacama-config endpoint. The user
//  picks a server+channel target per post. See docs/backend-api.md.
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

    init(
        id: UUID = UUID(),
        baseURL: String,
        name: String,
        apiBase: String,
        authType: String,
        loginPath: String
    ) {
        self.id = id
        self.baseURL = baseURL
        self.name = name
        self.apiBase = apiBase
        self.authType = authType
        self.loginPath = loginPath
    }

    /// Whether the app can currently sign in to this server. Only OAuth is wired
    /// up for now; password servers are shown but not yet signable.
    var supportsSignIn: Bool { authType == "oauth" }

    /// Copy with ATS-safe base URLs. This also fixes servers saved before the
    /// client enforced HTTPS for non-local backends.
    func usingSecureTransportDefaults() -> ServerConfig {
        ServerConfig(
            id: id,
            baseURL: TransportSecurity.normalizedBaseURL(baseURL),
            name: name,
            apiBase: TransportSecurity.normalizedBaseURL(apiBase),
            authType: authType,
            loginPath: loginPath
        )
    }
}

/// Where a post is sent: a configured server plus an optional channel name.
/// `channel` is nil to use the server's default channel.
struct PostTarget: Codable, Hashable {
    var serverID: UUID
    var channel: String?
}

/// Decodable shape of GET /api/atacama-config, served identically by both the
/// atacama (Flask) and newslettr (Go) backends so one client targets either.
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
        /// Share Extension). Absent on older/atacama backends.
        let links: Bool?
    }

    enum CodingKeys: String, CodingKey {
        case name
        case apiBase = "api_base"
        case auth
        case capabilities
    }
}
