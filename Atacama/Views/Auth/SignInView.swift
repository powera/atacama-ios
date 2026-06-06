//
//  SignInView.swift
//  Atacama
//
//  Shown when no server is signed in. Routes the user to the Servers screen to add
//  a server and/or sign in. (Sign-in itself is per-server via the OAuth web flow.)
//

import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: SessionManager
    @EnvironmentObject private var serverStore: ServerStore

    @State private var showServers = false

    private var hasServers: Bool { !serverStore.servers.isEmpty }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)

            VStack(spacing: 8) {
                Text("Atacama")
                    .font(.largeTitle.bold())
                Text("Voice-first authoring")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                showServers = true
            } label: {
                Text(hasServers ? "Sign in" : "Add a server")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)

            if let error = session.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .sheet(isPresented: $showServers) {
            ServerListView()
        }
    }
}
