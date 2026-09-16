# MCP wrapper for faers.mobi tools

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#38 `format=class` is live. Do not pile this onto #38.

## Problem

External LLMs still have to invent the REST calls. ChatGPT/Claude can use MCP if we expose the same `/signals` tools.

## Wanted

A thin MCP server over live GET `/signals`. No new statistics.

Tools (names can match this list):

- `search_drug` → `?drug=`
- `search_event` → `?event=`
- `get_signal` → `?drug=&event=`
- `get_signal_history` → `format=series`
- `get_profile` → `format=profile`
- `compare_class` → `format=class`
- `find_novel_signals` → `novel=` + `trend=` + thresholds

Ship:

1. MCP descriptor + stdio or HTTP transport next to the app (or a small sibling service).
2. One page an agent can read (`API.md` already public; add an MCP install snippet).
3. Preserve: signals are hypotheses, not causation. Return the underlying n/eb05/trend.

## Done when

- An MCP client can call `get_signal(tzield, Nausea)` and get the same 1-row AND isolation as REST.
- `compare_class(semaglutide, Nausea)` returns class_wide true.
- Documented. Live or installable from the box. Deploy note with how to point Claude/Cursor at it.

## Out of scope

Pay gate, Stripe, conversational UI on the site, `explain_signal` (client-side), merging this GPS PR.
