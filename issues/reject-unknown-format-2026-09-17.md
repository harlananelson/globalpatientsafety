# Reject unknown format= values with 400

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

Mistral API battery (2026-09-17): core contract passes (profile, brief, series, brand/generic, unknown drug, missing params, event-only, OZEMPIC normalization). Issue: `GET /signals?drug=tzield&format=bogus` → **200** default JSON list (~27 KB) instead of a validation error. Clients that key off `format` can mis-parse.

Career live check same day: `format=series` without `event` already returns **400** JSON `format=series requires drug and event` (Mistral’s 503 was not reproduced). Brief remains intentional `text/plain` Markdown (#74) — document, don’t “fix” back to JSON.

## Scope

1. Allowlist `format` to the documented set: omit/default, `json` (if used), `csv`, `series`, `profile`, `class`, `brief`, `pdf`, `label` (match openapi enum).
2. Unknown `format=` → **400** `application/json` with `error` + `usage` listing allowed values (same style as missing drug/event).
3. Docs: one line in API.md / openapi / chatgpt.md that unknown formats 400; brief is Markdown text/plain by design.

## Keep

- Default omit format → JSON list (unchanged)
- Valid formats unchanged
- No pay gate
- No new analytical filters

## Verify (live)

- `?drug=tzield&format=bogus` → 400 JSON, not a pair list
- `?drug=tzield` → 200 list
- `?drug=tzield&format=brief` → 200 text/plain
- `?drug=semaglutide&format=series` → 400 (needs event)
- `?drug=tzield&event=Nausea&format=series` → 200 JSON
- tzield×Nausea default still n=319

## Out of scope

- Changing brief to JSON
- Fixing client-side JSON parse at 2k chars (their tool)
- ChatGPT browse allowlist
