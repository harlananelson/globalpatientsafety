# Put GET /signals in the first extracted paragraph

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

Perplexity (2026-09-13) only extracted from the `<h4>Signals by drug and event</h4>` + first-load note + “All (drug, even…”. It never saw the LLM banner. That banner is an `alert alert-secondary` **above** the h4. Readability/search extractors drop alerts as chrome.

ChatGPT/Gemini/Perplexity have now all failed the same way: they describe the table, not `/signals`. `#66`/`#69` links are live; placement is wrong for extractors.

## Scope

1. Put one plain sentence **inside** the first main-content block they already quote — the `<h4>` and/or the “All (drug, event) pairs…” `<p>`, not another `alert-*`:

   Machine clients: do not scrape this table. Use `GET /signals` — https://faers.mobi/api.md · https://faers.mobi/openapi.json · https://faers.mobi/chatgpt.md · https://faers.mobi/mcp

2. Keep the existing top banner / footer / `<head>` links (do not remove).

3. Fix the GitHub repo description on `harlananelson/faers-mobi` (currently “Vaccine safety app (VAERS) — Rhino Shiny”). Perplexity used that and mixed in VAERS. Something like: “FAERS signal detection (faers.mobi) — Shiny UI + GET /signals”.

## Keep

- No new `/signals` params or `/api/v1/` paths
- No pay gate
- No second REST/MCP layer

## Verify (live)

- `curl -sS https://faers.mobi/` — the “All (drug, event)” (or h4) block contains `GET /signals` and `/api.md` **without** being inside `alert-secondary` only
- Banner still present
- `GET /api.md` still 200
- `GET /signals?drug=tzield&event=Nausea` still 200 n=319
- `gh repo view harlananelson/faers-mobi --json description` no longer says VAERS

## Out of scope

- Search-index lag
- Gemini’s invented `/api/v1/signal` or `/drug/event` paths
- Rewriting API.md
