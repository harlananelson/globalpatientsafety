# PDF/Typst download of RWE brief

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#53 FAERS data vintage is live (through 2025Q4). Do not pile this onto #53.

## Problem

The copyable RWE brief and `format=brief` are live, but a reviewer still has to paste markdown into another tool to get a file they can attach to an email or protocol folder.

## Wanted

Same content as live `format=brief` / UI copyable RWE brief → downloadable PDF.

1. UI control on isolated `?drug=` and selected pair (same brief they already copy).
2. Optional `GET /signals?...&format=pdf` if cheap.
3. Typst preferred if already in the stack; otherwise a pragmatic PDF.
4. Include disclaimer, data-through quarter, and the same profile / class / series stanzas as the brief.
5. Document in `API.md`.

No new compute. No billing / pay gate.

## Done when

- Isolated `?drug=tzield` (and tzield×Nausea) can download a PDF whose text matches the live brief.
- Optional `format=pdf` 200 if shipped.
- Documented. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, site chat box, new statistical compute, merging this GPS PR.
