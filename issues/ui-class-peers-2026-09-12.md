# UI class peers (format=class)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#41 UI profile brief is live. Do not pile this onto #41.

## Problem

`GET /signals?drug=&event=&format=class` is live (#38). Humans on a selected pair still don’t see ATC4 peers or `class_wide`. API-only.

## Wanted

Surface the existing class JSON on the selected pair (and/or `?drug=&event=` deep-link). No new compute.

1. When a pair is selected, show ATC4 class, `class_wide` hint, and a short peer list (drug, n, eb05, trend if present).
2. Reuse `format=class`. Isolation unchanged.
3. Skip when there is no `drug=` (class still requires drug).

## Done when

- https://faers.mobi/?drug=tzield&event=Nausea shows Other antidiabetics / not class-wide.
- https://faers.mobi/?drug=semaglutide&event=Nausea shows GLP-1 / class-wide + peers.
- Numbers match the API. Live. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, site chat box, new `/signals` formats, merging this GPS PR.
