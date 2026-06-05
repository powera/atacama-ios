//
//  ColorTag.swift
//  Atacama
//
//  The set of AML colortext tags an author can apply as a footnote.
//  Mirrors the COLORS dict in atacama/src/aml_parser/colorblocks.py — keep in sync.
//  See docs/aml-colortext.md.
//

import Foundation

/// A single AML colortext tag: a semantic color the author wraps text in, which the
/// server renders as a collapsible footnote.
struct ColorTag: Identifiable, Hashable {
    /// The AML tag name used in markup (e.g. "green"). Also the `id`.
    let name: String
    /// Emoji sigil the server shows for this color.
    let sigil: String
    /// Short human description of the color's meaning, for the picker.
    let meaning: String

    var id: String { name }

    /// The colortext tags available in the picker, in display order.
    ///
    /// Mirrors `COLORS` in colorblocks.py. A few server entries are aliases that
    /// share a sigil/class (acronym/context/resource → green, quote → yellow); the
    /// picker exposes the primary, author-facing set rather than every alias.
    static let all: [ColorTag] = [
        ColorTag(name: "xantham", sigil: "🔥", meaning: "sarcastic, overconfident"),
        ColorTag(name: "red",     sigil: "💡", meaning: "forceful, certain"),
        ColorTag(name: "orange",  sigil: "⚔️", meaning: "counterpoint"),
        ColorTag(name: "yellow",  sigil: "💬", meaning: "quotes"),
        ColorTag(name: "green",   sigil: "⚙️", meaning: "technical / context"),
        ColorTag(name: "teal",    sigil: "🤖", meaning: "LLM output"),
        ColorTag(name: "blue",    sigil: "✨", meaning: "voice from beyond"),
        ColorTag(name: "violet",  sigil: "📣", meaning: "serious"),
        ColorTag(name: "music",   sigil: "🎵", meaning: "music note"),
        ColorTag(name: "mogue",   sigil: "🌎", meaning: "actions taken"),
        ColorTag(name: "gray",    sigil: "💭", meaning: "past stories"),
        ColorTag(name: "hazel",   sigil: "🎭", meaning: "storytelling"),
    ]
}
