# CSV export of isolated drug/event results

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Do not implement SEARCH_REDESIGN.md wholesale. Deploy when good; post a note here.

Bars 1–4 are live (#23/#25/#26: Tzield isolation, `?drug=`, `GET /signals?drug=`, full-universe event search + `GET /signals?event=`). This slice is the next RWE takeaway gap: people can find pairs, but cannot download them.

## Problem

An RWE-style AE report ends in a spreadsheet or attachment. Today the UI table and JSON API are browse-only. Analysts re-copy rows by hand.

## Wanted (smallest ship)

### 1. CSV for the same isolation as live search / `/signals`

- `GET /signals?drug=tzield&format=csv` (and `?event=ischaemic%20stroke&format=csv`) returns the same isolated pairs as JSON, as CSV with header `drug,event,n,eb05,novel`.
- Or `Accept: text/csv` — pick one; document it in `API.md`.
- Empty isolation → empty CSV with header only (or 204). Do not dump the splash top-N.

### 2. One UI affordance

A Download CSV control on https://faers.mobi that exports the **current** isolated result set (after a drug or event search), not the splash list. Deep-link friendly if cheap (`?drug=` / `?q=` already isolate).

## Done when

- CSV endpoint matches JSON isolation for `tzield` / `teplizumab` and `ischaemic stroke` / `ischemic stroke`.
- UI can download that set after search.
- `API.md` documents the CSV form.
- Live on https://faers.mobi with a deploy note and verify URL(s) on this PR.

## Out of scope

Pay gate / Stripe / billing (needs Harlan). SEARCH_REDESIGN phases 2–8 (priority splash redesign, class stratification, PDF micropayments, enterprise API tiers). Merging this GPS PR.
