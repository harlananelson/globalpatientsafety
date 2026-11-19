# Bulk export of /signals rows for Portfolio safety

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`. Deploy when good.

## Why

Portfolio safety (globalpatientsafety.com/portfolio, live since 2026-11-17) lists FAERS signals
for every NDA/BLA ingredient a company markets. faers.mobi is its only source; it computes no
statistic itself. To build its cache it currently makes one call per ingredient set:

```
GET /signals?drug=<ingredient>&indication=hide&low_info=hide&medication_error=hide
            &min_n=10&sort=eb05&order=desc&limit=300
```

That is about 1,800 serial calls with a 2 s pause. The first full fill started 2026-11-18
11:07 UTC and was at 1,596 cache files after 1 h 50 min. Calls are serial because parallel
calls returned 504 (4 of 6 during development). A weekly refresh would repeat the full
load on faers.mobi every Sunday, so the timer stays disabled until this export exists.

The per-drug query also needs a lot of client-side cleanup. `drug=` matches by substring, so
the answer for "insulin" or "iron" pulls in other products. Portfolio has to filter rows again
by ingredient and brand (`row_belongs`, `ingredient_aliases` in
`globalpatientsafety/scripts/gps_portfolio.py`).

## Ask

One file covering every drug, produced when signals.parquet is deployed. It should hold the
same rows `/signals` would return under the filters above, so there is still one source of
truth for indication, low-information and medication-error hiding, label status and trend.

1. An endpoint or static file, e.g. `GET /signals/export?min_n=10` → gzip JSONL or parquet,
   one row per (drug, event) at the current quarter, after the three `hide` filters.
2. Fields Portfolio reads today: `drug`, `reported_drug`, `ingredient`, `event`, `n`, `eb05`,
   `trend`, `novel`. Add `n_unique` if it becomes available.
3. A header or field giving the data quarter and build date (as `X-…-Through` does elsewhere),
   so Portfolio can tell whether its cache is current.
4. `ingredient` normalised the same way `/signals` resolves names. Portfolio would then join on
   ingredient and drop the substring filtering. If that normalisation cannot be exposed, say
   so, and Portfolio keeps its own matching.

## Keep

- `/signals` per-drug behaviour unchanged. The Portfolio monitor checks and other clients
  depend on it.
- The same EB05 values and hiding rules. No new analytical filter in the export.

## Known issues found while building Portfolio (separate, low priority)

- `trend` comes back blank when `limit` ≥ 400 (measured: 300 keeps it, 400 drops it).
  Portfolio uses limit=300 because of this.
- `n` is the overlapping-window sum. There is no `n_unique`, so Portfolio cannot show
  distinct case counts and doesn't claim to.

## Verify (live)

- For tiopronin, ivosidenib and insulin glargine, the export rows filtered to that ingredient
  equal the `/signals` response above (same drug × event set, same `eb05`, `trend`, `novel`).
- The export's row count and data quarter are posted on this PR.
- Download time for the whole file is posted. The target is well under the current fill time.
- `/signals?drug=tzield` still returns 200 with an unchanged response.

## Out of scope

- Portfolio's switch to the export. This seat does it after the export is live.
- Ingredient pooling across routes (e.g. Nasacort picking up injection signals). That is
  Portfolio's open design question.
