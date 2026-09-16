# OpenAPI 3 schema for GET /signals

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#46 UI pair time-course is live. Do not pile this onto #46.

## Problem

`API.md` documents `/signals` for humans. ChatGPT Actions and other LLM clients still have to scrape markdown or run local stdio MCP to discover params and formats.

## Wanted

A machine-readable OpenAPI 3 companion to public `API.md` covering live `/signals`.

1. Params and formats already live: `json` / `csv` / `series` / `profile` / `class` / `brief`, plus filters, pagination, and sort.
2. Serve at a stable path (e.g. `/openapi.json`) so Actions / curl / other clients can fetch it.
3. No new compute. Schema describes existing endpoints only.
4. Point `API.md` at the schema URL.

Examples the schema must document:
- `GET /signals?drug=tzield&event=Nausea&format=series`
- `GET /signals?drug=tzield&event=Nausea&format=brief`

## Done when

- Schema validates as OpenAPI 3.
- Live at the stable path. Those two URLs are documented.
- Deploy note with the schema URL.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
