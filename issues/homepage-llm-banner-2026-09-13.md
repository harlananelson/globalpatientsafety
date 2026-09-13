# Homepage machine-client banner

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

ChatGPT’s first look at faers.mobi anchored on the Shiny table and the “read-only parquet for interactive exploration” About copy. Footer / About already link API.md, chatgpt.md, openapi.json, llms.txt, and MCP — but those sit at the bottom (and About is a hidden tab). The API is live; discoverability is weak.

**Do not change GET /signals, OpenAPI, or MCP.** Duplicate a machine-client notice at the top of the first tab, before the interactive table.

## Copy (near the top, before the 264k / table)

Put this on the active **Signals over time** tab, above the “Signals by drug and event” methodology paragraph and above the table. Keep it short.

**LLM / API access**

For ChatGPT, Claude, agents, and other machine clients: **do not scrape this page.** Use `GET /signals`, OpenAPI, or MCP.

- OpenAPI: https://faers.mobi/openapi.json
- ChatGPT: https://faers.mobi/chatgpt.md
- MCP: https://faers.mobi/mcp
- REST: `GET /signals` (example: https://faers.mobi/signals?drug=tzield)

Optional one-line: no API key. Hypothesis, not causation.

## Keep

- Footer and About “LLM / machine clients” links stay (do not remove).
- About parquet sentence can stay; the banner is the first-pass fix.

## Out of scope

- No new `/signals` query params
- No new REST or MCP layer
- No pay gate
- Do not rewrite API.md / chatgpt.md / openapi.json except a one-liner if you want to note the homepage banner

## Verify (live)

- `curl -sS https://faers.mobi/` HTML contains the banner **before** the 264k / table copy
- The four links are 200
- `GET /signals?drug=tzield` still 200
- Footer links unchanged
