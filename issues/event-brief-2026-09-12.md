# Event-only format=brief (RWE markdown)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#57 Event profile is live. Do not pile this onto #57.

## Problem

Drug `GET /signals?drug=&format=brief` is live markdown. Event-only `format=profile` is now 200, but event-only `format=brief` is still missing (or 400). API/LLM clients cannot get an AE-centric RWE brief.

## Wanted

`GET /signals?event=&format=brief` returns the same markdown stitch as the drug brief, from the live event profile.

1. Event required. Drug+event keeps the existing pair brief. Drug-only unchanged.
2. Stitch live event `format=profile` (n_drugs / n_pairs, faers_through, trend/novel mix, top drugs). Include class/series only where they already apply.
3. Disclaimer always. `Content-Type: text/markdown` like #45.
4. Update API.md + openapi.json (and llms.txt / chatgpt.md if those list brief).
5. Event-only UI profile and event PDF wait for later slices.

Example: `GET /signals?event=Nausea&format=brief`

No new compute. No billing / pay gate.

## Done when

- That URL is 200 markdown matching the event profile numbers (Nausea: 2459 pairs, top n otezla, Data through 2025Q4).
- Drug-only / pair brief unchanged. Documented. Deploy note with the URL.

## Out of scope

Pay gate, Stripe, site chat box, event-only UI/PDF, new statistical compute, merging this GPS PR.
