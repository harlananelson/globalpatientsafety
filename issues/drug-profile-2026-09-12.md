# Drug profile brief (format=profile)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#36 `format=series` is live. Do not pile this onto #36.

## Problem

An LLM still has to stitch `drug=` + `novel=` + `trend=` + sort to answer “profile tzield.” One shot should be enough.

## Wanted

`GET /signals?drug=tzield&format=profile` (or `GET /profile?drug=tzield`) returns a compact RWE-ready snapshot:

- isolated drug names, pair count, `X-Total-Count`
- top pairs by eb05 and by n (small lists)
- novel + rising/accelerating subset
- trend mix counts
- known vs novel vs `?` counts

Reuse existing isolation and filters. No new compute. Document in `API.md`. Event-only profile is out of this slice unless it is free.

## Done when

- `GET /signals?drug=tzield&format=profile` is 200 JSON an LLM can read in one call.
- Isolation holds (no ziprasidone).
- Pair list / series / CSV unchanged.
- Live on https://faers.mobi. Deploy note with verify URL.

## Out of scope

Pay gate, Stripe, MCP, conversational UI, `compare_class`, merging this GPS PR.
