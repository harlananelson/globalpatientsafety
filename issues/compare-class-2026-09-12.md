# compare_class (ATC4)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#37 `format=profile` is live. Do not pile this onto #37.

## Problem

LLM tool map still missing `compare_class`. We can say tzield × Nausea is Rising; we cannot say whether that is drug-specific or class-wide.

## Wanted

Cheap read of existing ATC class data (do not recompute disproportionality).

1. `GET /signals?drug=tzield&event=Nausea&format=class` (or `GET /signals?drug=tzield&format=class`) returns the drug’s ATC4 class and same-class peers for that event (or top events if event omitted): peer drug, n, eb05, novel, trend if already attached.
2. A short flag if several class peers also light up (class-wide hint — not a new statistical method).
3. Isolation holds. Document in `API.md`. Single-param list / profile / series unchanged.

## Done when

- `GET /signals?drug=tzield&event=Nausea&format=class` is 200 JSON an LLM can read.
- Tzield still isolated from ziprasidone.
- Live on https://faers.mobi. Deploy note with verify URL.

## Out of scope

Pay gate, Stripe, MCP, conversational UI, stratified recompute, merging this GPS PR.
