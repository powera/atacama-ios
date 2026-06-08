//
//  ServerStore.swift
//  Atacama
//
//  Singleton owning the list of configured backend servers and the default
//  server+channel target the capture screen starts on. The server list and default
//  target are non-secret config, persisted to UserDefaults; per-server auth tokens
//  live in the Keychain (see KeychainStore). See docs/backend-api.md.
//

import Combine
import Foundation

@MainActor
final class ServerStore: ObservableObject {
    static let shared = ServerStore()

    /// All configured servers, in display order.
    @Published private(set) var servers: [ServerConfig]
    /// The default server+channel the capture screen starts on (changeable per post).
    @Published private(set) var defaultTarget: PostTarget?

    private let defaults: UserDefaults
    private let serversKey = "atacama.servers"
    private let defaultTargetKey = "atacama.defaultTarget"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.servers = (Self.decode([ServerConfig].self, from: defaults, key: serversKey) ?? [])
            .map { $0.usingSecureTransportDefaults() }
        self.defaultTarget = Self.decode(PostTarget.self, from: defaults, key: defaultTargetKey)
        persist()
    }

    // MARK: - Lookup

    func server(id: UUID) -> ServerConfig? {
        servers.first { $0.id == id }
    }

    /// Servers the user is currently signed in to (have a stored token). These are
    /// the servers offered on the capture screen's target picker.
    var signedInServers: [ServerConfig] {
        servers.filter { KeychainStore.loadToken(for: $0.id) != nil }
    }

    // MARK: - Mutations

    /// Add a server by base URL: fetch its /api/atacama-config, build a
    /// ServerConfig, persist it, and return it. Throws if discovery fails.
    @discardableResult
    func add(baseURL: String) async throws -> ServerConfig {
        let normalized = TransportSecurity.normalizedBaseURL(baseURL)
        let response = try await APIClient.shared.serverConfig(baseURL: normalized)
        let server = ServerConfig(
            baseURL: normalized,
            name: response.name.isEmpty ? host(of: response.apiBase) : response.name,
            apiBase: TransportSecurity.normalizedBaseURL(response.apiBase),
            authType: response.auth.type,
            loginPath: response.auth.loginPath
        )
        servers.append(server)
        persist()
        return server
    }

    /// Remove a server and its stored token. Clears the default target if it
    /// pointed at this server.
    func remove(_ server: ServerConfig) {
        KeychainStore.deleteToken(for: server.id)
        servers.removeAll { $0.id == server.id }
        if defaultTarget?.serverID == server.id {
            defaultTarget = nil
        }
        persist()
    }

    /// Set the default server+channel the capture screen starts on.
    func setDefaultTarget(_ target: PostTarget?) {
        defaultTarget = target
        persist()
    }

    /// Notify observers after a sign-in/sign-out changed a server's token, so
    /// views derived from `signedInServers` re-evaluate.
    func tokensChanged() {
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(servers) {
            defaults.set(data, forKey: serversKey)
        }
        if let target = defaultTarget, let data = try? JSONEncoder().encode(target) {
            defaults.set(data, forKey: defaultTargetKey)
        } else {
            defaults.removeObject(forKey: defaultTargetKey)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func host(of urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}
