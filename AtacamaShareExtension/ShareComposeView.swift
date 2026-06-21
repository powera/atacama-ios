//
//  ShareComposeView.swift
//  AtacamaShareExtension
//
//  The compose UI shown when the user shares a URL into Atacama. It confirms the
//  link, lets them add a title/comment and pick a topic and a publish/draft
//  state, and posts to the backend via ShareStore. Hosted by ShareViewController.
//

import SwiftUI

struct ShareComposeView: View {
    /// The shared link (already extracted by the host view controller).
    let sharedURL: String
    /// A title harvested from the share (page title / selected text), if any.
    let initialTitle: String
    /// Called when the share finishes (success) or the user cancels.
    let onFinish: () -> Void
    let onCancel: () -> Void

    @StateObject private var store = ShareStore()

    @State private var title: String
    @State private var comment: String = ""
    /// Default false → publish immediately; the toggle saves a draft instead.
    @State private var saveAsDraft = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(sharedURL: String, initialTitle: String, onFinish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.sharedURL = sharedURL
        self.initialTitle = initialTitle
        self.onFinish = onFinish
        self.onCancel = onCancel
        _title = State(initialValue: initialTitle)
    }

    var body: some View {
        NavigationView {
            Group {
                if store.hasSignedInServer {
                    form
                } else {
                    notSignedIn
                }
            }
            .navigationTitle("Share to Atacama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(saveAsDraft ? "Save" : "Publish", action: submit)
                            .disabled(!store.hasSignedInServer)
                    }
                }
            }
        }
        .task { await store.loadTopics() }
    }

    private var form: some View {
        Form {
            Section("Link") {
                Text(sharedURL)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Section("Title") {
                TextField("Title", text: $title, axis: .vertical)
            }

            Section("Comment") {
                TextField("Why you're sharing this (optional)", text: $comment, axis: .vertical)
                    .lineLimit(2...5)
            }

            if !store.topics.isEmpty {
                Section("Topic") {
                    Picker("Topic", selection: Binding(
                        get: { store.selectedTopicID ?? "" },
                        set: { store.selectedTopicID = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(store.topics) { topic in
                            Text(topic.name).tag(topic.id)
                        }
                    }
                }
            }

            if store.signedInServers.count > 1 {
                Section("Server") {
                    Picker("Server", selection: Binding(
                        get: { store.selectedServer?.id },
                        set: { id in store.selectedServer = store.signedInServers.first { $0.id == id } }
                    )) {
                        ForEach(store.signedInServers) { server in
                            Text(server.name).tag(Optional(server.id))
                        }
                    }
                }
            }

            Section {
                Toggle("Save as draft", isOn: $saveAsDraft)
            } footer: {
                Text(saveAsDraft
                     ? "Saved unpublished — review it in Atacama before it goes into a digest."
                     : "Published immediately and eligible for the next digest.")
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
    }

    private var notSignedIn: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Not signed in")
                .font(.headline)
            Text(ShareError.notSignedIn.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        Task {
            do {
                try await store.share(url: sharedURL, title: title, comment: comment, draft: saveAsDraft)
                onFinish()
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
