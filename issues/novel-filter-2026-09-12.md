# Filter by Novel

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#29 Trend filter is live. Do not pile this onto #29.

## Wanted

Same shape as Trend filter, for the Novel column (novel / known / ?).

1. **UI:** chip or dropdown on isolated search (All / Novel / Known / Undetermined). Isolated search only, not splash.
2. **API:** optional `novel=` on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). e.g. `?event=rash&novel=novel`. Combine with `trend=` if cheap.
3. **Keep isolation.** Tzield/teplizumab not ziprasidone. Event path stays 200. Document in `API.md`.

## Done when

- Isolated rash/tzield can filter to Novel (or Known).
- `GET /signals?event=rash&novel=novel` returns only those rows.
- CSV honors the same param.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, fake labels, merging this GPS PR.
