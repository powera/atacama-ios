//
//  DraftStore.swift
//  Atacama
//
//  Singleton owning the current in-progress draft, with debounced autosave to disk.
//  The capture UI binds to `draft`; submission goes through `submit()`.
//  See docs/draft-model.md and docs/backend-api.md.
//

import Combine
import Foundation

@MainActor
final class DraftStore: ObservableObject {
    static let shared = DraftStore()

    /// The current draft. Mutations trigger debounced autosave.
    @Published var draft: Draft
    /// Channels available for the picker, loaded from the server.
    @Published private(set) var channels: [Channel] = []
    @Published var isSubmitting = false
    @Published var lastError: String?

    private var autosaveCancellable: AnyCancellable?

    private init() {
        self.draft = DraftPersistence.load() ?? Draft()
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
            draft.body += " " + trimmed
        }
        draft.updatedAt = Date()
    }

    /// Wrap a selected range of the body in a colortext footnote.
    func applyFootnote(_ tag: ColorTag, to range: Range<String.Index>) {
        draft = draft.applyingFootnote(tag, to: range)
    }

    /// Load the channel list for the picker. Sets the draft's channel to the server
    /// default if it has none.
    func loadChannels() async {
        do {
            let list = try await APIClient.shared.channels()
            channels = list.channels
            if draft.channel == nil {
                draft.channel = list.default
            }
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Render the current draft to server HTML for preview.
    func preview() async -> String? {
        do {
            return try await APIClient.shared.preview(content: draft.toAML())
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Submit the draft. On success, clears the draft and its autosave file and
    /// returns the created message; on failure, sets `lastError` and returns nil.
    func submit() async -> CreatedMessage? {
        guard !draft.isEmpty else { return nil }
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await APIClient.shared.createMessage(draft.payload())
            DraftPersistence.clear()
            draft = Draft()
            return created
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
