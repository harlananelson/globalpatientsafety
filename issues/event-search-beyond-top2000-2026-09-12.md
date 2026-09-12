# Event search beyond top-2000

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Do not implement SEARCH_REDESIGN.md wholesale. Deploy when good; post a note here.

Bars 1–3 from #23/#25 are live (Tzield isolation, `?drug=` named URL, `GET /signals?drug=`). This slice is the next usefulness gap for RWE-style AE reports.

## Problem

The timeline still pre-filters toward a top EB05 set before search. Event queries like `ischaemic stroke` / `ischemic stroke` can miss clinically real pairs that sit outside that window. Drug isolation for Tzield is fixed; event findability is not.

## Wanted (smallest ship)

### 1. Server-side event (and drug) search against the full pair universe

When the user types an event or drug term, match against the full flagged-pair set (not only the splash top-N). Keep current Tzield/drug isolation ranking for drug queries.

- Spelling normalize so `ischemic` finds `ischaemic`.
- Debounce so typing does not hammer parquet.
- Empty query keeps today’s splash (top / priority list) — do not rebuild the whole priority redesign.

### 2. One verify case

`https://faers.mobi/?q=ischaemic%20stroke` (and `ischemic stroke`) returns ischaemic-stroke pairs that were previously invisible under top-2000-only filtering. Include at least one known-out-of-window pair if still available in data.

Optional same slice if cheap: `GET /signals?event=ischaemic%20stroke` with the same isolation rules, documented in `API.md`. Skip if it blocks the UI fix.

## Done when

- Event search finds pairs outside the old top-2000 window.
- Existing drug isolation for `tzield` / `teplizumab` still holds (no ziprasidone regression).
- Live on https://faers.mobi with a deploy note and verify URL(s) on this PR.

## Out of scope

Pay gate / Stripe / billing (needs Harlan). SEARCH_REDESIGN phases 3–8 (priority splash redesign, class stratification, PDF micropayments, enterprise API tiers). Merging this GPS PR.
