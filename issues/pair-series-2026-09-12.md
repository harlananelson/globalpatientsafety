# Pair time-course series (format=series)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#35 UI AND refine is live. Do not pile this onto #35.

## Problem

Humans already click a row for the quarterly time-course plot. API/LLM clients only get summary `trend` / `eb05_recent`. No series.

## Wanted

1. For an isolated `drug=` + `event=` pair, `GET /signals?drug=&event=&format=series` (or equivalent) returns the quarterly EWMA EB05 / n series that matches the UI plot.
2. Single-param JSON / CSV / filters unchanged.
3. Document in `API.md`. Keep isolation. Event path stays 200.

Example: `GET /signals?drug=tzield&event=Nausea&format=series`

## Done when

- That URL is 200 JSON with a quarter series (eb05 and n, or the same fields the plot uses).
- Tzield × Nausea is one pair, not every Nausea series.
- Live on https://faers.mobi. Deploy note with verify URL.

## Out of scope

Pay gate, Stripe, changing the UI plot, merging this GPS PR.
