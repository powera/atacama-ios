# AGENTS.md

## General Agent directions:
* CLAUDE.md is a symlink to AGENTS.md.
* The backend for this app is **newslettr** (the Go server in `../newslettr`).
  API changes go there, not here — this repo is the iOS client only. The
  **atacama** Flask backend (`../atacama`) is **retired**: newslettr now serves
  newslettr.com, earlyversion.com, and all the other reader sites. Treat
  `../atacama` as dead code — do not cite it as a reference or a live backend.
* The `atacama` name survives in identifiers that cannot be changed cheaply —
  the App Group, Keychain service, `UserDefaults` keys, bundle ids, the
  `atacama://` OAuth callback scheme, the `/api/atacama-config` endpoint, and the
  Xcode project/target/scheme names. These are persisted keys or live
  client/server contracts: **renaming them signs users out, orphans their stored
  server list, or breaks OAuth.** Product-facing copy says "newslettr".

## Project Overview

newslettr iOS is a native iOS app for **fast voice-first authoring** of posts on
newslettr (newslettr.com), a semantic publishing CMS. Speech-to-text is the
primary input method.

Two authoring patterns drive the design:

1. **Stream of consciousness.** The author dictates freely; the transcript
   accumulates into an editable draft. v1 uses plain text editing (correct/delete
   normally) — there is no "hide instead of delete" edit-tracking model for now.
2. **Colortext blocks entered after the fact**, which behave like footnotes. The
   author selects prior text and wraps it in an Atacama Markup Language (AML)
   colortext tag, which renders as a collapsible footnote on the server.

The app has three tabs (`RootView`):
- **Write** — voice-first authoring (the original v1 scope): composing and
  submitting posts. Auth-gated; falls back to sign-in until a server is signed
  in to.
- **Photo** — pick or capture a photo and upload it to newslettr
  (`PhotoUploadView` + `PhotoUploadStore` → `POST /api/images`). Auth-gated like
  Write; shown per the server's `images` capability.
- **Read** — a read-only feed from a newslettr site (the `Views/Reading/` screens
  + `ReadingStore`), with a Posts / Photos / Links / Quotes selector. Reading is
  **public** (the `GET /api/{posts,images,links,quotes}` feeds need no token), so
  it works without sign-in. Posts and photos filter by topic and date;
  intelligent digest/summarization is deferred.

## Architecture

- **Framework**: SwiftUI
- **Architecture**: MVVM pattern with singleton Managers (`static let shared`) and a
  Services layer — mirrors the `trakaido` SwiftApp conventions.
- **Storage**: Core Data / file-backed draft autosave + Keychain for the auth token.
- **STT**: Apple `Speech` framework + `AVAudioEngine`, on-device recognition.
- **TTS**: `AVSpeechSynthesizer` for reading the draft back for proofing.
- **Building**: Don't build Swift until the user has explicitly asked. When you do,
  build for the **iOS Simulator** without downloading extra SDKs:
  `xcodebuild -project Atacama.xcodeproj -scheme Atacama -sdk iphonesimulator26.5 -destination 'generic/platform=iOS Simulator' build`.
  Check the installed SDK version first (`xcodebuild -showsdks`) and substitute
  it — pinning a version that isn't installed fails immediately.
  A **macOS** build of the whole scheme cannot work: `AtacamaShareExtension` is
  iOS-only (`import UIKit` / `UIViewController`), and the app target embeds it,
  so `-sdk macosx…` fails with "unable to resolve module dependency: 'UIKit'"
  for both the scheme and the `Atacama` target.

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
- `POST /api/links` — save a shared link (backs the Share Extension).
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
└── Atacama/                       # Atacama.xcodeproj (synchronized file-system group:
    │                              #   new .swift files under Atacama/ are auto-compiled)
    ├── AtacamaApp.swift           # @main; RootView tabs; registers atacama:// (.onOpenURL)
    ├── Models/
    │   ├── Draft.swift            # draft text + applied colortext footnotes
    │   ├── ColorTag.swift         # mirror of AML COLORS (name, sigil, cssClass, description)
    │   ├── Channel.swift          # Decodable {name, displayName, group, requiresAuth}
    │   ├── MessageDraftPayload.swift  # Encodable {subject, content, channel, parent_id}
    │   ├── Post.swift             # read-only post feed models (PostSummary/PostDetail/TopicRef)
    │   ├── AtacamaImage.swift     # image model (upload response + feed)
    │   ├── LinkItem.swift         # links feed model
    │   └── Quote.swift            # quotes feed model
    ├── Views/
    │   ├── Capture/               # CaptureView (STT screen), DraftEditorView, PhotoUploadView
    │   ├── Reading/               # ReadingView + Post/Image/Link/Quote row & detail views
    │   ├── Components/            # ColorTagPickerView, MicButton, PostTargetPicker, HTMLView
    │   └── Auth/                  # SignInView
    ├── Services/                  # APIClient, AuthenticationService, STT/TTSService, ImageEncoding
    ├── Managers/                  # SessionManager, DraftStore, ReadingStore, PhotoUploadStore
    └── Storage/                   # KeychainStore, DraftPersistence
```

## Draft → AML

The draft is plain editable text. When the author adds a **colortext footnote**, the
selected span is wrapped in the chosen AML color tag (e.g. `(green: …)` /
`<green> … >>>`, exact syntax confirmed against newslettr's AML parser in
`../newslettr/internal/aml/`). `Draft.toAML()`
produces the final `content` string sent to `POST /api/messages`.

Always preview via `POST /api/preview` rather than reimplementing AML rendering on
the client.
