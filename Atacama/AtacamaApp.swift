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
    @StateObject private var serverStore = ServerStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(serverStore)
                .onOpenURL { url in
                    session.handleCallback(url)
                }
        }
    }
}

/// Switches between sign-in and the authoring UI based on the configured servers
/// and whether the user is signed in to at least one.
struct RootView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var serverStore: ServerStore

    var body: some View {
        if session.signedInServerIDs.isEmpty {
            // No usable server yet — either none configured, or none signed in.
            SignInView()
        } else {
            CaptureView()
        }
    }
}
