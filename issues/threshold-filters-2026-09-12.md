# Threshold filters (min EB05 / min n)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#30 Novel filter is live. Do not pile this onto #30.

## Wanted

Let an isolated search drop weak pairs.

1. **API:** optional `min_eb05=` and `min_n=` on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). Combine with `trend=` and `novel=`.
   - Example: `?event=rash&novel=novel&min_eb05=5&min_n=10`
2. **UI:** two small controls on isolated search (not splash). Defaults empty = no extra cut.
3. **Keep isolation.** Tzield/teplizumab not ziprasidone. Event path stays 200. Document in `API.md`.

## Done when

- `GET /signals?event=rash&min_eb05=5` returns only rows with eb05 ≥ 5.
- `min_n=` works the same for n.
- Combined with `novel=` / `trend=` still 200 and filtered.
- Isolated UI can set the same cuts.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, changing default splash, merging this GPS PR.
