# Atacama iOS — docs

Architecture and reference notes for the iOS authoring client. See the top-level
[AGENTS.md](../AGENTS.md) for the overview, backend contract, and project structure.

- **[backend-api.md](backend-api.md)** — the JSON API this app depends on, including
  the endpoints still to be implemented in the `atacama` repo.

Planned documents (to be filled in during implementation):

- **auth-flow.md** — the mobile OAuth → `UserToken` exchange, the `atacama://`
  callback scheme, and Keychain token storage.
- **aml-colortext.md** — cheat-sheet of AML colortext tags mirrored in
  `ColorTag.swift`, tracking `atacama/src/aml_parser/colorblocks.py`.
- **draft-model.md** — the local `Draft` model and how `Draft.toAML()` wraps
  colortext footnotes into submittable AML.
