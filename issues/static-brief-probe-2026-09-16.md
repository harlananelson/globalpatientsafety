# Static brief probe (ChatGPT “not safe to open” diagnostic)

Handshake only. Do not merge. Implement in `/projects/faers-mobi/` (nginx static). Deploy when good.

OpenAI (2026-09-16): homepage `text/plain` works; `GET /signals?...` JSON and brief fail with instant **“Not safe to open.”** Hypotheses: cached deny, query-string block, different infra, Accept/UA cache, or slow dynamic compute.

Live from Career box: brief ~3s 200 `text/plain`; JSON ~1.3s 200. Bot-UA homepage already inlines the tzield×Nausea brief (#72). Instant “not safe” is unlikely our 3s compute.

## Experiment (one file)

Serve **one** static URL, no query string, same body as current tzield×Nausea `format=brief` (or the bot-home worked-example section), `Content-Type: text/plain; charset=utf-8`:

`https://faers.mobi/examples/tzield-nausea-brief.txt`

Optional alias only if trivial: `/brief/tzield-nausea.txt` → same file. **Do not** build `/brief/{drug}/{event}` routing.

Log access (nginx) so we see whether ChatGPT’s fetch **reaches** the server when they retest.

Link it once from bot homepage / `/api` / `llms.txt` as “static example (no query string)” so they can find it.

## Interpret

| Result | Conclusion |
|--------|------------|
| Static `.txt` works; `/signals?...` still “not safe” | Fetcher blocks query-string or `/signals` path — **stop** API MIME/discovery churn; use Actions/MCP |
| Static also “not safe” and **no** nginx hit | Allowlist / remote deny — app changes won’t help |
| Static slow/empty and **nginx hit** | Then look at proxy/timeouts |

## Keep

- No change to `/signals` contract
- No pay gate
- Do not revert bot-UA homepage

## Verify (live)

- `curl -sS -D - https://faers.mobi/examples/tzield-nausea-brief.txt` → 200 text/plain, body has n=319 / 2025Q4
- `/signals?drug=tzield&event=Nausea&format=brief` still 200
- Linux notes whether probe URL appears in access log when OpenAI retests

## Out of scope

- General path-style API
- Precompute all briefs
- Rate limits
