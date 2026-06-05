//
//  AtacamaApp.swift
//  Atacama
//
//  App entry point. Routes the atacama:// OAuth callback to SessionManager and shows
//  the sign-in screen or the capture screen depending on auth state.
//

import SwiftUI

@main
struct AtacamaApp: App {
    @StateObject private var session = SessionManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .onOpenURL { url in
                    session.handleCallback(url)
                }
        }
    }
}

/// Switches between sign-in and the authoring UI based on auth state.
struct RootView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        if session.isSignedIn {
            CaptureView()
        } else {
            SignInView()
        }
    }
}
