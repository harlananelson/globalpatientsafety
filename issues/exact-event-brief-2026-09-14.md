# Prefer exact event PT on pair briefs / series

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

LLM test 2026-09-14: `/signals` works (tzield×Nausea n=319). Bug: `event=Haemorrhage` is substring isolation. Pair `format=brief` / `format=series` can pick a *longer* PT and still title the query string.

Live: `GET /signals?drug=xarelto&event=Haemorrhage&format=series` returns **Gastrointestinal haemorrhage** (sum n=28,661). Exact `xarelto × Haemorrhage` exists (n=12,583). Heading still says Haemorrhage. Same class of error as “Pericardial haemorrhage under a Haemorrhage heading.”

List search (`event=Haemorrhage` JSON) should **keep** substring (Injection site / GI / exact all show up). Only **single-pair** formats must not silently swap the PT.

## Scope

When `drug=` AND `event=` and the format is one pair (`series`, pair stanza of `brief`/`pdf`, `label`, `class`):

1. If an isolated row has **exact** event PT (case-insensitive), use that row.
2. If not, pick the substring match you already pick — but the brief heading, series `event` field, and any “selected pair” line must say the **actual** PT (`Gastrointestinal haemorrhage`), plus `matched=substring` (or one plain sentence). Do not keep the user’s shorter string as if it were the row.

Do not change event-only JSON lists or the documented exact/prefix/substring isolation for search.

## Verify (live)

- `GET /signals?drug=xarelto&event=Haemorrhage` still returns multiple substring rows including exact Haemorrhage and GI haemorrhage
- `format=series` on that pair → event is `Haemorrhage`, sum n around 12,583 (not 28,661 GI)
- `format=brief` heading `xarelto × Haemorrhage` and series stanza match the exact pair
- `drug=tzield&event=Nausea&format=brief` unchanged (n=319)
- A query with **no** exact PT still works and names the chosen PT

## Out of scope

- ChatGPT page-reader rejecting markdown homepage (`#72`) — use `/api` HTML; not this slice
- New `/signals` filters
- Pay gate
