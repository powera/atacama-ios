//
//  SessionManager.swift
//  Atacama
//
//  Singleton holding per-server auth state. The app can be signed in to multiple
//  servers at once; each server's bearer token lives in the Keychain keyed by the
//  server's id. This drives the OAuth sign-in session per server and exposes which
//  servers are currently signed in. See docs/auth-flow.md.
//

import AuthenticationServices
import Combine
import Foundation
#if os(iOS)
import UIKit
#else
import AppKit
#endif

@MainActor
final class SessionManager: NSObject, ObservableObject {
    static let shared = SessionManager()

    /// Ids of servers the user is currently signed in to. Republished so views
    /// re-evaluate signed-in state after sign-in/out.
    @Published private(set) var signedInServerIDs: Set<UUID> = []
    /// The server whose sign-in is currently in flight, if any.
    @Published private(set) var signingInServerID: UUID?
    @Published var lastError: String?

    private var webAuthSession: ASWebAuthenticationSession?
    /// The server that started the in-flight OAuth session; the callback token is
    /// saved under this server's id.
    private var pendingServer: ServerConfig?

    private override init() {
        super.init()
        refreshSignedInState()
    }

    // MARK: - Queries

    func isSignedIn(_ server: ServerConfig) -> Bool {
        signedInServerIDs.contains(server.id)
    }

    func isSigningIn(_ server: ServerConfig) -> Bool {
        signingInServerID == server.id
    }

    /// Recompute which servers have a stored token (e.g. on launch or after a change).
    func refreshSignedInState() {
        signedInServerIDs = Set(
            ServerStore.shared.servers
                .filter { KeychainStore.loadToken(for: $0.id) != nil }
                .map(\.id)
        )
    }

    // MARK: - Sign in / out

    /// Begin the OAuth sign-in flow for a server in a web auth session.
    func signIn(server: ServerConfig) {
        guard signingInServerID == nil else { return }
        guard server.supportsSignIn else {
            lastError = "Sign-in for this server type isn’t supported yet."
            return
        }
        signingInServerID = server.id
        pendingServer = server
        lastError = nil

        let url = AuthenticationService.loginURL(baseURL: server.apiBase, loginPath: server.loginPath)
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: atacamaCallbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.signingInServerID = nil
                if let error {
                    // User cancellation is not an error worth surfacing loudly.
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.lastError = AuthError.sessionFailed(error).localizedDescription
                    }
                    self.pendingServer = nil
                    return
                }
                guard let callbackURL else { self.pendingServer = nil; return }
                self.handleCallback(callbackURL)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
    }

    /// Handle the atacama:// OAuth callback (also reachable via .onOpenURL). The
    /// token is stored under the server that started the flow.
    func handleCallback(_ url: URL) {
        defer { pendingServer = nil }
        guard let server = pendingServer else {
            lastError = "Received a sign-in callback without a pending server."
            return
        }
        do {
            let token = try AuthenticationService.extractToken(from: url)
            KeychainStore.saveToken(token, for: server.id)
            refreshSignedInState()
            ServerStore.shared.tokensChanged()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sign out of a server: revoke the token server-side (best-effort) and clear
    /// local state.
    func signOut(server: ServerConfig) {
        Task { try? await APIClient.shared.logout(on: server) }
        clearToken(for: server)
    }

    /// Clear a server's token locally without a server round-trip (e.g. on a 401).
    func clearToken(for server: ServerConfig) {
        KeychainStore.deleteToken(for: server.id)
        refreshSignedInState()
        ServerStore.shared.tokensChanged()
    }
}

extension SessionManager: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            #if os(iOS)
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
            return scene?.keyWindow ?? ASPresentationAnchor()
            #else
            return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
            #endif
        }
    }
}
