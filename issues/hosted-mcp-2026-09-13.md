# Hosted MCP (HTTP)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#61 leftover docs scrub is live. #52 public MCP files (stdio `server.py`) stay as they are.

## Problem

MCP today is “download `server.py` and run it locally.” ChatGPT / Claude / Cursor that can take a remote MCP URL still have to fetch a file. The tools already exist; the transport does not.

## Wanted

A hosted MCP endpoint on faers.mobi that speaks the same tools as the stdio server, over HTTP.

1. Stable URL (e.g. `https://faers.mobi/mcp`) — Streamable HTTP or SSE, whichever the existing stack can ship cleanly.
2. Same tools, same payloads: search_drug / search_event / get_signal / get_signal_history / get_profile / compare_class / rwe_brief / explain_signal / find_novel_signals. No new compute — wrap live `GET /signals`.
3. Auth none. Hypothesis disclaimer in the server instructions / tool descriptions (already true for stdio).
4. Keep `/mcp/server.py` and the Claude Desktop example working (local stdio remains a path).
5. Update `mcp.md`, `llms.txt`, footer/About, and `API.md` with the hosted URL and a one-line paste for Cursor / Claude / ChatGPT custom MCP.

## Done when

- A client can add `https://faers.mobi/mcp` (or the shipped path) and call `get_signal drug=tzield event=Nausea` → n=319, same as stdio / REST.
- `rwe_brief` still matches `format=brief`.
- Docs list the hosted URL. Deploy note with that URL.

## Out of scope

Pay gate, Stripe, site chat box, FDA label status (next slice), new statistical compute, merging this GPS PR.
