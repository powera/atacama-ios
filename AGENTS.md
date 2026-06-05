# AGENTS.md

## General Agent directions:
* CLAUDE.md is a symlink to AGENTS.md.
* The backend for this app lives in the separate **atacama** repo
  (`../atacama`, served at earlyversion.com). API changes go there, not here —
  this repo is the iOS client only. This mirrors how the `trakaido` repo is a
  client whose backend lives inside `atacama`.

## Project Overview

Atacama iOS is a native iOS app for **fast voice-first authoring** of posts on
Atacama (earlyversion.com), a semantic publishing CMS. Speech-to-text is the
primary input method.

Two authoring patterns drive the design:

1. **Stream of consciousness.** The author dictates freely; the transcript
   accumulates into an editable draft. v1 uses plain text editing (correct/delete
   normally) — there is no "hide instead of delete" edit-tracking model for now.
2. **Colortext blocks entered after the fact**, which behave like footnotes. The
   author selects prior text and wraps it in an Atacama Markup Language (AML)
   colortext tag, which renders as a collapsible footnote on the server.

v1 scope is **authoring/capture only** — composing and submitting posts. Reading
and browsing existing posts is out of scope for v1.

## Architecture

- **Framework**: SwiftUI
- **Architecture**: MVVM pattern with singleton Managers (`static let shared`) and a
  Services layer — mirrors the `trakaido` SwiftApp conventions.
- **Storage**: Core Data / file-backed draft autosave + Keychain for the auth token.
- **STT**: Apple `Speech` framework + `AVAudioEngine`, on-device recognition.
- **TTS**: `AVSpeechSynthesizer` for reading the draft back for proofing.
- **Building**: Don't build Swift until the user has explicitly asked. When you do,
  build for macOS without downloading extra SDKs:
  `xcodebuild -project Atacama.xcodeproj -scheme Atacama -sdk macosx26.1 build`.

See [docs/](docs/) for architecture notes and the auth flow, and
[docs/backend-api.md](docs/backend-api.md) for the full backend API spec.

## Backend contract (lives in the `atacama` repo)

The app talks to a small JSON API on the atacama Flask server. The full spec —
including the endpoints that still need to be implemented in the `atacama` repo — is
in [docs/backend-api.md](docs/backend-api.md). Summary:

Auth is **already built** server-side:
- **Login**: open `https://earlyversion.com/login?mobile=1&redirect=atacama://auth-callback`
  in a web auth session. The server completes Google OAuth, mints a `UserToken`, and
  redirects to `atacama://auth-callback?token=<token>`. Store the token in Keychain.
- **Authenticated requests**: send `Authorization: Bearer <token>`.
- **Logout / revoke**: `POST /api/logout` with the Bearer token.

Endpoints used:
- `POST /api/preview` — `{content}` → `{processed_content}` (already exists).
- `POST /api/messages` — create a post (**to be implemented** in atacama).
- `GET /api/channels` — channel list for the picker (**to be implemented**).

## Project Structure

```
atacama-ios/
├── AGENTS.md / CLAUDE.md (symlink)
├── docs/                          # backend-api.md, architecture, auth flow
└── Atacama/                       # Atacama.xcodeproj (not yet created)
    ├── AtacamaApp.swift           # @main; registers atacama:// URL scheme (.onOpenURL)
    ├── Models/
    │   ├── Draft.swift            # draft text + applied colortext footnotes
    │   ├── ColorTag.swift         # mirror of AML COLORS (name, sigil, cssClass, description)
    │   ├── Channel.swift          # Decodable {name, displayName, group, requiresAuth}
    │   └── MessageDraftPayload.swift  # Encodable {subject, content, channel, parent_id}
    ├── Views/
    │   ├── Capture/               # CaptureView (STT screen), DraftEditorView
    │   ├── Components/            # ColorTagPickerView, MicButton, ChannelPicker
    │   └── Auth/                  # SignInView
    ├── Services/                  # APIClient, AuthenticationService, STTService, TTSService
    ├── Managers/                  # SessionManager, DraftStore (singletons)
    └── Storage/                   # KeychainStore, DraftPersistence
```

## Draft → AML

The draft is plain editable text. When the author adds a **colortext footnote**, the
selected span is wrapped in the chosen AML color tag (e.g. `(green: …)` /
`<green> … >>>`, exact syntax confirmed against the atacama parser). `Draft.toAML()`
produces the final `content` string sent to `POST /api/messages`.

Always preview via `POST /api/preview` rather than reimplementing AML rendering on
the client.
