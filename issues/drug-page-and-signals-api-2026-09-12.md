# Drug page + GET /signals?drug=

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Do not implement SEARCH_REDESIGN.md wholesale. Deploy when good; post a note here.

#23 (Tzield search + Novel) is live. Do not pile this work onto #23.

## Wanted (in this order)

### 1. `?q=` fill on load

Deep-link `https://faers.mobi/?q=teplizumab` (and `?q=tzield`) should fill the search box once and run the same ranked search as typing. Currently flaky.

### 2. Named-drug profile

A shareable URL that *is* the report, not a Shiny table session.

- Prefer `https://faers.mobi/?drug=teplizumab` and `?drug=tzield` (same isolation as live search: exact/prefix brand+generic first).
- Isolated teplizumab rows already exist (rash 314, pyrexia 218, lymphocyte decreased 103, CRS 50, lymphopenia 48). Show those, with Novel, n, EB05. Not ziprasidone.
- A dedicated path (`/drug/teplizumab`) is fine if cheaper than query-param. One stable URL per drug.

### 3. API / LLM

```
GET /signals?drug=teplizumab
GET /signals?drug=tzield
```

Same ranking as live search. JSON of isolated pairs: drug, event, Novel, n, EB05 (and adj EB05 if already computed). 404 or empty list if no isolate.

Document the endpoint in one markdown file an LLM can read (e.g. `faers-mobi/API.md`). Plumber or existing Shiny HTTP — whichever is smaller.

Optional later, not this slice: `GET /signals?q=`, MCP wrapper, billing.

## Done when

- `?q=teplizumab` fills and isolates on load.
- `?drug=teplizumab` or `/drug/teplizumab` is a usable named-drug profile.
- `GET /signals?drug=teplizumab` returns the isolated JSON; documented.
- Live on https://faers.mobi. Deploy note on this PR with the three URLs to verify.

## Out of scope

Pay gate, Stripe, SEARCH_REDESIGN phases 3–8, merging this GPS PR.
