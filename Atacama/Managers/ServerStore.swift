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
    /// Set once the default server has been seeded successfully. Persisted so a
    /// user who deletes newslettr.com never has it reappear on the next launch.
    private let hasSeededDefaultKey = "atacama.hasSeededDefault"

    /// The publisher seeded on first launch, so a fresh install goes straight to
    /// sign-in instead of asking the user to type a base URL. It is an ordinary
    /// server once added: deletable, and other servers can still be added.
    static let defaultServerBaseURL = "https://newslettr.com"

    /// Guards against two concurrent seed attempts (app launch and the Servers
    /// screen both kick one off).
    private var isSeeding = false

    /// Defaults live in the shared App Group suite so the Share Extension reads the
    /// same server list and default target the app wrote. A pre-App-Group install
    /// has its config in `.standard`, so migrate it across once on first launch.
    init(defaults: UserDefaults = AppGroup.defaults) {
        self.defaults = defaults
        Self.migrateFromStandardIfNeeded(into: defaults, keys: [serversKey, defaultTargetKey])
        let stored = (Self.decode([ServerConfig].self, from: defaults, key: serversKey) ?? [])
            .map { $0.usingSecureTransportDefaults() }
        self.servers = Self.deduplicated(stored)
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
    ///
    /// A server already in the list is **updated in place** rather than added
    /// again: adding newslettr.com twice used to produce two rows that were
    /// indistinguishable in the UI but held separate ids, so each carried its own
    /// Keychain token and the target picker offered the same site twice. Keeping
    /// the existing id preserves the stored token and any default target pointing
    /// at it, while refreshing the name and capabilities the server now reports.
    @discardableResult
    func add(baseURL: String) async throws -> ServerConfig {
        let normalized = TransportSecurity.normalizedBaseURL(baseURL)
        let response = try await APIClient.shared.serverConfig(baseURL: normalized)
        let existing = servers.first { $0.matches(baseURL: normalized) }
        let server = ServerConfig(
            id: existing?.id ?? UUID(),
            baseURL: normalized,
            name: response.name.isEmpty ? host(of: response.apiBase) : response.name,
            apiBase: TransportSecurity.normalizedBaseURL(response.apiBase),
            authType: response.auth.type,
            loginPath: response.auth.loginPath ?? "",
            supportsImages: response.capabilities?.images,
            supportsQuotes: response.capabilities?.quotes,
            supportsMessages: response.capabilities?.messages,
            supportsPreview: response.capabilities?.preview
        )
        if let index = servers.firstIndex(where: { $0.id == server.id }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        persist()
        return server
    }

    /// Whether a base URL is already configured. Lets the Add sheet say so before
    /// a round-trip, rather than silently replacing a row the user forgot about.
    func contains(baseURL: String) -> Bool {
        let normalized = TransportSecurity.normalizedBaseURL(baseURL)
        return servers.contains { $0.matches(baseURL: normalized) }
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

    // MARK: - Default server

    /// Add newslettr.com on first launch so a fresh install lands on sign-in
    /// rather than an empty "add a server" screen.
    ///
    /// Adding a server requires a successful /api/atacama-config fetch, so this
    /// cannot run from the synchronous `init()`. It is instead called from app
    /// launch and from the Servers screen, and is idempotent: the flag is set
    /// only on success, so a first launch with no network retries later rather
    /// than skipping the seed permanently. Once the flag is set it never seeds
    /// again — deleting newslettr.com is meant to stick.
    func seedDefaultServerIfNeeded() async {
        guard !isSeeding, !defaults.bool(forKey: hasSeededDefaultKey) else { return }
        isSeeding = true
        defer { isSeeding = false }

        // A user who added newslettr.com by hand before this shipped shouldn't
        // end up with a duplicate row.
        guard !contains(baseURL: Self.defaultServerBaseURL) else {
            defaults.set(true, forKey: hasSeededDefaultKey)
            return
        }

        do {
            try await add(baseURL: Self.defaultServerBaseURL)
            defaults.set(true, forKey: hasSeededDefaultKey)
        } catch {
            // Leave the flag unset so the next launch (or a visit to the Servers
            // screen) tries again. Nothing is surfaced: the user did not ask for
            // this, and the Add flow remains available.
        }
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

    /// Collapse servers that share a base URL, keeping the first occurrence.
    /// Duplicates could be created before `add` merged them, so an existing
    /// install is cleaned up on the next launch rather than left with rows the
    /// user cannot tell apart. The kept row is the earlier one, which is the one
    /// a stored default target is most likely to point at; the dropped rows'
    /// tokens are deleted so they do not linger in the Keychain unreferenced.
    private static func deduplicated(_ servers: [ServerConfig]) -> [ServerConfig] {
        var seen = Set<String>()
        var result: [ServerConfig] = []
        for server in servers {
            if seen.insert(ServerConfig.identity(of: server.baseURL)).inserted {
                result.append(server)
            } else {
                KeychainStore.deleteToken(for: server.id)
            }
        }
        return result
    }

    private static func decode<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Copy any legacy config stored in `.standard` (before the App Group existed)
    /// into the shared suite once, so signing in stays sticky across the upgrade.
    /// No-op when the shared suite already holds a value or there is nothing to copy.
    private static func migrateFromStandardIfNeeded(into defaults: UserDefaults, keys: [String]) {
        guard defaults != .standard else { return }
        for key in keys where defaults.data(forKey: key) == nil {
            if let legacy = UserDefaults.standard.data(forKey: key) {
                defaults.set(legacy, forKey: key)
            }
        }
    }

    private func host(of urlString: String) -> String {
        URL(string: urlString)?.host ?? urlString
    }
}
