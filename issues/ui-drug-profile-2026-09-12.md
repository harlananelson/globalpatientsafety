# UI drug profile brief

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#40 `explain_signal` is live. Do not pile this onto #40.

## Problem

`GET /signals?drug=tzield&format=profile` is live (#37). Humans on `?drug=tzield` still only get the table. The compact snapshot (trend/novel mix, top eb05, top n, novel+rising) is API-only.

## Wanted

Surface the existing profile JSON on isolated `?drug=` pages. No new compute.

1. A short brief above the table: pair count, novel/known mix, trend mix, top EB05, top n, novel+rising.
2. Reuse `format=profile`. Isolation unchanged.
3. Optional: same brief for a deep-link. Event-only pages can skip (profile still requires `drug=`).

## Done when

- https://faers.mobi/?drug=tzield shows the profile brief without a separate API call by the human.
- Numbers match `GET /signals?drug=tzield&format=profile`.
- Live. Deploy note with that URL.

## Out of scope

Pay gate, Stripe, site chat box, new `/signals` formats, merging this GPS PR.
