# Atacama Mobile — docs

Architecture and reference notes for the iOS authoring client. See the top-level
[AGENTS.md](../AGENTS.md) for the overview, backend contract, and project structure.

Planned documents (to be filled in during implementation):

- **auth-flow.md** — the mobile OAuth → `UserToken` exchange, the `atacama://`
  callback scheme, and Keychain token storage.
- **aml-colortext.md** — cheat-sheet of AML colortext tags mirrored in
  `ColorTag.swift`, tracking `atacama/src/aml_parser/colorblocks.py`. Includes the
  `hidden` tag used for hidden-text edits.
- **draft-model.md** — the local `Draft` / `EditOp` model and how `Draft.toAML()`
  flattens typo corrections, struck sections, hidden spans, and colortext footnotes
  into submittable AML.
