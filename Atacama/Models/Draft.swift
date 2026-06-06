//
//  Draft.swift
//  Atacama
//
//  The in-progress post. Plain editable text plus a subject and chosen channel.
//  Colortext footnotes are applied by wrapping a selected range in an AML color tag.
//  See docs/draft-model.md and docs/backend-api.md.
//

import Foundation

/// An in-progress post being authored.
///
/// `body` is the live, editable text (the dictation transcript the author edits
/// normally). Applying a colortext footnote rewrites `body` in place, wrapping the
/// selected substring in the inline AML form `(<color> …)`. `toAML()` therefore just
/// returns `body` — the markup is already embedded — but is kept as a named seam so
/// the submit path doesn't assume the body is raw text.
struct Draft: Identifiable, Codable, Equatable {
    let id: UUID
    var subject: String
    var body: String
    /// Channel name, or nil to use the server default.
    var channel: String?
    /// Optional parent message id for threaded chains.
    var parentId: Int?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        subject: String = "",
        body: String = "",
        channel: String? = nil,
        parentId: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.subject = subject
        self.body = body
        self.channel = channel
        self.parentId = parentId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// True when there is nothing worth saving or submitting.
    var isEmpty: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The AML markup string to submit as `content`. The colortext footnotes are
    /// already embedded in `body`, so this is the body verbatim.
    func toAML() -> String {
        body
    }

    /// Wrap a range of `body` in an inline AML colortext footnote: `(<color> text)`.
    ///
    /// This is the "add a footnote after the fact" operation. The server renders the
    /// wrapped span as a collapsible footnote. Returns a new range-adjusted Draft;
    /// no-op (returns self) if the range is empty or out of bounds.
    func applyingFootnote(_ tag: ColorTag, to range: Range<String.Index>) -> Draft {
        guard !range.isEmpty,
              range.lowerBound >= body.startIndex,
              range.upperBound <= body.endIndex
        else { return self }

        let selected = body[range]
        let wrapped = "(<\(tag.name)> \(selected))"
        var copy = self
        copy.body = body.replacingCharacters(in: range, with: wrapped)
        copy.updatedAt = Date()
        return copy
    }
}
