//
//  ShareStore.swift
//  AtacamaShareExtension
//
//  Backing model for the Share Extension: it reuses the main app's signed-in
//  server and token (read from the shared App Group) to post a shared URL to the
//  backend's POST /api/links endpoint. The extension never signs in itself —
//  if the app has no signed-in server, sharing is unavailable until the user
//  opens Atacama and signs in.
//
//  This file deliberately duplicates a small slice of the main app's contract
//  (App Group id, Keychain service/account scheme, the ServerConfig JSON shape)
//  rather than sharing a module, to keep the extension target self-contained.
//  Keep these constants in sync with AppGroup.swift / KeychainStore.swift /
//  ServerConfig.swift in the main target.
//

import Combine
import Foundation
import Security

// MARK: - Shared App Group contract (mirrors the main app)

private enum SharedAppGroup {
    static let identifier = "group.com.yevaud.atacama"
    static let defaults = UserDefaults(suiteName: identifier) ?? .standard
    static let serversKey = "atacama.servers"
    static let defaultTargetKey = "atacama.defaultTarget"
}

/// Minimal mirror of the app's ServerConfig (default Codable keys: id, baseURL,
/// name, apiBase, authType, loginPath). Only the fields the extension needs.
struct SharedServer: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let apiBase: String
}

/// Mirror of the app's PostTarget for reading the default server selection.
private struct SharedTarget: Decodable {
    let serverID: UUID
}

/// Reads the per-server bearer token the app wrote to the shared Keychain access
/// group. Mirrors KeychainStore in the main target.
private enum SharedKeychain {
    static let service = "com.atacama.ios.auth"
    static let accessGroup = SharedAppGroup.identifier

    static func token(for serverID: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "bearer-token-\(serverID.uuidString)",
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// A topic option for the picker, decoded from GET /api/channels (newslettr
/// returns `{"topics": [...]}`; atacama returns `{"channels": [...]}` — both are
/// accepted so one extension targets either backend).
struct ShareTopic: Identifiable, Hashable {
    let id: String
    let name: String
}

enum ShareError: LocalizedError {
    case notSignedIn
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Open Atacama and sign in to a server before sharing links."
        case let .server(message):
            return message
        }
    }
}

/// Resolves the active server + token from the shared App Group and performs the
/// link share. UI state lives in ShareComposeView; this is the pure data layer.
@MainActor
final class ShareStore: ObservableObject {
    /// Servers the app is currently signed in to (have a stored token).
    let signedInServers: [SharedServer]
    /// The server a share posts to: the app's default target if it is signed in,
    /// else the first signed-in server.
    @Published var selectedServer: SharedServer?
    @Published var topics: [ShareTopic] = []
    @Published var selectedTopicID: String?

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)

        let all = Self.decode([SharedServer].self, key: SharedAppGroup.serversKey) ?? []
        signedInServers = all.filter { SharedKeychain.token(for: $0.id) != nil }

        let defaultServerID = Self.decode(SharedTarget.self, key: SharedAppGroup.defaultTargetKey)?.serverID
        selectedServer = signedInServers.first { $0.id == defaultServerID } ?? signedInServers.first
    }

    var hasSignedInServer: Bool { selectedServer != nil }

    // MARK: - Topics

    /// Best-effort fetch of the selected server's topics for the picker. Failures
    /// are swallowed: the link can still post under the server's default topic.
    func loadTopics() async {
        guard let server = selectedServer, let token = token(for: server) else { return }
        guard let url = URL(string: server.apiBase + "/api/channels") else { return }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(TopicsResponse.self, from: data)
        else { return }
        topics = decoded.items.map { ShareTopic(id: $0.name, name: $0.displayName) }
        if selectedTopicID == nil {
            selectedTopicID = decoded.default ?? topics.first?.id
        }
    }

    // MARK: - Share

    /// Post the link to the selected server. `draft == false` publishes it.
    func share(url: String, title: String, comment: String, draft: Bool) async throws {
        guard let server = selectedServer, let token = token(for: server) else {
            throw ShareError.notSignedIn
        }
        guard let endpoint = URL(string: server.apiBase + "/api/links") else {
            throw ShareError.server("The selected server has an invalid address.")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body: [String: Any] = ["url": url, "draft": draft]
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty { body["title"] = trimmedTitle }
        let trimmedComment = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedComment.isEmpty { body["comment"] = trimmedComment }
        if let topic = selectedTopicID, !topic.isEmpty { body["topic"] = topic }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ShareError.server("No response from the server.")
        }
        switch http.statusCode {
        case 200...299:
            return
        case 401:
            throw ShareError.server("Your session expired. Open Atacama and sign in again.")
        default:
            throw ShareError.server(Self.serverMessage(data) ?? "The server rejected the link (HTTP \(http.statusCode)).")
        }
    }

    // MARK: - Helpers

    private func token(for server: SharedServer) -> String? {
        SharedKeychain.token(for: server.id)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = SharedAppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Pull the human-readable `message` out of the backend's JSON error envelope.
    private static func serverMessage(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["message"] as? String) ?? (obj["error"] as? String)
    }
}

/// Tolerant decoder for the topics list: newslettr keys it `topics`, atacama
/// keys it `channels`; each item exposes `name` (GUID) and `display_name`.
private struct TopicsResponse: Decodable {
    let items: [Item]
    let `default`: String?

    struct Item: Decodable {
        let name: String
        let displayName: String
        enum CodingKeys: String, CodingKey { case name; case displayName = "display_name" }
    }

    enum CodingKeys: String, CodingKey { case topics; case channels; case `default` }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? c.decode([Item].self, forKey: .topics))
            ?? (try? c.decode([Item].self, forKey: .channels))
            ?? []
        `default` = try? c.decodeIfPresent(String.self, forKey: .default)
    }
}
