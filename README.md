# Atacama iOS

A native SwiftUI iOS app for simple, voice-first posting to
[Atacama](https://earlyversion.com), a semantic publishing CMS.

The app is intentionally focused on authoring only:

- choose the target server and channel;
- enter a post title;
- dictate or type post sections;
- insert four-dash (`----`) AML section breaks between sections; and
- select existing text to wrap it in an AML colortext footnote.

This repo is **just the iOS client**. The backend lives in the separate **atacama**
repo (served at earlyversion.com); see [AGENTS.md](AGENTS.md) and
[docs/backend-api.md](docs/backend-api.md) for the API contract it depends on.
