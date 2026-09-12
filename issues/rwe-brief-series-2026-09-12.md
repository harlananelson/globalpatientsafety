# Enrich RWE brief with format=series

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#43 Copyable RWE brief is live. Do not pile this onto #43.

## Problem

The copyable brief already stitches profile + class + explain_signal. A selected pair still omits the quarterly time-course that `GET /signals?drug=&event=&format=series` already returns. Humans and LLMs have to fetch series separately.

## Wanted

When a pair is selected, fold live quarterly series / trend context into the same copyable brief and MCP `rwe_brief`.

1. Isolated pair (drug + event selected): include live `format=series` context in the existing RWE brief (textarea + Copy). Same text from MCP `rwe_brief` if that template exists.
2. Keep it compact: last few quarters or a short trend summary from the series (`n`, `eb05` / `eb50` / `eb95`, `ewma_eb05`) — not a dump of the whole JSON.
3. Drug-only pages stay as they are (no pair, no series). Event-only can skip.
4. No new compute. Numbers must match the live series API.
5. Disclaimer stays. Document the extra stanza in `API.md` if `rwe_brief` is documented.

Example: `GET /signals?drug=tzield&event=Nausea&format=series`

## Done when

- https://faers.mobi/?drug=tzield with Nausea selected shows series / trend context in the same copyable brief, matching that series URL.
- MCP `rwe_brief` matches if present.
- Live. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
