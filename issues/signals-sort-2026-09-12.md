# sort= on GET /signals

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#32 pagination is live. Do not pile this onto #32.

## Problem

`sort=` is ignored. `?event=rash&sort=n` still comes back in default EB05 / Accelerating order.

## Wanted

1. **API:** optional `sort=` and `order=` (`asc`/`desc`, default `desc`) on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). Allowed keys: `eb05`, `n`, `trend` (and `novel` if cheap). Combine with `limit=`, `offset=`, `trend=`, `novel=`, `min_eb05=`, `min_n=`.
   - Example: `?event=rash&sort=n&order=desc&limit=20`
2. **UI:** column sort or a sort control on isolated search (not splash).
3. **Docs:** `API.md`. Keep isolation. Event path stays 200.

## Done when

- `GET /signals?event=rash&sort=n&limit=5` is ordered by n (not eb05).
- `sort=eb05` still works. Pagination + filters still apply.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, changing splash ranking, merging this GPS PR.
