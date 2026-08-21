# Backend API spec

The JSON API that **newslettr iOS** consumes, served by the **newslettr** Go
backend (newslettr.com, earlyversion.com, and the other reader sites). The app
can author against **one or more servers** — newslettr.com is seeded as the
default, and additional servers (a local dev instance, say) can be added by base
URL. This document is the contract from the iOS client's point of view.

Some endpoints carry aliases from the retired atacama Flask backend
(`/api/messages`↔`/api/posts`, `/api/channels`↔`/api/topics`); both spellings
work.

## Multi-server model

- A **server** is added by its base URL. The app fetches
  [`GET /api/atacama-config`](#get-apiatacama-config) to learn the server's name,
  API base, and auth flow.
- Each server has its **own bearer token**, stored in the Keychain keyed by the
  server's id. The app may be signed in to several servers at once.
- The user posts to a **server + channel** target chosen per post on the capture
  screen; Settings marks one default target.
- The config endpoint declares the auth flow via `auth.type`. newslettr reports
  `"oauth"` (web sign-in → token) whenever Google OAuth is configured, and falls
  back to `"password"` (`POST /api/login`) otherwise — typically a local dev
  server without Google credentials. **The app currently drives only the OAuth
  flow**; servers with a non-oauth `auth.type` are listed but their sign-in is
  disabled until a password flow is added.

Status legend:
- ✅ **exists** — already implemented in the backend(s); no backend work needed.

---

## `GET /api/atacama-config` ✅

Self-describing config the app fetches when a server is added (unauthenticated
discovery). The endpoint keeps its historical `atacama-config` name — it is a
live contract with shipped clients.

**Request**
```http
GET /api/atacama-config
```

**Response** `200`
```json
{
  "name": "Alex Power's blog",
  "api_base": "https://newslettr.com",
  "auth": { "type": "oauth", "login_path": "/login" },
  "capabilities": { "preview": true, "messages": true, "channels": true, "links": true, "images": true, "quotes": true },
  "styles": { "colortext": "https://newslettr.com/publisher/static/css/colortext.css" }
}
```

- `name` — display name for the server list (falls back to host).
- `api_base` — absolute base the app prefixes onto `/api/...` paths.
- `auth.type` — `"oauth"` or `"password"`. The app branches on this; only `oauth`
  is wired up today.
- `auth.login_path` — path the OAuth flow opens.
- `capabilities` — feature flags. `images`/`quotes` gate the Photo tab and the
  Read tab's Photos/Quotes views; absent flags (older backends) are treated as
  "allowed" for already-added servers but recorded on `ServerConfig` when a
  server is added.
- `styles.colortext` — absolute URL of the **AML stylesheet**, which `HTMLView`
  links alongside a `body_html` or a `POST /api/preview` result. Without it a
  colortext block, a literal span (`<< … >>`) and an inline title all render as
  plain prose. **The path differs per host and only one is public on each**: a
  reader-served content domain serves `/reader/static/css/colortext.css`
  anonymously, while on the publisher that prefix is behind the author gate and
  `303`s to the login page — so the client must use the advertised URL rather
  than assume a path. Older servers omit the block; `AMLStylesheet` then links
  both known paths and lets the redirect-to-HTML one lose.

Implemented in newslettr at `internal/app/publisher/routes.go` (`apiConfig`) and
`internal/app/readapi/readapi.go` (`Discovery`, for reader-served domains).

---

## Authentication ✅ (exists)

Token-based auth is the mechanism this app uses.

### Obtaining a token (mobile OAuth flow)

Implemented in newslettr at `internal/app/oauth.go`.

1. The app opens a web auth session to:
   ```
   GET /login?mobile=1&redirect=atacama://auth-callback
   ```
2. The server runs Google OAuth, then on the callback mints a bearer token and
   redirects to:
   ```
   atacama://auth-callback?token=<token>
   ```
3. The app extracts `token` from the callback URL and stores it in the Keychain.

Use `ASWebAuthenticationSession` with callback scheme `atacama` so the redirect is
captured by the app.

> **The `atacama://` scheme is a live contract, not a leftover.** newslettr
> allowlists mobile redirect targets (`mobileRedirect` in
> `internal/app/oauth.go`) and maps exactly `"atacama"` →
> `atacama://auth-callback`; an unlisted scheme is refused, so this is
> deliberately an open redirect guard. Changing the scheme on the client
> requires a coordinated backend change and would break every shipped app
> version.

### Using a token

Send the token on every authenticated request:
```
Authorization: Bearer <token>
```
Authentication is handled by `requireToken` / `bearer` in
`internal/app/publisher/routes.go`. Expired tokens are treated as
unauthenticated.

On any `401` with `{"code": "UNAUTHORIZED"}`, the app should discard the stored
token and prompt re-login.

### Revoking a token (logout) ✅

```
POST /api/logout
Authorization: Bearer <token>
```
Revokes the token server-side. Response: `{"success": true}` (200).
Implemented in newslettr as `apiLogout`.

---

## `POST /api/preview` ✅ (exists)

Renders AML markup to HTML without persisting anything. Implemented in newslettr
as `apiPreview`, guarded by `requireToken`.

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

Create a new post from JSON. `/api/messages` is an alias of `/api/posts`; see
`apiCreatePost` in newslettr. The `id` field is a string GUID (older backends
returned an integer, so the client decodes it as a string either way — see
`MessageDraftPayload.swift`).

**Request**
```http
POST /api/messages
Authorization: Bearer <token>
Content-Type: application/json

{
  "subject": "On deserts",
  "content": "Stream of consciousness body... (green: a footnote)",
  "channel": "personal",        // optional; defaults to the server's default channel
  "parent_id": 1234             // optional; links into a message chain
}
```

**Response** `201`
```json
{
  "id": "pst_abc123",
  "url": "https://newslettr.com/feed/post/pst_abc123",
  "processed_content": "<...server-rendered HTML...>"
}
```

**Errors**
- `400` — body is not JSON.
- `401` — missing/invalid token.
- `422` — `subject` or `content` missing.
- `500` — creation failed.

### Field reference
- `subject` (string, required) — post title.
- `content` (string, required) — raw AML markup. Colortext footnotes are embedded
  here as AML color tags.
- `channel` (string, optional) — must be a valid channel name (see
  `GET /api/channels`). The server validates against the channel config and defaults
  to the server's default channel when omitted.
- `parent_id` (int, optional) — parent message id for threaded chains. Invalid /
  unknown ids are ignored server-side (logged, not fatal).

---

## `GET /api/channels` ✅

List the channels the authenticated user may post to, for the channel picker.
Implemented in newslettr as `apiTopics`, where `/api/channels` is an alias of
`/api/topics` and `name` carries the topic **slug**.

> newslettr filters this list to topics the token may post to and sets `group`
> to the reader host that serves the topic (for example `blog.pow3.com`).
> Authoring requests still go to the publisher's `api_base`; the group tells the
> app where the published post will appear.

**Request**
```http
GET /api/channels
Authorization: Bearer <token>
```

**Response** `200`
```json
{
  "channels": [
    { "name": "programming", "display_name": "Programming", "group": "blog.pow3.com", "requires_auth": false },
    { "name": "personal", "display_name": "Personal", "group": "earlyversion.com", "requires_auth": true }
  ],
  "default": "programming"
}
```

**Errors**
- `401` — missing/invalid token.

### Field reference
- `channels[].name` — channel id used in `POST /api/messages`'s `channel` field.
- `channels[].display_name` — human-readable label for the picker.
- `channels[].group` — public reader host where the channel's posts appear.
- `channels[].requires_auth` — whether the channel is non-public (informational).
- `default` — the channel pre-selected in the picker (the server's default
  channel).

---

## `POST /api/links` ✅ — Share Extension

Save a **shared link** (a URL the user shared into the app from another app via
the iOS Share Extension), gated by `capabilities.links == true`. newslettr
(`apiCreateLink`) files a `Link` — URL + title + optional quote/comment, under a
topic — for the next digest.

Only `url` is required: a missing `title` falls back to the URL's host, and
`quote`/`comment` are optional, so a one-tap share succeeds. Links **publish
immediately** by default; the extension's "Save as draft" toggle sends
`"draft": true` to capture one unpublished for later review.

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
- `422` — `url` missing or not a valid http(s) URL, a field exceeds its limit, or an unknown topic.
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
`url` is the post's reader-facing page — it backs the row's **View in Browser**
and **Share Link** context menu, and is handed to `PostDetailView` so those
actions work there before the detail request finishes.

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

Decoded into `PostDetail`; `body_html` is shown in the shared `HTMLView`, with
the AML stylesheet named by `styles.colortext` in the discovery document — see
`AMLStylesheet`. `url` backs the detail view's **View in Browser** / **Share
Link** toolbar menu.

---

## `POST /api/images` ✅ — photo upload (the Photo tab)

Upload a photo from the phone. **Requires a bearer token.** Unlike the JSON
authoring endpoints, the body is `multipart/form-data` (it carries binary): the
bytes go in an `image` part, the rest are ordinary form fields. Advertised by
`capabilities.images == true`.

```http
POST /api/images
Authorization: Bearer <token>
Content-Type: multipart/form-data; boundary=…

image=<binary>            // required, an image/* file, ≤ 30 MiB
topic_guid=top_abc123     // or "topic"/"channel"; optional, defaults to default topic
title=Sunset              // optional
caption=Over the bay      // optional
location=San Francisco    // optional
date=2026-07-01           // optional YYYY-MM-DD; overrides EXIF capture date
action=publish            // optional; "publish" or "draft" (default "draft")
```

**Response** `201` — the created image (same shape as `GET /api/images/{guid}`).
Errors: `401` (no token), `422` (no/invalid image, over 30 MiB, bad field, or
unknown topic), `500`.

Client notes: the app transcodes picked/captured photos to JPEG and downscales
them (`ImageEncoding`) before upload, since library photos are often HEIC (which
the backend's EXIF reader doesn't decode). Decoded into `AtacamaImage`. Uploads
default to **draft**; the Photo tab's "Publish now" toggle sends `action=publish`.

---

## `GET /api/images` ✅ (reading) — photo feed

The public photo feed. **Public — no token.** Published, non-deleted images only.
Same `topic` / `since` / `until` / `limit` filters as `GET /api/posts`.

**Response** `200`
```json
{
  "images": [
    {
      "id": "img_def456",
      "url": "https://newslettr.example.com/publisher/uploads/img_def456.jpg",
      "title": "Sunset",
      "caption": "Over the bay",
      "location": "San Francisco",
      "width": 4032,
      "height": 3024,
      "camera_make": "Apple",
      "camera_model": "iPhone 15 Pro",
      "captured_at": "2026-07-01T18:12:00Z",
      "topic": { "id": "top_abc123", "name": "Personal" },
      "author": "Newslettr Admin",
      "is_draft": false
    }
  ]
}
```

`url` is absolutized so the app can load it directly via `AsyncImage`. Decoded
into `[AtacamaImage]`; shown as a grid in the Read tab's **Photos** view.

## `GET /api/images/{guid}` ✅ (reading)

A single published image's metadata (the same object shape as a feed entry). A
draft / soft-deleted / unknown GUID returns `404` (`NOT_FOUND`).

---

## `GET /api/links` ✅ (reading) — links feed

The public shared-link feed. **Public — no token.** Published, non-deleted links
only; each carries a URL plus an optional quote and comment. Decoded into
`[LinkItem]`; shown as a tappable list in the Read tab's **Links** view.

**Response** `200`
```json
{
  "links": [
    {
      "id": "lnk_norvig",
      "url": "https://norvig.com/21-days.html",
      "domain": "norvig.com",
      "title": "Teach Yourself Programming in Ten Years",
      "quote": "",
      "comment": "A durable rebuttal to weekend mastery myths.",
      "published_at": "2026-07-22T12:00:00Z",
      "topic": { "id": "top_programming", "name": "Programming" }
    }
  ]
}
```

---

## `GET /api/quotes` ✅ (reading) — quotes feed

The public tracked-quotation feed. **Public — no token.** Quotes have no draft
concept. Advertised by `capabilities.quotes == true`. Decoded into `[Quote]`;
shown in the Read tab's **Quotes** view.

**Response** `200`
```json
{
  "quotes": [
    {
      "id": "quo_abc123",
      "text": "The medium is the message.",
      "quote_type": "reference",
      "original_author": "Marshall McLuhan",
      "source": "Understanding Media",
      "quote_date": "1964",
      "commentary": ""
    }
  ]
}
```

---

## Out of scope (v1)

Reading **posts**, **images**, **links**, and **quotes** is supported (above),
and photos can be uploaded (`POST /api/images`). Still out of scope: photo
**collections/galleries**, reading calendar entries, newsletters/digests,
subscriptions, message chains, and any edit-history / "hide" tracking.
Intelligent digest/AI summarization of the feed is deferred — the list `excerpt`
is the server's stored excerpt or a first-100-chars fallback.
