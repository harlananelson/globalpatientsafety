# List rows: indication / low_info flags + optional hide filters

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

Harlan + Mistral (2026-09-16): `format=profile` tops are clean after #79 (explicit `indication` / `low_info`). Default `GET /signals?drug=tzield` still leads with **Insulin therapy** (n=4, eb05 367) and list rows have **no** flag fields — so an LLM that follows api.md’s “use GET /signals?drug=” crowns indication confounding.

## Scope

### 1. Additive fields (required)

On default JSON list rows (and CSV columns), include the same booleans profile already has:

- `indication` (bool)
- `low_info` (bool)

Same definitions as profile. Backward compatible.

### 2. Optional filters (required)

Mirror `novel=` / `trend=` style:

- `indication=hide` — drop indication-confounded rows
- `low_info=hide` — drop low-info rows

**Do not** change default ranking when those params are absent (crawlers / documented contract keep current order).

### 3. Docs (required, scoped)

Update API.md / openapi.json / chatgpt.md / llms.txt / mcp.md:

- Document the two fields on list rows
- Document `indication=` / `low_info=` (`hide` value)
- Instruct LLM clients: for ranking/summaries prefer `indication=hide&low_info=hide` **or** `format=profile` / `format=brief`
- Amend any “no new query params” crawler line **only** to allow these two (same five-test rule as #65: stable, cut multi-call, common PV question, unambiguous, deterministic)

## Keep

- Default `GET /signals?drug=tzield` without filters: same pairs / order as today (plus new fields)
- tzield×Nausea pair n=319 unchanged
- No pay gate
- No silent default filter

## Verify (live)

- `GET /signals?drug=tzield&limit=5` → 200; rows include `indication` and `low_info`; first row may still be Insulin therapy
- `GET /signals?drug=tzield&indication=hide&low_info=hide&sort=eb05&order=desc&limit=5` → 200; **no** Insulin therapy; tops look like cleaned profile spirit
- `format=profile` still clean
- openapi / API.md document the params
- chatgpt.md tells Actions to use hide for ranking asks

## Out of scope

- Changing default body ranking
- New SOC / min_quarters filters
- ChatGPT browse “not safe to open”
