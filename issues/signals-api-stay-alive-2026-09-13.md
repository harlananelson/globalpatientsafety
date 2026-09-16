# Harden GET /signals stay-alive under format=brief load

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

## Why

On 2026-09-13 the homepage banner (#66) was already in the HTML, but `GET /signals` hung ~2h with **listen socket open and 0 bytes out**. Cause: single-thread httpuv on `:3841` (`faers-signals-api`) pinned under a concurrent `format=brief` storm (MistralAI-User; nginx 499s). R sat ~25% CPU / 1.1 GB and stopped answering bodies. Recycle recovered tzield×Nausea (`n=319`).

The product bar is: **`/signals` keeps returning a body under concurrent `format=brief`**. No new API surface.

## Scope

Make the API stay alive when several `format=brief` (or other slow format) requests arrive together. Linux picks the mechanism. Acceptable directions:

- request timeout so one brief cannot pin the only worker forever
- bounded queue / fail-fast (503 or 429) instead of 0-byte hang
- more than one httpuv/plumber worker
- nginx read timeout + recycle of a stuck worker

Do **not** add query params, a second REST/MCP layer, or pay-gate work.

## Keep

- Same `GET /signals` contract (json / csv / series / profile / class / brief / pdf / label)
- Homepage banner, footer, About links
- Pair tzield×Nausea still `n=319`

## Verify (live)

- `GET /signals?drug=tzield&event=Nausea` → 200, body has `n=319` (not just HTTP 200)
- Same pair `format=brief` → 200 markdown
- Several parallel `format=brief` requests must not leave a later `/signals` hung at 0 bytes. A 503/429 with a body is OK; silence is not.
- Homepage still has the LLM / API banner

## Out of scope

- `soc=` / `min_signal_quarters=` / `indication_confounded=` / `max_class_coflags=`
- Pay gate
- Conversational UI
