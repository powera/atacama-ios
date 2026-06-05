//
//  DraftPersistence.swift
//  Atacama
//
//  File-backed autosave for the in-progress draft. v1 keeps a single current draft;
//  a JSON file in Application Support is sufficient and avoids Core Data overhead.
//  See docs/draft-model.md.
//

import Foundation

/// Persists the current draft to a JSON file for crash/relaunch recovery.
enum DraftPersistence {
    private static let fileName = "current-draft.json"

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let dir = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    /// Write the draft to disk. Errors are logged, not thrown — autosave is best-effort.
    static func save(_ draft: Draft) {
        guard let url = fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(draft)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("⚠️ DraftPersistence.save failed: \(error.localizedDescription)")
        }
    }

    /// Load the saved draft, or nil if none exists / decode fails.
    static func load() -> Draft? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Draft.self, from: data)
    }

    /// Remove the saved draft (e.g. after a successful submit).
    static func clear() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
