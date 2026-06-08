//
//  AuthenticationService.swift
//  Atacama
//
//  Drives the mobile OAuth flow: builds the login URL and extracts the bearer token
//  from the atacama:// callback. Token persistence is handled by SessionManager /
//  KeychainStore. Modeled on trakaido's AuthenticationService. See docs/auth-flow.md.
//

import AuthenticationServices
import Foundation

enum AuthError: LocalizedError {
    case invalidCallback
    case noTokenInCallback
    case sessionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCallback:
            return "Invalid authentication callback URL"
        case .noTokenInCallback:
            return "Authentication response did not contain a token"
        case let .sessionFailed(error):
            return "Sign-in failed: \(error.localizedDescription)"
        }
    }
}

/// URL scheme registered for the OAuth callback (also declared in Info.plist).
let atacamaCallbackScheme = "atacama"

enum AuthenticationService {
    /// OAuth login URL. The server completes Google OAuth, mints a UserToken, and
    /// redirects to `atacama://auth-callback?token=<token>`. `loginPath` comes from
    /// the server's /api/atacama-config (defaults to `/login`).
    static func loginURL(baseURL: String, loginPath: String = "/login") -> URL {
        let redirect = "\(atacamaCallbackScheme)://auth-callback"
        let path = loginPath.hasPrefix("/") ? loginPath : "/" + loginPath
        let secureBaseURL = TransportSecurity.normalizedBaseURL(baseURL)
        return URL(string: "\(secureBaseURL)\(path)?mobile=1&redirect=\(redirect)")!
    }

    /// Extract the bearer token from the OAuth callback URL.
    static func extractToken(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == atacamaCallbackScheme,
              components.host == "auth-callback"
        else {
            throw AuthError.invalidCallback
        }

        var token = components.queryItems?.first(where: { $0.name == "token" })?.value

        if token == nil, let fragment = components.fragment {
            var fragmentComponents = URLComponents()
            fragmentComponents.query = fragment
            token = fragmentComponents.queryItems?.first(where: { $0.name == "token" })?.value
        }

        guard let authToken = token, !authToken.isEmpty else {
            throw AuthError.noTokenInCallback
        }
        return authToken
    }
}
