# Signal trends (is this getting stronger?)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Do not implement SEARCH_REDESIGN.md wholesale. Deploy when good; post a note here. Pay gate / billing is out of scope.

#27 CSV is live. Do not pile this onto #27.

## Wanted

For an isolated drug or event result set, show whether each pair is rising or fading.

1. **Table:** a `Trend` column on the isolated search (not the splash). Values: Accelerating / Rising / Stable / Declining / New (or arrows). Sortable.
2. **API:** same fields on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). e.g. `trend`, optional `eb05_recent`, `eb05_prior`.
3. **Keep isolation.** `?drug=tzield` / `?q=teplizumab` still not ziprasidone. Event search still hits Ischaemic stroke for both spellings.

Cheap definition is fine: last-4-quarter slope vs prior window, or latest vs prior peak. Do not rebuild the whole compute pipeline if the existing parquet already has per-quarter EB05.

## Done when

- Isolated Tzield/teplizumab table shows Trend; isolation holds.
- `GET /signals?drug=tzield` JSON includes `trend` (or equivalent) on rows.
- CSV includes the same column.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, period-picker UI, class-wide temporal signals, merging this GPS PR.
