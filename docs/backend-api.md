# Backend API spec

The JSON API that **Atacama iOS** consumes. The backend lives in the separate
**atacama** repo (Python/Flask, served at `https://earlyversion.com`). This document
is the contract from the iOS client's point of view, and the spec for the two
endpoints the atacama repo still needs to implement.

Status legend:
- ✅ **exists** — already implemented in atacama; no backend work needed.
- 🟡 **to implement** — must be added in the atacama repo before the iOS app can use it.

Base URL: `https://earlyversion.com` (make this configurable in `APIClient`).

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

## `POST /api/messages` 🟡 (to implement in atacama)

Create a new post (an `Email` message) from JSON. The atacama repo currently only
has the form-based `POST /submit`; this endpoint exposes the same creation pipeline
over JSON.

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

## `GET /api/channels` 🟡 (to implement in atacama)

List the channels the authenticated user may post to, for the channel picker.

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

## Out of scope (v1)

Reading/browsing existing posts, message chains, feeds, widgets, and any
edit-history / "hide" tracking are **not** part of v1. The app is authoring-only:
preview, create, and pick a channel.
