# Atacama iOS

A native iOS app for fast, voice-first authoring of posts on
[Atacama](https://earlyversion.com), a semantic publishing CMS.

Speech-to-text is the primary input. Drafts are written stream-of-consciousness;
edits are tracked as *hiding* text (preserved, not deleted), and colortext blocks
are added after the fact as collapsible footnotes.

This repo is **just the SwiftUI app**. The backend lives in the separate **atacama**
repo (served at earlyversion.com); see [AGENTS.md](AGENTS.md) for the backend API
contract it depends on.

See [AGENTS.md](AGENTS.md) for architecture and project structure, and [docs/](docs/)
for detailed notes.

> **Status:** scaffolding only. No Swift sources or Xcode project yet.
