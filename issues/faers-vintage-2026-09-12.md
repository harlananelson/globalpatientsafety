# FAERS data vintage (through-quarter) on UI + API

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#52 Public MCP install files are live. Do not pile this onto #52.

## Problem

RWE briefs, series, and MCP answers have no explicit “data through” quarter. A reviewer cannot tell whether live aggregates stop at 2025Q4 or an older extract without inferring from series max.

## Wanted

Expose which FAERS quarter the live aggregates cover (e.g. 2025Q4 from existing series max).

1. About plus a small UI chip or footer: data through YYYYQn.
2. API: `X-FAERS-Through` and/or a field on `format=profile` / `format=brief` / docs.
3. Brief update to `API.md` and `llms.txt`.

No new compute — read from the existing signal store. No billing / pay gate.

## Done when

- Home / `?drug=tzield` shows the through-quarter.
- API header and/or profile/brief field matches (e.g. 2025Q4 for tzield×Nausea series max).
- Documented. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
