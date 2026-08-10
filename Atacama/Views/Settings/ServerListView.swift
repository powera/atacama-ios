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
    @State private var isSeeding = false
    /// The server awaiting delete confirmation. Removing a server signs it out,
    /// so it is worth a confirm step rather than a bare swipe.
    @State private var serverToDelete: ServerConfig?

    var body: some View {
        NavigationStack {
            List {
                if serverStore.servers.isEmpty {
                    if isSeeding {
                        // First launch is still fetching the default server's
                        // config; showing "No servers" here would flash and then
                        // be replaced a moment later.
                        HStack {
                            ProgressView()
                            Text("Setting up…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView(
                            "No servers",
                            systemImage: "server.rack",
                            description: Text("Add a server to start authoring.")
                        )
                    }
                } else {
                    ForEach(serverStore.servers) { server in
                        ServerRow(server: server) { serverToDelete = server }
                            // The row's own buttons (Sign in/out, Make default)
                            // swallow the swipe gesture, so a swipe-to-delete
                            // alone left the user with no way to remove a
                            // server. This adds an explicit action, and the
                            // toolbar's Edit button covers the list-wide path.
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    serverToDelete = server
                                }
                            }
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
                if !serverStore.servers.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .confirmationDialog(
                serverToDelete.map { "Remove \($0.name)?" } ?? "Remove server?",
                isPresented: .constant(serverToDelete != nil),
                titleVisibility: .visible,
                presenting: serverToDelete
            ) { server in
                Button("Remove", role: .destructive) {
                    serverStore.remove(server)
                    session.refreshSignedInState()
                    serverToDelete = nil
                }
                Button("Cancel", role: .cancel) { serverToDelete = nil }
            } message: { _ in
                Text("This signs you out of the server and removes it from the list.")
            }
            .sheet(isPresented: $showAddServer) {
                AddServerView()
            }
            .task {
                // Retry for the user who was offline at launch and opened this
                // screen to sort it out. No-op once the seed has succeeded.
                isSeeding = true
                await serverStore.seedDefaultServerIfNeeded()
                isSeeding = false
            }
            .alert("Sign-in error", isPresented: .constant(session.lastError != nil)) {
                Button("OK") { session.lastError = nil }
            } message: {
                Text(session.lastError ?? "")
            }
        }
    }

    /// Delete via the Edit button / list swipe. The servers are resolved *before*
    /// any removal: removing by index while iterating shifts the ones that follow,
    /// so a multi-row delete used to remove the wrong servers.
    private func deleteServers(at offsets: IndexSet) {
        let doomed = offsets.map { serverStore.servers[$0] }
        for server in doomed {
            serverStore.remove(server)
        }
        session.refreshSignedInState()
    }
}

/// One server row: name/host, signed-in state, sign-in/out, and a default toggle.
private struct ServerRow: View {
    let server: ServerConfig
    /// Asks the list to confirm removing this server.
    let onDelete: () -> Void
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
                Spacer()
                // An in-row control, because the row's other buttons keep the
                // swipe gesture from reaching the list reliably.
                Button("Remove", role: .destructive, action: onDelete)
                    .font(.caption)
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

                if isDuplicate {
                    Text("This server is already in your list. Adding it again refreshes its settings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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

    /// Whether the typed URL names a server already configured. Adding it is
    /// still allowed — it refreshes the existing row in place rather than
    /// creating a second one — but the user should know that is what happens.
    private var isDuplicate: Bool {
        isValid && serverStore.contains(baseURL: baseURL)
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
