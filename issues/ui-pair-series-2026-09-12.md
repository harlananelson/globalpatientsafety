# UI pair time-course (format=series)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#45 HTTP format=brief is live. Do not pile this onto #45.

## Problem

`format=series` is live and already folded into the copyable RWE brief (#44) and HTTP `format=brief` (#45). Humans still have no on-page quarterly table or sparkline for the selected pair — they only get the compact Series stanza in the brief.

## Wanted

Surface live `GET /signals?drug=&event=&format=series` on the selected pair.

1. Compact quarterly table or sparkline: `n` / EB05 / EWMA (same fields the series API already returns).
2. Pair-only. Drug-only and event-only skip.
3. No new compute. Numbers must match the live series API and the brief's Series stanza.
4. Keep isolation. Do not change `format=brief` / MCP `rwe_brief` unless a one-line "see series" pointer is needed.

Example: selected tzield × Nausea on https://faers.mobi/?drug=tzield

## Done when

- That selected pair shows the quarterly series (table or sparkline) matching `GET /signals?drug=tzield&event=Nausea&format=series` (11 quarters 2023Q2–2025Q4).
- Drug-only / event-only pages do not show it.
- Live. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
