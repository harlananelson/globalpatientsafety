# explain_signal (client)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#39 MCP is live. Do not pile this onto #39.

## Problem

Tools return n / eb05 / trend / novel / class_wide. Nothing turns those fields into a one-paragraph hypothesis an LLM or a human can read without inventing stats.

## Wanted

Client-side only. No new server statistics. No new `/signals` formats.

1. A small helper (R or JS in the app, plus a short prompt snippet in `API.md`) that takes an existing pair or `format=class` payload and writes 3–6 sentences:
   - what was isolated
   - n, eb05, trend, novel
   - class-wide or drug-specific if `format=class` was used
   - **this is a statistical hypothesis, not causation**
2. UI: an Explain control on the isolated pair (optional if the helper + API.md prompt is enough).
3. MCP: do **not** add an explain tool that computes new numbers. If you add one, it only templates the same fields.

## Done when

- Tzield × Nausea can be explained from live JSON without new compute.
- Disclaimer is always present.
- API.md has the prompt/helper. Live. Deploy note with one example paragraph.

## Out of scope

Pay gate, Stripe, site chat box, new EB05 math, merging this GPS PR.
