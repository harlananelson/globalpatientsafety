# GPS #61 — Scrub leftover Event-only wait docs

Handshake only — do not merge. No pay gate. No new compute.

## Why
#60 Event-only UI is live, but `API.md` still says “Event-only PDF / UI wait.” under `format=profile`, and OpenAPI’s `format=brief` 400 example still says the format requires `drug=` only.

## Scope
- Remove the stale “Event-only PDF / UI wait.” line from `API.md` (keep the event-only field semantics above it).
- Update OpenAPI `400` `brief` example: error/usage should require `drug=` **or** `event=` (include an `event=Nausea&format=brief` usage).
- Leave UI / signal compute unchanged.

Implement in `/projects/faers-mobi/`. Deploy when good.
