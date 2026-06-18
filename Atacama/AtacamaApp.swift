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
    @StateObject private var reading = ReadingStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(serverStore)
                .environmentObject(reading)
                .onOpenURL { url in
                    session.handleCallback(url)
                }
        }
    }
}

/// Top-level tabs: a public Reading feed (always available) and the auth-gated
/// authoring flow. Reading needs no sign-in, so it is the default experience;
/// writing falls back to sign-in until a server is signed in to.
struct RootView: View {
    @EnvironmentObject private var session: SessionManager

    var body: some View {
        TabView {
            ReadingView()
                .tabItem { Label("Read", systemImage: "book") }

            Group {
                if session.signedInServerIDs.isEmpty {
                    // No server signed in yet — offer sign-in for authoring.
                    SignInView()
                } else {
                    CaptureView()
                }
            }
            .tabItem { Label("Write", systemImage: "square.and.pencil") }
        }
    }
}
