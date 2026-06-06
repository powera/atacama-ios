//
//  SessionManager.swift
//  Atacama
//
//  Singleton holding auth state. Loads the bearer token from the Keychain on launch,
//  runs the OAuth sign-in session, and exposes whether the user is signed in.
//  See docs/auth-flow.md.
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

    /// The current bearer token, or nil when signed out. Read by APIClient.
    @Published private(set) var token: String?
    @Published var isSigningIn = false
    @Published var lastError: String?

    var isSignedIn: Bool { token != nil }

    private var webAuthSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
        self.token = KeychainStore.loadToken()
    }

    /// Begin the OAuth sign-in flow in a web auth session.
    func signIn() {
        guard !isSigningIn else { return }
        isSigningIn = true
        lastError = nil

        let url = AuthenticationService.loginURL(baseURL: APIClient.shared.baseURL)
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: atacamaCallbackScheme
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self else { return }
                self.isSigningIn = false
                if let error {
                    // User cancellation is not an error worth surfacing loudly.
                    if (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        self.lastError = AuthError.sessionFailed(error).localizedDescription
                    }
                    return
                }
                guard let callbackURL else { return }
                self.handleCallback(callbackURL)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.webAuthSession = session
        session.start()
    }

    /// Handle the atacama:// OAuth callback (also reachable via .onOpenURL).
    func handleCallback(_ url: URL) {
        do {
            let token = try AuthenticationService.extractToken(from: url)
            setToken(token)
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Sign out: revoke the token server-side (best-effort) and clear local state.
    func signOut() {
        Task { try? await APIClient.shared.logout() }
        clearToken()
    }

    /// Clear the token locally without a server round-trip (e.g. on a 401).
    func clearToken() {
        token = nil
        KeychainStore.deleteToken()
    }

    private func setToken(_ token: String) {
        self.token = token
        KeychainStore.saveToken(token)
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
