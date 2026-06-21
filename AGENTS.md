# AGENTS.md

## General Agent directions:
* CLAUDE.md is a symlink to AGENTS.md.
* The backend for this app is **newslettr** (the Go server in `../newslettr`).
  API changes go there, not here — this repo is the iOS client only. The
  obsolete **atacama** repo (`../atacama`, earlyversion.com) is posting-only and
  no longer the reading/reference backend; new work targets newslettr.

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

The app has two sides, surfaced as tabs (`RootView`):
- **Write** — voice-first authoring (the original v1 scope): composing and
  submitting posts. Auth-gated; falls back to sign-in until a server is signed
  in to.
- **Read** — a read-only feed of published posts from a newslettr site, filtered
  by topic and date (the `Views/Reading/` screens + `ReadingStore`). Reading is
  **public** (newslettr's `GET /api/posts` needs no token), so it works without
  sign-in. Intelligent digest/summarization is deferred; the list shows a
  lightweight excerpt and the body is fetched on demand for the detail view.

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

## Backend contract (lives in the `newslettr` repo)

The app talks to a small JSON API on the newslettr publisher server. The full
spec is in the newslettr repo's `API.md` (and mirrored notes in
[docs/backend-api.md](docs/backend-api.md)). Summary:

Authoring endpoints (require `Authorization: Bearer <token>`):
- `POST /api/login` — `{email, password}` → `{token, expires_at}`.
- `POST /api/preview` — `{content}` → `{processed_content}`.
- `POST /api/messages` (alias `/api/posts`) — create a post.
- `POST /api/links` — save a shared link (backs the Share Extension; newslettr only).
- `GET /api/channels` (alias `/api/topics`) — channel/topic list for the picker.
- `POST /api/logout` — revoke the bearer token.

Reading endpoints (**public — no token**):
- `GET /api/posts` — published-post feed; filters `topic`, `since`, `until`,
  `limit`. Omits the body (light list).
- `GET /api/posts/{guid}` — a single post with its rendered `body_html`.

Discovery: `GET /api/atacama-config` (unauthenticated) advertises capabilities,
including `"reading": true` and `"links": true`.

## Share Extension (sharing a link into Atacama)

`AtacamaShareExtension/` is a separate app-extension target that puts Atacama in
the iOS share sheet for URLs. It extracts the shared URL (and page title),
presents a small SwiftUI compose sheet (title, comment, topic, publish/draft
toggle), and `POST`s to `/api/links` on the signed-in server. It reuses the app's
server list and bearer token through the shared **App Group**
`group.com.yevaud.atacama` (which backs both the shared `UserDefaults` suite and
the Keychain access group — see `Storage/AppGroup.swift`). The extension is
self-contained (its own `ShareStore`) so it doesn't pull the whole app in; keep
the shared constants in sync with `AppGroup.swift` / `KeychainStore.swift` /
`ServerConfig.swift`. The user must be signed in to a server in the app first.

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
