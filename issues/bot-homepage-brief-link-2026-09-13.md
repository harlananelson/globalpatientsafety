# Bot-facing homepage + "copy link for your LLM" on the selected pair

Handshake only. Implement in `/projects/faers-mobi/`. Deploy when good.

Diagnosis (2026-09-13, verified with curl as `ChatGPT-User`): every discovery
surface is live and correct — `/llms.txt`, `/api.md`, `/openapi.json` (valid 3.0.3,
one path), `/chatgpt.md`, `/mcp` (answers `initialize`). #66/#69/#70 copy is in the
first extracted paragraph. ChatGPT / Perplexity / Gemini still "describe the table"
because a pasted URL in those chats is a **one-shot page fetch**: they do not follow
links, cannot issue their own `GET /signals`, and cannot pick up OpenAPI/MCP from a
chat. The banner is an instruction they have no tool to obey. Stripped of Shiny JS,
`/` is prose about a table that is not in the HTML.

What already works: paste
`https://faers.mobi/signals?drug=tzield&event=Nausea&format=brief` — it is markdown,
so the fetched page **is** the answer. The fix is to make that the thing bots and
humans reach first.

## Scope

1. **Serve bots a markdown homepage.** In nginx, when the `User-Agent` for `GET /`
   matches a known LLM fetcher, return `text/markdown` instead of the Shiny shell.
   Match (case-insensitive): `ChatGPT-User`, `OAI-SearchBot`, `GPTBot`,
   `PerplexityBot`, `Perplexity-User`, `ClaudeBot`, `Claude-User`, `Claude-SearchBot`,
   `anthropic-ai`, `Google-Extended`, `Googlebot`, `Bingbot`, `cohere-ai`, `Bytespider`,
   `Applebot`. Body = `/llms.txt` content plus one worked brief inlined (tzield × Nausea,
   or a nightly-cached copy of that `format=brief` output), plus one sentence on how to
   build a brief URL for any drug or event. Serve it from a static file nginx owns;
   do not route bots into Shiny. Humans and unknown agents get the Shiny page unchanged.

2. **"Copy link for your LLM" on the selected pair.** In the Shiny UI, next to the
   time-course plot for the selected row, show the brief URL for that pair
   (`/signals?drug=<d>&event=<e>&format=brief`) with a copy button and one line:
   "Paste this into ChatGPT, Claude, or Perplexity and ask about it." Same for the
   event-only and drug-only profile pages if they exist. This is the human-facing half
   of the same fix: a visitor should never have to know `format=` exists.

3. **Lead with the brief URL in the existing machine-client copy** (banner + first
   `<p>` from #66/#70): put the worked brief link first, before `/api`, `/api.md`,
   `/openapi.json`, `/chatgpt.md`, `/mcp`. Keep every existing link.

4. **`/.well-known/*` → 404, not 403.** Cosmetic; do it while in the nginx file.

## Keep

- No new `/signals` params, no new formats, no `/api/v1/`
- No pay gate
- No change to OpenAPI / MCP / `format=brief` body
- Existing banner, first paragraph, `<meta name="description">`, head links stay
- Do not touch aers-mobi; do not deploy `renv/activate.R`

## Verify (live, body numbers not just 200)

- `curl -sS -A ChatGPT-User https://faers.mobi/` → `text/markdown`, body contains
  `format=brief`, `n=319` (or the current tzield × Nausea `n`), and `Data through 2025Q4`
- `curl -sS -A PerplexityBot https://faers.mobi/` and `-A ClaudeBot` → same body
- `curl -sS -A Mozilla/5.0 https://faers.mobi/` → unchanged Shiny HTML, banner present,
  `<meta name="description">` present
- Homepage HTML contains a `format=brief` href in the banner **and** in the first `<p>`
  after `<h4>Signals by drug and event</h4>`
- Selecting tzield × Nausea in the UI shows a copyable
  `https://faers.mobi/signals?drug=tzield&event=Nausea&format=brief`
- `GET /signals?drug=tzield&event=Nausea` still 200 n=319
- `GET /.well-known/ai-plugin.json` → 404
- Acceptance test that settles the original complaint: paste `https://faers.mobi/`
  into ChatGPT with browsing and ask "what does this site say about tzield and
  nausea" — the answer should quote `n=319` and mention `GET /signals`.

## Out of scope

- Registering the Custom GPT (import `/chatgpt.md` → `/openapi.json`) and adding the
  MCP connector in claude.ai. Those are one-time account actions Harlan does, and are
  the only route to multi-turn "ask the data" in those products. Link the resulting GPT
  from the homepage once it exists.
- Perplexity / Gemini consumer chat have no custom-tool surface; the bot homepage +
  brief URL is the ceiling there.
- Search-index lag; rewriting API.md.
