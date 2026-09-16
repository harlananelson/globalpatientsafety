# UI pair refine (drug AND event)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#34 AND isolation is live on the API and `?drug=&event=` deep-link. Do not pile this onto #34.

## Problem

`event_refine` is `display:none`. Humans can AND-isolate only by crafting a URL. The API already does the right thing.

## Wanted

1. Unhide/wire a visible event refine (or a second box) on isolated drug search so people can add an event without leaving the page.
2. Same AND isolation as `GET /signals?drug=&event=` (and the reverse if cheap: refine drug on an event search).
3. Single-param search unchanged. Deep-link `?drug=tzield&event=Nausea` stays.
4. Document if the UI param names differ.

## Done when

- On https://faers.mobi/?drug=tzield a person can type Nausea (or pick it) and see only tzield/teplizumab × Nausea — no URL editing.
- API paths unchanged. Live. Deploy note with a screenshot-free verify path.

## Out of scope

Pay gate, Stripe, merging this GPS PR.
