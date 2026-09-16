# HTML /api page (same docs as /api.md)

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

Gemini (2026-09-13) can fetch `/` but **Failed to fetch** `https://faers.mobi/api.md` with no status. Live: `/api.md` is 200 `Content-Type: text/plain`. `/api` is 404. Their extractor is built for article HTML, not raw Markdown.

Do **not** add `/api/v1/` or a second signal API. Keep `/api.md` as `text/plain` for agents that want the file. Add one HTML companion.

## Scope

1. `GET /api` → 200 `text/html`, server-rendered (not Shiny-hydrated). Semantic `<main>`, `<h1>` like “How to query faers.mobi”, ordinary paragraphs.
2. Same facts as `/api.md`: `GET /signals`, example `https://faers.mobi/signals?drug=tzield`, formats, hypothesis-not-causation, links to openapi.json / chatgpt.md / mcp / llms.txt.
3. Homepage already-plain first paragraph (and banner) get an ordinary `<a href="/api">` next to `/api.md`.
4. Optional: `/api/` same as `/api`. Do not create `/docs/api` or `/how-to-query` unless `/api` collides.

## Keep

- `/api.md` and `/API.md` unchanged (text/plain 200)
- No new `/signals` params
- No pay gate
- No ChatGPT “ask a question” box

## Verify (live)

- `curl -sS -D - -o /dev/null https://faers.mobi/api` → 200, `Content-Type` includes `text/html`
- Body contains `GET /signals` and `tzield` (or another real example) in `<main>` / `<h1>` text, not only an alert
- `curl -sS https://faers.mobi/` HTML includes `href="/api"`
- `/api.md` still 200 text/plain
- `GET /signals?drug=tzield&event=Nausea` still 200 n=319

## Out of scope

- Gemini/ChatGPT search-index lag (they still cite the old VAERS GitHub blurb)
- Changing `/api.md` to `text/html` (would break raw-md clients)
- New REST paths
