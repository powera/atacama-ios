//
//  ServerListView.swift
//  Atacama
//
//  Settings screen for managing backend servers: add a server by base URL, sign in
//  or out of each, delete servers, and choose the default server+channel the capture
//  screen starts on. See docs/backend-api.md.
//

import SwiftUI

struct ServerListView: View {
    @ObservedObject private var serverStore = ServerStore.shared
    @ObservedObject private var session = SessionManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            List {
                if serverStore.servers.isEmpty {
                    ContentUnavailableView(
                        "No servers",
                        systemImage: "server.rack",
                        description: Text("Add a server to start authoring.")
                    )
                } else {
                    ForEach(serverStore.servers) { server in
                        ServerRow(server: server)
                    }
                    .onDelete(perform: deleteServers)
                }
            }
            .navigationTitle("Servers")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add", systemImage: "plus") { showAddServer = true }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView()
            }
            .alert("Sign-in error", isPresented: .constant(session.lastError != nil)) {
                Button("OK") { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            serverStore.remove(serverStore.servers[index])
        }
    }
}

/// One server row: name/host, signed-in state, sign-in/out, and a default toggle.
private struct ServerRow: View {
    let server: ServerConfig
    @ObservedObject private var serverStore = ServerStore.shared
    @ObservedObject private var session = SessionManager.shared

    private var isSignedIn: Bool { session.isSignedIn(server) }
    private var isDefault: Bool { serverStore.defaultTarget?.serverID == server.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.headline)
                    Text(server.baseURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isDefault {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Default server")
                }
            }

            HStack(spacing: 16) {
                if isSignedIn {
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Button("Sign out", role: .destructive) {
                        session.signOut(server: server)
                    }
                    .font(.caption)
                    if !isDefault {
                        Button("Make default") {
                            serverStore.setDefaultTarget(PostTarget(serverID: server.id, channel: nil))
                        }
                        .font(.caption)
                    }
                } else if server.supportsSignIn {
                    Button("Sign in") {
                        session.signIn(server: server)
                    }
                    .font(.caption)
                    .disabled(session.isSigningIn(server))
                } else {
                    Text("Sign-in not supported yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Sheet to add a server by base URL; fetches /api/atacama-config to describe it.
private struct AddServerView: View {
    @ObservedObject private var serverStore = ServerStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = "https://"
    @State private var isAdding = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://example.com", text: $baseURL)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Server URL")
                } footer: {
                    Text("The app fetches the server's configuration to set it up.")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Add server")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { Task { await add() } }
                        .disabled(isAdding || !isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isAdding { ProgressView() }
            }
        }
    }

    private var isValid: Bool {
        guard let url = URL(string: baseURL.trimmingCharacters(in: .whitespaces)) else { return false }
        return url.scheme != nil && url.host != nil
    }

    private func add() async {
        isAdding = true
        errorMessage = nil
        defer { isAdding = false }
        do {
            try await serverStore.add(baseURL: baseURL)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
