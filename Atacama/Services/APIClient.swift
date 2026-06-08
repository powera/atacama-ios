//
//  APIClient.swift
//  Atacama
//
//  JSON HTTP client for the atacama / newslettr authoring API. Modeled on trakaido's
//  APIClient, extended with a POST helper. The app can target multiple servers, so
//  every authenticated call takes an explicit `ServerConfig`: the request is sent to
//  that server's `apiBase` with that server's bearer token (from the Keychain).
//  See docs/backend-api.md.
//

import Foundation

/// API errors.
enum APIError: LocalizedError {
    case invalidURL
    case decodingFailed(Error)
    case httpError(Int, String)
    case networkError(Error)
    case unauthorized
    case serverError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case let .decodingFailed(error):
            return "Failed to decode response: \(error.localizedDescription)"
        case let .httpError(code, message):
            return "HTTP Error \(code): \(message)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized — please sign in again"
        case .serverError:
            return "Server error — please try again later"
        }
    }
}

/// HTTP client for the atacama / newslettr JSON API.
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    // MARK: - GET

    /// GET against a specific server, attaching that server's bearer token.
    func get<T: Decodable>(
        _ endpoint: String,
        on server: ServerConfig,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        try await get(endpoint, base: server.apiBase, token: KeychainStore.loadToken(for: server.id), queryParams: queryParams)
    }

    /// GET against an explicit base URL with an optional token (used for the
    /// unauthenticated config fetch when adding a server).
    private func get<T: Decodable>(
        _ endpoint: String,
        base: String,
        token: String?,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: fullURL(for: endpoint, base: base)) else {
            throw APIError.invalidURL
        }
        if let queryParams {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyCommonHeaders(to: &request, token: token)

        NSLog("🌐 GET \(url.absoluteString)")
        return try await send(request)
    }

    // MARK: - POST

    /// POST a JSON body to a specific server and decode the JSON response.
    func post<Body: Encodable, T: Decodable>(
        _ endpoint: String,
        on server: ServerConfig,
        body: Body
    ) async throws -> T {
        guard let url = URL(string: fullURL(for: endpoint, base: server.apiBase)) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyCommonHeaders(to: &request, token: KeychainStore.loadToken(for: server.id))
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decodingFailed(error)
        }

        NSLog("🌐 POST \(url.absoluteString)")
        return try await send(request)
    }

    // MARK: - Helpers

    private func fullURL(for endpoint: String, base: String) -> String {
        let urlString = endpoint.hasPrefix("http")
            ? endpoint
            : TransportSecurity.normalizedBaseURL(base) + endpoint
        return TransportSecurity.normalizedURLString(urlString)
    }

    private func applyCommonHeaders(to request: inout URLRequest, token: String?) {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.serverError
            }

            switch httpResponse.statusCode {
            case 200 ... 299:
                break
            case 401:
                NSLog("❌ 401 Unauthorized")
                throw APIError.unauthorized
            case 400 ... 499:
                let message = String(data: data, encoding: .utf8) ?? "Client error"
                throw APIError.httpError(httpResponse.statusCode, message)
            case 500 ... 599:
                throw APIError.serverError
            default:
                throw APIError.httpError(httpResponse.statusCode, "Unknown error")
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingFailed(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }
}

// MARK: - Discovery

extension APIClient {
    /// Fetch a server's self-describing config (unauthenticated). Used when adding
    /// a server by base URL. GET <baseURL>/api/atacama-config.
    func serverConfig(baseURL: String) async throws -> ServerConfigResponse {
        let base = TransportSecurity.normalizedBaseURL(baseURL)
        return try await get("/api/atacama-config", base: base, token: nil)
    }
}

// MARK: - Authoring endpoints

extension APIClient {
    /// Render AML to HTML without persisting. POST /api/preview.
    func preview(content: String, on server: ServerConfig) async throws -> String {
        let response: PreviewResponse = try await post(
            "/api/preview",
            on: server,
            body: PreviewRequest(content: content)
        )
        return response.processedContent
    }

    /// Create a post. POST /api/messages.
    func createMessage(_ payload: MessageDraftPayload, on server: ServerConfig) async throws -> CreatedMessage {
        try await post("/api/messages", on: server, body: payload)
    }

    /// List channels the user may post to on a server. GET /api/channels.
    func channels(on server: ServerConfig) async throws -> ChannelList {
        try await get("/api/channels", on: server)
    }

    /// Revoke the current token on a server. POST /api/logout.
    func logout(on server: ServerConfig) async throws {
        struct LogoutResponse: Decodable { let success: Bool }
        let _: LogoutResponse = try await post("/api/logout", on: server, body: [String: String]())
    }
}
