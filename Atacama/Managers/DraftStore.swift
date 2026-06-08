//
//  DraftStore.swift
//  Atacama
//
//  Singleton owning the current in-progress draft, with debounced autosave to disk.
//  The capture UI binds to `draft` and selects a `target` (server + channel) to post
//  to; submission goes through `submit()` against the target's server.
//  See docs/draft-model.md and docs/backend-api.md.
//

import Combine
import Foundation

@MainActor
final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    /// The current draft. Mutations trigger debounced autosave.
    @Published var draft: Draft
    /// The selected server+channel this post goes to. Starts at the saved default.
    @Published var target: PostTarget?
    /// Channels available per server, loaded from each signed-in server.
    @Published private(set) var channelsByServer: [UUID: [Channel]] = [:]
    /// Whether the capture screen is currently refreshing server channel lists.
    @Published private(set) var isLoadingChannels = false
    /// Per-server channel load failures, surfaced in the destination picker so an
    /// empty picker distinguishes client/server/auth problems from a real empty list.
    @Published private(set) var channelErrorsByServer: [UUID: String] = [:]
    @Published var isSubmitting = false
    @Published var lastError: String?

    private var autosaveCancellable: AnyCancellable?

    private init() {
        self.draft = DraftPersistence.load() ?? Draft()
        self.target = ServerStore.shared.defaultTarget
        autosaveCancellable = $draft
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { draft in
                guard !draft.isEmpty else { return }
                DraftPersistence.save(draft)
            }
    }

    /// Append a finalized dictation utterance to the body.
    func appendUtterance(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if draft.body.isEmpty {
            draft.body = trimmed
        } else {
            let separator = draft.body.hasSuffix(" ") || draft.body.hasSuffix("\n") ? "" : " "
            draft.body += separator + trimmed
        }
        draft.updatedAt = Date()
    }

    /// Insert the four-dash AML section divider used between dictated sections.
    func insertSectionBreak() {
        draft = draft.appendingSectionBreak()
    }

    /// Wrap a selected range of the body in a colortext footnote.
    func applyFootnote(_ tag: ColorTag, to range: Range<String.Index>) {
        draft = draft.applyingFootnote(tag, to: range)
    }

    /// The server the current target points at, if any.
    var targetServer: ServerConfig? {
        guard let serverID = target?.serverID else { return nil }
        return ServerStore.shared.server(id: serverID)
    }

    /// Load the channel list for every signed-in server. Failures on one server are
    /// surfaced but don't block the others. Picks a sensible default target/channel
    /// if none is selected yet.
    func loadChannels() async {
        let servers = ServerStore.shared.signedInServers
        let signedInServerIDs = Set(servers.map(\.id))
        channelsByServer = channelsByServer.filter { signedInServerIDs.contains($0.key) }
        channelErrorsByServer = channelErrorsByServer.filter { signedInServerIDs.contains($0.key) }
        guard !servers.isEmpty else { return }

        isLoadingChannels = true
        defer { isLoadingChannels = false }

        for server in servers {
            do {
                let list = try await APIClient.shared.channels(on: server)
                channelsByServer[server.id] = list.channels
                channelErrorsByServer[server.id] = nil

                let defaultChannel = list.default ?? list.channels.first?.name
                // Seed a default target if we don't have a valid one yet.
                if target == nil {
                    target = PostTarget(serverID: server.id, channel: defaultChannel)
                } else if target?.serverID == server.id, target?.channel == nil {
                    target?.channel = defaultChannel
                }
            } catch {
                let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
                channelsByServer[server.id] = []
                channelErrorsByServer[server.id] = message
                lastError = "Couldn’t load channels for \(server.name): \(message)"
            }
        }
    }

    /// Render the current draft to server HTML for preview, against the target server.
    func preview() async -> String? {
        guard let server = targetServer else {
            lastError = "Choose a server to post to first."
            return nil
        }
        do {
            return try await APIClient.shared.preview(content: draft.toAML(), on: server)
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Submit the draft to the target server+channel. On success, clears the draft
    /// and its autosave file and returns the created message; on failure, sets
    /// `lastError` and returns nil.
    func submit() async -> CreatedMessage? {
        guard !draft.isEmpty else { return nil }
        guard let server = targetServer else {
            lastError = "Choose a server to post to first."
            return nil
        }
        isSubmitting = true
        defer { isSubmitting = false }
        let payload = MessageDraftPayload(
            subject: draft.subject,
            content: draft.toAML(),
            channel: target?.channel,
            parentId: draft.parentId
        )
        do {
            let created = try await APIClient.shared.createMessage(payload, on: server)
            DraftPersistence.clear()
            draft = Draft()
            return created
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
