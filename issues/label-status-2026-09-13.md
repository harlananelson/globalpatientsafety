# FDA label status (get_label_status)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#62 Hosted MCP is live. Do not pile this onto #62.

## Problem

Pair rows already carry `novel` = known / novel / ? from the cached FDA label. LLMs still have to infer label status from a signal row. The ChatGPT tool list wanted `get_label_status` as its own call.

## Wanted

A dedicated label-status read over the **existing** Novel / FDA-label cache. No new OpenFDA scrape this slice.

1. HTTP: `GET /signals?drug=&event=&format=label` (both required) returns one JSON object: drug, event, `novel` (known / novel / ?), `faers_through`, and any cached label snippet already in the store (omit the field if none).
2. MCP: `get_label_status` on hosted `/mcp` and stdio `server.py`, same payload.
3. 400 if drug or event is missing. Drug-only / event-only stay as they are.
4. Document in API.md, openapi.json, mcp.md. One-line in llms.txt if those list tools.

Example: `GET /signals?drug=tzield&event=Nausea&format=label` → novel known (matches the pair row).

No new compute. No billing / pay gate.

## Done when

- That URL is 200 JSON with novel matching `GET /signals?drug=tzield&event=Nausea`.
- MCP `get_label_status` returns the same.
- Documented. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, site chat box, live OpenFDA refetch, new statistical compute, merging this GPS PR.
