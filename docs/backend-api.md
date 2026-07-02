# Backend API spec

The JSON API that **Atacama iOS** consumes. The app can author against **one or
more servers**: the original **atacama** backend (Python/Flask, e.g.
`https://earlyversion.com`) and the **newslettr** Go backend, which deliberately
mirrors the same JSON surface (`/api/preview`, `/api/messages`↔`/api/posts`,
`/api/channels`↔`/api/topics`, `/api/logout`). This document is the contract from
the iOS client's point of view.

## Multi-server model

- A **server** is added by its base URL. The app fetches
  [`GET /api/atacama-config`](#get-apiatacama-config) to learn the server's name,
  API base, and auth flow.
- Each server has its **own bearer token**, stored in the Keychain keyed by the
  server's id. The app may be signed in to several servers at once.
- The user posts to a **server + channel** target chosen per post on the capture
  screen; Settings marks one default target.
- Auth differs by backend: atacama uses **OAuth** (web sign-in → token); newslettr
  uses **email/password** (`POST /api/login`). The config endpoint declares which
  via `auth.type`. **The app currently drives only the OAuth flow**; servers with a
  non-oauth `auth.type` are listed but their sign-in is disabled until a password
  flow (or newslettr OAuth) is added.

Status legend:
- ✅ **exists** — already implemented in the backend(s); no backend work needed.

---

## `GET /api/atacama-config` ✅

Self-describing config the app fetches when a server is added (unauthenticated
discovery). Served identically by both backends.

**Request**
```http
GET /api/atacama-config
```

**Response** `200`
```json
{
  "name": "Alex Power's blog",
  "api_base": "https://earlyversion.com",
  "auth": { "type": "oauth", "login_path": "/login" },
  "capabilities": { "preview": true, "messages": true, "channels": true, "links": true }
}
```

- `name` — display name for the server list (falls back to host).
- `api_base` — absolute base the app prefixes onto `/api/...` paths.
- `auth.type` — `"oauth"` (atacama) or `"password"` (newslettr). The app branches
  on this; only `oauth` is wired up today.
- `auth.login_path` — path the OAuth flow opens (atacama: `/login`).
- `capabilities` — informational feature flags.

Implemented in atacama at `src/blog/blueprints/api.py` (`client_config_api`) and in
newslettr at `internal/app/publisher/routes.go` (`apiConfig`).

---

## Authentication ✅ (exists)

Token-based auth is already built in atacama and is the mechanism this app uses.

### Obtaining a token (mobile OAuth flow)

Implemented in `atacama/src/atacama/blueprints/auth.py`.

1. The app opens a web auth session to:
   ```
   GET /login?mobile=1&redirect=atacama://auth-callback
   ```
2. The server runs Google OAuth, then on `/oauth2callback` mints a `UserToken`
   (a `secrets.token_urlsafe(32)` string, 120-day expiry) and redirects to:
   ```
   atacama://auth-callback?token=<token>
   ```
3. The app extracts `token` from the callback URL and stores it in the Keychain.

Use `ASWebAuthenticationSession` with callback scheme `atacama` so the redirect is
captured by the app.

### Using a token

Send the token on every authenticated request:
```
Authorization: Bearer <token>
```
Authentication is handled by `require_auth` / `_populate_user`
(`atacama/src/atacama/decorators/auth.py`), which accepts both `Bearer <token>` and
a bare `<token>`. Expired tokens (>120 days) are deleted server-side and treated as
unauthenticated.

On any `401` with `{"code": "UNAUTHORIZED"}`, the app should discard the stored
token and prompt re-login.

### Revoking a token (logout) ✅

```
POST /api/logout
Authorization: Bearer <token>
```
Deletes the `UserToken` server-side. Response: `{"success": true}` (200).
Implemented in `auth.py`.

---

## `POST /api/preview` ✅ (exists)

Renders AML markup to HTML without persisting anything. Implemented in
`atacama/src/blog/blueprints/submit.py` (`preview_message`), guarded by
`require_auth` (so it already accepts Bearer-token auth).

**Request**
```http
POST /api/preview
Authorization: Bearer <token>
Content-Type: application/json

{ "content": "<green> a technical aside >>>\nMain text here." }
```

**Response** `200`
```json
{ "processed_content": "<...server-rendered HTML...>" }
```

**Errors**
- `400` — body is not JSON, or `content` missing.
- `401` — missing/invalid token.
- `500` — `{ "error": ..., "message": "Failed to process message preview" }`.

The app uses this to show a faithful preview before submitting, so it never
reimplements AML rendering.

---

## `POST /api/messages` ✅

Create a new post from JSON. On atacama this creates an `Email` message via the
same creation pipeline as the form-based `POST /submit`
(`src/blog/blueprints/api.py`, `create_message_api`); on newslettr it creates a
`Post` (`/api/messages` is an alias of `/api/posts`, see `apiCreatePost`). The
`id` field is an integer on atacama and a string GUID on newslettr — the client
decodes it as a string.

### Implementation notes (for the atacama side)

- Add to the existing `content_bp` in `src/blog/blueprints/submit.py` (already
  registered — no `server.py` change).
- Guard with `@require_auth`. Because token auth has **no Flask session**, resolve
  the author from `g.user` (populated by `_populate_user`), **not** `session['user']`.
  Re-fetch the user inside the new `db.session()` to avoid detached-instance issues.
- Reuse the AML pipeline from `handle_submit` (lines ~107–151): `Email(...)`
  construction, `tokenize` → `parse` → `generate_html` for both `processed_content`
  and the truncated `preview_content`, parent linking, and URL extraction. Recommend
  extracting a shared `create_email_message(db_session, *, author, subject, content,
  channel, parent_id=None) -> (message, extracted_urls)` helper so the form route and
  this route share one implementation, and the form route stays byte-identical.
- Reuse the background archive step (`handle_submit` lines ~157–203); recommend
  factoring it into `_start_archive_thread(message_id, extracted_urls, channel)`.

**Request**
```http
POST /api/messages
Authorization: Bearer <token>
Content-Type: application/json

{
  "subject": "On deserts",
  "content": "Stream of consciousness body... (green: a footnote)",
  "channel": "personal",        // optional; defaults to channel_manager.default_channel
  "parent_id": 1234             // optional; links into a message chain
}
```

**Response** `201`
```json
{
  "id": 5678,
  "url": "https://earlyversion.com/messages/5678",
  "processed_content": "<...server-rendered HTML...>"
}
```

**Errors**
- `400` — body is not JSON.
- `401` — missing/invalid token.
- `422` — `subject` or `content` missing (mirror `handle_submit`'s validation).
- `500` — creation failed.

### Field reference
- `subject` (string, required) — post title.
- `content` (string, required) — raw AML markup. Colortext footnotes are embedded
  here as AML color tags.
- `channel` (string, optional) — must be a valid channel name (see
  `GET /api/channels`). The server validates against the channel config and defaults
  to `channel_manager.default_channel` when omitted.
- `parent_id` (int, optional) — parent message id for threaded chains. Invalid /
  unknown ids are ignored server-side (logged, not fatal), matching `handle_submit`.

---

## `GET /api/channels` ✅

List the channels the authenticated user may post to, for the channel picker.
Implemented in atacama (`list_channels_api`) and newslettr (`apiTopics`, where
`/api/channels` is an alias of `/api/topics` and `name` carries the topic GUID).

### Implementation notes (for the atacama side)

- Add to `content_bp` in `src/blog/blueprints/submit.py`, guarded by `@require_auth`.
- Use `get_channel_manager()` (already imported in `submit.py`) to enumerate
  channels, honoring `g.user.channel_preferences` / access levels so restricted
  channels the user can't post to are excluded.

**Request**
```http
GET /api/channels
Authorization: Bearer <token>
```

**Response** `200`
```json
{
  "channels": [
    { "name": "personal", "display_name": "Personal", "group": "Personal", "requires_auth": true },
    { "name": "general",  "display_name": "General",  "group": "General",  "requires_auth": false }
  ],
  "default": "personal"
}
```

**Errors**
- `401` — missing/invalid token.

### Field reference
- `channels[].name` — channel id used in `POST /api/messages`'s `channel` field.
- `channels[].display_name` — human-readable label for the picker.
- `channels[].group` — channel group, for sectioning the picker.
- `channels[].requires_auth` — whether the channel is non-public (informational).
- `default` — the channel pre-selected in the picker
  (`channel_manager.default_channel`).

---

## `POST /api/links` ✅ (both backends) — Share Extension

Save a **shared link** (a URL the user shared into Atacama from another app via
the iOS Share Extension). Implemented on both backends
(`capabilities.links == true`). newslettr (`apiCreateLink`) files a `Link` —
URL + title + optional quote/comment, under a topic — for the next digest.
atacama (`create_link_api` in `src/blog/blueprints/api.py`) has no separate
link model, so it saves the link as a regular message: the comment leads, the
quote renders as a `<quote>` block, and the URL sits on its own line
(auto-linked and archived).

Only `url` is required: a missing `title` falls back to the URL's host, and
`quote`/`comment` are optional, so a one-tap share succeeds. Links **publish
immediately** by default; the extension's "Save as draft" toggle sends
`"draft": true` to capture one unpublished for later review — on newslettr
only. atacama has no unpublished drafts and rejects `"draft": true` with a
`422` telling the user to turn the toggle off.

**Request**
```http
POST /api/links
Authorization: Bearer <token>
Content-Type: application/json

{
  "url": "https://example.com/article",   // required, http(s)
  "title": "Great read",                  // optional; defaults to the URL host
  "topic": "top_abc123",                  // or "channel"; optional, defaults to the default topic
  "comment": "Why it's worth sharing",    // optional
  "quote": "A pulled excerpt",            // optional
  "draft": false                          // optional; default false (publish now)
}
```

**Response** `201`
```json
{
  "id": "lnk_def456",
  "url": "https://example.com/article",
  "domain": "example.com",
  "title": "Great read",
  "topic": { "id": "top_abc123", "name": "Science" },
  "is_draft": false
}
```

**Errors**
- `400` — body is not JSON.
- `401` — missing/invalid token.
- `422` — `url` missing or not a valid http(s) URL, a field exceeds its limit, an unknown topic, or (atacama only) `"draft": true`.
- `500` — save failed.

### Client notes
- The Share Extension (`AtacamaShareExtension/`) is a separate target. It reuses
  the app's signed-in server and bearer token via the shared App Group
  (`group.com.yevaud.atacama`) — the App Group backs both the shared
  `UserDefaults` suite (server list) and the Keychain access group (token). The
  user must be signed in to a server in the app before sharing works.

---

## `GET /api/posts` ✅ (reading)

The read-only feed for the Read tab. **Public — no token.** Returns published
posts newest first; the body is omitted to keep the list light.

```http
GET /api/posts?topic=top_abc123&since=2026-01-01&until=2026-06-18&limit=50
```

All params optional: `topic` (topic GUID; unknown → 422), `since`/`until`
(RFC3339 or `YYYY-MM-DD`; malformed → 400), `limit` (default/max 50).

**Response** `200`
```json
{
  "posts": [
    {
      "id": "pst_abc123",
      "title": "Welcome",
      "excerpt": "Short summary…",
      "published_at": "2026-06-17T12:00:00Z",
      "topic": { "id": "top_abc123", "name": "Programming" },
      "url": "https://newslettr.example.com/feed/post/pst_abc123"
    }
  ]
}
```

Decoded into `PostSummary` / `PostListResponse` (`Models/Post.swift`).
`published_at` is ISO8601 (the shared `APIClient` decoder uses `.iso8601`).

---

## `GET /api/posts/{guid}` ✅ (reading)

A single published post with its rendered HTML body. **Public — no token.** A
draft / soft-deleted / unknown GUID returns `404` (`NOT_FOUND`).

**Response** `200`
```json
{
  "id": "pst_abc123",
  "title": "Welcome",
  "body_html": "<p>Rendered AML…</p>",
  "published_at": "2026-06-17T12:00:00Z",
  "author": "Newslettr Admin",
  "topic": { "id": "top_abc123", "name": "Programming" },
  "references": [ { "id": "pst_def456", "title": "See also" } ],
  "url": "https://newslettr.example.com/feed/post/pst_abc123"
}
```

Decoded into `PostDetail`; `body_html` is shown in the shared `HTMLView`.

---

## Out of scope (v1)

Reading **posts** is supported (above). Still out of scope: reading links,
calendar entries, newsletters/digests, subscriptions, message chains, and any
edit-history / "hide" tracking. Intelligent digest/AI summarization of the feed
is deferred — the list `excerpt` is the server's stored excerpt or a
first-100-chars fallback.
