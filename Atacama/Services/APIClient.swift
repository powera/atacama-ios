//
//  APIClient.swift
//  Atacama
//
//  JSON HTTP client for the atacama authoring API. Modeled on trakaido's APIClient,
//  extended with a POST helper. The bearer token comes from SessionManager (backed
//  by the Keychain). See docs/backend-api.md.
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

/// HTTP client for the atacama JSON API.
final class APIClient {
    static let shared = APIClient()

    /// Base server URL. Configurable for local development against `launch.py`.
    var baseURL: String = "https://earlyversion.com"

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    // MARK: - GET

    func get<T: Decodable>(
        _ endpoint: String,
        queryParams: [String: String]? = nil
    ) async throws -> T {
        guard var components = URLComponents(string: fullURL(for: endpoint)) else {
            throw APIError.invalidURL
        }
        if let queryParams {
            components.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        await applyCommonHeaders(to: &request)

        NSLog("🌐 GET \(url.absoluteString)")
        return try await send(request)
    }

    // MARK: - POST

    /// POST a JSON body and decode the JSON response.
    func post<Body: Encodable, T: Decodable>(
        _ endpoint: String,
        body: Body
    ) async throws -> T {
        guard let url = URL(string: fullURL(for: endpoint)) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        await applyCommonHeaders(to: &request)
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            throw APIError.decodingFailed(error)
        }

        NSLog("🌐 POST \(url.absoluteString)")
        return try await send(request)
    }

    // MARK: - Helpers

    private func fullURL(for endpoint: String) -> String {
        endpoint.hasPrefix("http") ? endpoint : baseURL + endpoint
    }

    private func applyCommonHeaders(to request: inout URLRequest) async {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await SessionManager.shared.token {
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

// MARK: - Authoring endpoints

extension APIClient {
    /// Render AML to HTML without persisting. POST /api/preview.
    func preview(content: String) async throws -> String {
        let response: PreviewResponse = try await post(
            "/api/preview",
            body: PreviewRequest(content: content)
        )
        return response.processedContent
    }

    /// Create a post. POST /api/messages.
    func createMessage(_ payload: MessageDraftPayload) async throws -> CreatedMessage {
        try await post("/api/messages", body: payload)
    }

    /// List channels the user may post to. GET /api/channels.
    func channels() async throws -> ChannelList {
        try await get("/api/channels")
    }

    /// Revoke the current token. POST /api/logout.
    func logout() async throws {
        struct LogoutResponse: Decodable { let success: Bool }
        let _: LogoutResponse = try await post("/api/logout", body: [String: String]())
    }
}
