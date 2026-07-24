//
//  AtacamaImage.swift
//  Atacama
//
//  A photo hosted on a newslettr site. One shape backs three endpoints — the
//  upload response (POST /api/images), the feed list (GET /api/images), and the
//  single-image lookup (GET /api/images/{guid}) — so the app decodes them all
//  the same way. The binary lives at `url` (absolute; the app loads it with
//  AsyncImage); the rest is human-facing metadata plus best-effort EXIF.
//  See docs/backend-api.md.
//

import Foundation

/// A published (or just-uploaded) image with its metadata.
struct AtacamaImage: Identifiable, Decodable, Hashable {
    /// Image GUID (img_…).
    let id: String
    /// Absolute URL of the image binary, ready to load directly.
    let url: String
    let title: String
    let caption: String
    let location: String
    /// Pixel dimensions from EXIF; 0 when the source carried none.
    let width: Int
    let height: Int
    /// Camera metadata from EXIF; empty when absent.
    let cameraMake: String
    let cameraModel: String
    /// Capture date from EXIF; nil when the photo carried none.
    let capturedAt: Date?
    let topic: TopicRef
    let author: String
    /// Whether the image is an unpublished draft (only ever true for the caller's
    /// own upload response — the public feed never returns drafts).
    let isDraft: Bool

    enum CodingKeys: String, CodingKey {
        case id, url, title, caption, location, width, height
        case cameraMake = "camera_make"
        case cameraModel = "camera_model"
        case capturedAt = "captured_at"
        case topic, author
        case isDraft = "is_draft"
    }
}

/// Response shape of GET /api/images.
struct ImageListResponse: Decodable {
    let images: [AtacamaImage]
}
