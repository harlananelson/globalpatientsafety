# Pagination on GET /signals (limit / offset)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#31 threshold filters are live. Do not pile this onto #31.

## Problem

Common events silently hard-cap at 500. `limit=` and `sort=` are ignored today.

## Wanted

1. **API:** optional `limit=` and `offset=` on `GET /signals?drug=` and `GET /signals?event=` (JSON + CSV). Sane max (e.g. 500 or 1000). Combine with `trend=`, `novel=`, `min_eb05=`, `min_n=`.
   - Example: `?event=rash&min_eb05=5&limit=50&offset=50`
2. **Response:** JSON can include `total` (or `X-Total-Count`) so a client knows there are more than `limit`.
3. **UI:** page-size or Show more on isolated search (not splash).
4. **Optional if cheap:** serve `https://faers.mobi/API.md` (file exists in repo; site 404s; faers-mobi is private).
5. **Keep isolation.** Tzield not ziprasidone. Event path stays 200.

## Done when

- `GET /signals?event=rash&limit=20` returns 20 rows (not 500).
- `offset=` pages the rest; `total` (or header) is honest.
- CSV honors the same params.
- Live on https://faers.mobi. Deploy note with verify URLs.

## Out of scope

Pay gate, Stripe, changing default splash ranking, merging this GPS PR.
