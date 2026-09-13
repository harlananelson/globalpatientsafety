# Lowercase /api.md + head discovery links

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

ChatGPT’s 2026-09-13 cold-start test: root is indexed; exact search for `https://faers.mobi/api.md` found nothing; direct open failed in their browse layer. Live check the same day:

- `GET /API.md` → 200
- `GET /api.md` → **404**
- Banner / About / footer already have `<a href="/API.md">`, `/chatgpt.md`, `/openapi.json` (#66)
- `<head>` has no `rel="alternate"` / `service-desc`

Do **not** rebuild `/signals` or rewrite API.md. Give crawlers the lowercase path they actually type, and a graph edge in `<head>`.

## Scope

1. Serve `GET /api.md` as the same body as `/API.md` (301 or identical 200). Prefer 200 same bytes so a paste of the lowercase URL works in a safety-restricted browse layer.
2. Add `/api.md` to `robots.txt` (keep `/API.md` too).
3. In the homepage `<head>` (first tab HTML, not JS-only):

```html
<link rel="alternate" type="text/markdown" href="https://faers.mobi/API.md" title="faers.mobi API documentation" />
<link rel="alternate" type="text/plain" href="https://faers.mobi/api.md" title="faers.mobi API documentation" />
<link rel="service-desc" type="application/json" href="https://faers.mobi/openapi.json" />
<link rel="alternate" type="text/plain" href="https://faers.mobi/llms.txt" title="llms.txt" />
```

4. Add `API.md` (and `/api.md`) to the existing top **LLM / API access** banner so the first screen matches ChatGPT’s “API documentation · OpenAPI · ChatGPT guide”. Footer/About stay.

## Keep

- No new `/signals` params
- No new REST/MCP layer
- No pay gate
- Do not rename `/API.md` (uppercase stays canonical in our docs)

## Verify (live)

- `curl -sS -o /dev/null -w '%{http_code}' https://faers.mobi/api.md` → 200 (same idea as `/API.md`)
- `curl -sS https://faers.mobi/` HTML `<head>` contains `rel="alternate"` and `rel="service-desc"`
- Banner still says do not scrape; includes API.md / OpenAPI / ChatGPT
- `GET /signals?drug=tzield&event=Nausea` still 200 n=319

## Out of scope

- ChatGPT’s own URL-safety / no-DNS sandbox (we cannot fix)
- Rewriting API.md into their “Start here apixaban” stub
- Indexing delays on Bing/Google
