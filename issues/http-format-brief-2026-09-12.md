# HTTP format=brief (RWE markdown)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#44 Enrich RWE brief with format=series is live. Do not pile this onto #44.

## Problem

The copyable brief (profile + class + series last-quarters + explain) exists in the UI textarea and MCP `rwe_brief`. ChatGPT Actions, curl, and other non-MCP LLM clients have no HTTPS way to get that same markdown.

## Wanted

`GET /signals?drug=` (and `drug=&event=` when a pair) `&format=brief` returns the same markdown as the UI textarea / MCP `rwe_brief`.

1. Reuse the existing stitch. No new compute.
2. Drug-only vs pair: same rules as UI/MCP (series + class only when a pair is selected).
3. Pick one response shape and document it in `API.md`: `Content-Type: text/markdown` **or** a JSON wrapper with a markdown field. Prefer `text/markdown` if nothing else needs JSON.
4. Always include the hypothesis-not-causation disclaimer.
5. Event-only can 400 or skip, matching other brief formats.

Examples:
- `GET /signals?drug=tzield&format=brief`
- `GET /signals?drug=tzield&event=Nausea&format=brief`

## Done when

- Those URLs return the same brief the UI/MCP already show (tzield×Nausea includes the Series stanza; drug-only does not).
- Documented in `API.md`. Live. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new statistical compute, merging this GPS PR.
