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

1. **Stream of consciousness.** Beyond immediate typo correction and striking an
   entire section, edits are tracked as *hiding* text rather than deleting it.
   Hidden text is preserved in the submitted content and renders as a collapsed
   footnote.
2. **Colortext blocks entered after the fact**, which behave like footnotes. These
   map directly onto Atacama Markup Language (AML) colortext tags, which already
   render as collapsible footnotes on the server.

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

See [docs/](docs/) for architecture notes, the auth flow, and the AML colortext
cheat-sheet.

## Backend contract (in the `atacama` repo)

The app talks to a small JSON API on the atacama Flask server. Auth is already built
server-side:

- **Login**: open `https://earlyversion.com/login?mobile=1&redirect=atacama://auth-callback`
  in a web auth session. The server completes Google OAuth, mints a `UserToken`, and
  redirects to `atacama://auth-callback?token=<token>`. Store the token in Keychain.
- **Authenticated requests**: send `Authorization: Bearer <token>`.
- **Logout / revoke**: `POST /api/logout` with the Bearer token.

Endpoints used:
- `POST /api/preview` — `{content}` → `{processed_content}` (server-rendered HTML).
- `POST /api/messages` — `{subject, content, channel?, parent_id?}` → `201 {id, url, processed_content}`.
- `GET /api/channels` — channel list for the picker.

## Project Structure

```
atacama-ios/
├── AGENTS.md / CLAUDE.md (symlink)
├── docs/                          # architecture, auth flow, AML colortext cheat-sheet
└── Atacama/                       # Atacama.xcodeproj (not yet created)
    ├── AtacamaApp.swift           # @main; registers atacama:// URL scheme (.onOpenURL)
    ├── Models/
    │   ├── Draft.swift            # committed text + [EditOp] log + colortext footnotes
    │   ├── EditOp.swift           # .correct / .strikeSection / .hide
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

## Draft → AML mapping

`Draft.toAML()` flattens the local edit model into AML for submission:

- **Typo correction**: mutate the uncommitted segment in place — never reaches AML.
- **Strike a section**: true delete — recorded as `EditOp.strikeSection` locally for
  undo, but omitted from submitted AML.
- **Hide**: wrap the span in the AML `hidden` colortext tag — preserved in content,
  renders collapsed/struck.
- **Colortext footnote**: wrap selected prior text in a chosen AML color tag.

The structured `[EditOp]` log is kept locally even though v1 only submits flattened
AML, so a future move to server-side edit history needs no client rewrite. Always
preview via `POST /api/preview` rather than reimplementing AML rendering.
