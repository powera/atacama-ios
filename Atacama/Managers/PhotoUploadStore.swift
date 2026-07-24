//
//  PhotoUploadStore.swift
//  Atacama
//
//  Singleton owning the in-progress photo upload: the chosen image bytes, its
//  metadata (title/caption/location), the destination server+topic, and the
//  publish/draft choice. Uploading goes through APIClient.uploadImage against the
//  destination server (POST /api/images, multipart, bearer). Mirrors DraftStore's
//  @MainActor/@Published conventions and reuses DraftStore's channel list for the
//  destination picker. See docs/backend-api.md.
//

import Combine
import Foundation

@MainActor
final class PhotoUploadStore: ObservableObject {
    static let shared = PhotoUploadStore()

    /// JPEG bytes of the photo to upload, set once a photo is picked/captured.
    @Published var imageData: Data?
    @Published var title = ""
    @Published var caption = ""
    @Published var location = ""
    /// Destination server+topic. `channel` carries the topic GUID (as for posts).
    @Published var target: PostTarget?
    /// Publish immediately, or upload as a draft to caption later in the publisher.
    @Published var publishNow = false

    @Published var isUploading = false
    @Published var lastError: String?

    private init() {
        self.target = ServerStore.shared.defaultTarget
    }

    /// The server the current target points at, if any.
    var targetServer: ServerConfig? {
        guard let serverID = target?.serverID else { return nil }
        return ServerStore.shared.server(id: serverID)
    }

    /// Whether there's enough to upload: a photo and a destination server.
    var canUpload: Bool { imageData != nil && targetServer != nil && !isUploading }

    /// Clear the picked photo and metadata, keeping the destination for the next one.
    func reset() {
        imageData = nil
        title = ""
        caption = ""
        location = ""
    }

    /// Upload the current photo to the target server+topic. On success returns the
    /// created image and clears the photo/metadata; on failure sets `lastError`.
    func upload() async -> AtacamaImage? {
        guard let data = imageData else {
            lastError = "Choose a photo to upload first."
            return nil
        }
        guard let server = targetServer else {
            lastError = "Choose a server to upload to first."
            return nil
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let image = try await APIClient.shared.uploadImage(
                data,
                filename: "photo.jpg",
                topicGUID: target?.channel,
                title: title,
                caption: caption,
                location: location,
                publish: publishNow,
                on: server
            )
            reset()
            return image
        } catch {
            lastError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }
}
