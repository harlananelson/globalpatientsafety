# Tzield search over-match and Novel=?

Live repro on faers.mobi, 2026-09-12. Implement on the Ubuntu box in `/projects/faers-mobi/` (sibling project; not this repo). Do not implement SEARCH_REDESIGN.md wholesale.

## Bug 1 — search over-match

Global search does not isolate the queried drug. Results are ranked by Adj EB05 across a greedy expansion, so unrelated high-EB05 drugs bury the query.

- Search `tzield` → `4,020 pairs ... matched 13 drug names, 5 substances (83 drugs) (showing top 2000)`.
- First rows: ziprasidone, tildrakizumab. Not Tzield/teplizumab.
- Drug-column filter `tzield`: 0 rows. `teplizumab`: 0 rows. `ziprasidone`: 43 rows.
- Search `teplizumab` → `15,030 pairs ... matched 18 drug names, 11 substances`.
- Isolated `tzield (teplizumab)` rows exist (rash 314, pyrexia 218, lymphocyte decreased 103, CRS 50, lymphopenia 48). Data is there; search/ranking is wrong.

Likely `head(2000)` / `SPLASH_SIZE` plus synonym/DiAna/ATC expansion in `faers-mobi/app/view/signal_timeline.R`.

**Wanted:** exact/prefix brand+generic first; matched names as chips; do not bury the queried drug. `?q=teplizumab` if cheap.

## Bug 2 — Novel=?

On isolated Tzield/teplizumab rows, Novel is `?` (label undetermined). Approval year / years-on-market blank. Tzield has an FDA label. Fix openFDA/label cache so teplizumab/Tzield is Known or Novel. Do not fake labels.

## Done when

- Search `tzield` or `teplizumab` surfaces those rows first, not ziprasidone.
- Novel is Known or Novel for teplizumab/Tzield, or a documented skip if openFDA has no label.
- Small change. Deploy to faers.mobi if that is how you ship.
