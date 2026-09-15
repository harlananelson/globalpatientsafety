# Serve machine Markdown as text/plain

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

LLM fetch tool (2026-09-15) failed homepage with an **explicit** error: `Unsupported content-type: text/markdown`. `/api.md` already works as `text/plain`. OpenAPI JSON was readable. Separate failures on JSON `/signals` were “not safe to open” — that is the fetch tool’s allowlist, not a MIME bug. Do not invent a WAF change from this PR.

## Scope

Keep Markdown **bodies**. Change only `Content-Type` to `text/plain; charset=utf-8` for:

1. `GET /signals?...&format=brief` (and any other route that returns the same markdown brief body)
2. Bot-UA homepage response from #72 (currently `text/markdown` for ChatGPT-User / PerplexityBot / ClaudeBot)
3. `GET /bot-home.md` if it is still `text/markdown`

Do **not** change:

- Human Mozilla homepage (`text/html` Shiny)
- `GET /api` HTML
- `/api.md` / `/API.md` (already text/plain)
- `openapi.json` (`application/json`)
- `format=pdf` (`application/pdf`)
- Default `/signals` JSON

Optional one-liner in API.md: machine markdown is served as `text/plain; charset=utf-8` so restricted page readers accept it; body is still Markdown.

## Verify (live)

- `curl -sS -D - -o /dev/null 'https://faers.mobi/signals?drug=tzield&event=Nausea&format=brief'` → 200, `Content-Type: text/plain` (body still starts with `# RWE brief`, sum n=319)
- `curl -sS -A ChatGPT-User -D - -o /dev/null https://faers.mobi/` → 200, `text/plain` (not text/markdown)
- Mozilla homepage still `text/html`
- `/api.md` still 200 text/plain
- JSON `/signals?drug=tzield&event=Nausea` still 200 application/json, n=319

## Out of scope

- Making their fetch tool allowlist `faers.mobi` for JSON (“not safe to open”)
- HTML wrappers for briefs
- Pay gate
- Exact-event PT (#73) — separate open slice
