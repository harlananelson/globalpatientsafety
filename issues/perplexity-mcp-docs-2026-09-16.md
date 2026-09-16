# Perplexity Connectors recipe on mcp.md

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

Perplexity (2026-09-16) correctly diagnosed: web search finds the homepage; browsing does not call `/signals`. Their path is **Settings → Connectors → Add custom connector** with remote MCP (Streamable HTTP), then enable the connector in the chat. Not another discovery layer on faers.mobi.

Live `https://faers.mobi/mcp.md` is Claude Desktop / Cursor only. Hosted MCP is already `https://faers.mobi/mcp` (POST 202). Add a short Perplexity section. Optional one-liner on `/api` and `/llms.txt` pointing at that section.

## Scope

1. In `/mcp.md` (served live), add **Perplexity** after Hosted:

   - Settings → Connectors → Add custom connector  
   - URL: `https://faers.mobi/mcp`  
   - Transport: Streamable HTTP  
   - Auth: none  
   - Enable the connector in a new chat  
   - Example ask: retrieve FAERS brief for tzield × Nausea; state data-through; hypothesis not causation  
   - Note: may need a paid Perplexity plan for custom connectors (say “check your plan” — do not invent pricing)

2. Optional: `/api` and `/llms.txt` one line each: Perplexity → `/mcp.md` Connectors.

## Keep

- No new `/signals` params
- No new MCP tools
- No pay gate
- No `ai-plugin.json` / `capabilities.json` / `llms-full.txt`

## Verify (live)

- `https://faers.mobi/mcp.md` mentions Perplexity Connectors and `https://faers.mobi/mcp`
- Hosted MCP still answers POST
- tzield×Nausea `/signals` still 200 n=319

## Out of scope

- Changing Perplexity’s product
- HTML wrappers for briefs
- Rate limits / 429
