# Filter / sort by Trend

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope. Do not implement SEARCH_REDESIGN.md wholesale.

#28 Trend is live on drug and event paths. Do not pile this onto #28.

## Wanted

Make the Trend column actionable on isolated search.

1. **UI:** filter and/or default sort so Accelerating and Rising surface first (isolated search only, not splash). A chip or dropdown for Accelerating / Rising / Stable / Declining / New is enough.
2. **API:** optional `trend=` on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). e.g. `?event=rash&trend=Accelerating`. Comma or repeat for several values is fine.
3. **Keep isolation.** Tzield/teplizumab not ziprasidone. `ischemic`/`ischaemic stroke` still Ischaemic stroke. Event path must stay 200 (no 502 regression).

## Done when

- Isolated `?q=rash` / `?drug=tzield` can show Accelerating/Rising first (or filter to them).
- `GET /signals?event=rash&trend=Accelerating` returns only those rows, still isolated, with `trend`.
- CSV honors the same param.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, period-picker, class-wide temporal, merging this GPS PR.
