# Event profile brief (format=profile for event=)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#56 OpenAPI application/pdf is live. Do not pile this onto #56.

## Problem

Drug `GET /signals?drug=&format=profile` is live. Event-only `format=profile` is still 400 (`format=profile requires drug`). An AE-centric RWE snapshot has no compact JSON.

## Wanted

Allow `GET /signals?event=&format=profile`.

1. Event required. Drug optional — if both set, keep current drug-focused profile behavior or document clearly.
2. One JSON object mirroring the drug profile shape where it makes sense: query, n_drugs / n_pairs, `faers_through`, trend mix, novel mix, `top_eb05` / `top_n` / `novel_rising` as drug rows for that event.
3. No new disproportionality math — aggregate from the existing isolated event set.
4. Update API.md + openapi.json (and a brief mention in llms.txt / chatgpt.md if those list profile).
5. Event-only `format=brief` / UI surface can wait for a later slice.

Examples:
- `GET /signals?event=Nausea&format=profile`
- Drug+event or drug-only profile stays as today.

## Done when

- Event-only profile is 200 JSON with those fields (e.g. Nausea has n_drugs / n_pairs and top drugs).
- Documented. Drug-only profile unchanged. Deploy note with the event URL.

## Out of scope

Pay gate, Stripe, site chat box, event-only brief/PDF/UI, new statistical compute, merging this GPS PR.
