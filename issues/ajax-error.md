# Triage: aers-mobi DataTables Ajax error

## Context

Repo: `aers-mobi` (Rhino Shiny app, FAERS + MAUDE drug/device safety surveillance).
Symptom: User-facing modal popup reads:

> DataTables warning: table id=DataTables_Table_1 - Ajax error. For more information about this error, please see http://datatables.net/tn/7

This is the **generic** DataTables message that fires whenever the server-side Ajax endpoint feeding the table returns non-200, malformed JSON, or an R error during rendering. The real cause is server-side and is **not visible in the browser**. Do not stop at the modal text.

Visible context when the error fired:
- Substance view was rendered (Prednisone row visible, EBGM with 95% CI forest plot drew partially).
- "Showing top 2,000 of 995,681 flagged pairs" indicates the table is paginated server-side, so the Ajax handler is being hit on every redraw / filter change.
- A second message in the UI: "No label cached for cloruro de sodio usp — can't determine if this signal is known." This is informational, not the failure, but worth noting in case the same code path is involved.

## Prime suspect

Most recent commit on `main` (3 days ago):

> Lift class-effect filter when user has an active se…

Timing matches. Class-effect filtering is exactly the kind of reactive that would feed the DT server-side endpoint, and "lifting" a filter is the kind of refactor that introduces NULL inputs, unmatched factor levels, or stale column references.

Treat this commit as the leading hypothesis, not a conclusion. Disconfirm or confirm before fixing.

## What I want you to do

### 1. Reproduce locally

- Check out `main`.
- `renv::restore()`.
- Launch the app (`rhino::app()` or `shiny::runApp("app")` depending on Rhino convention used here).
- Reproduce the failure on the substance view with Prednisone selected and the same filter state shown in the screenshots (class-effect filter active).
- Capture the **R-side error** from the console or `shiny::runApp(launch.browser = FALSE)` log. That is the artifact we need; the DataTables modal is not.

If you cannot reproduce locally because the FAERS data isn't checked in, say so explicitly and stop — do not patch blind. Ask me where the data lives.

### 2. Localize

- `git log --oneline -20` and identify the "Lift class-effect filter" commit SHA.
- `git show <SHA> -- app/` to see the diff.
- Identify which reactive(s) feed the DataTable. Look for `DT::renderDT`, `DT::dataTableProxy`, `DT::replaceData`, or `reactable` (depending on which is used).
- Trace the data path: filter inputs → reactive → DT server function. Note where the lifted filter sits in that chain.

### 3. Disconfirm the prime suspect

Before fixing, run:

- `git stash` any local changes, then `git revert --no-commit <SHA>` for the suspect commit on a throwaway branch.
- Reproduce with the revert applied.
- If the error disappears → suspect confirmed.
- If the error persists → suspect is not the cause. Widen the search to the previous 2–3 commits on `app/` and to any changes in `renv.lock` (a silently bumped DT or htmlwidgets version can also produce this).

### 4. Diagnose

Likely failure modes, in rough order of probability for this kind of refactor:

1. Reactive returns `NULL` or zero-row data frame when the lifted filter is in a particular state, and downstream code calls `DT::datatable()` on it without guarding.
2. Column rename or removal in the lifted filter that downstream `columnDefs` / `colnames` / formatters still reference.
3. `subset()` or `dplyr::filter()` on a column that no longer exists in the post-lift data shape.
4. `factor` level mismatch after the lift — `droplevels()` missing or extra.
5. Server-side processing pagination (`server = TRUE`) returning more/fewer columns than the client schema expects.
6. Encoding issue with non-ASCII drug names ("cloruro de sodio usp", "Pantoea agglomerans") if the lift changed how strings are matched or joined. The "No label cached" message hints at this path.

For each candidate, state how you'd confirm it from the code and the captured error message. Don't guess — match the actual error to the candidate.

### 5. Fix

- Smallest diff that addresses the actual root cause.
- Add a guard at the DT-feeding reactive: if input data frame is NULL or zero rows, return an empty data frame with the expected columns rather than letting the error propagate to DT.
- Add a `tryCatch` around the server-side rendering only if the underlying bug is also fixed — do not paper over with a tryCatch alone.

### 6. Regression test

- Add a `tests/testthat` (or whatever test harness this repo uses — check `tests/`) test that exercises the filter state that triggered the failure.
- If the repo uses `shinytest2`, add a snapshot test that activates the class-effect filter on the substance view.

### 7. Report back

Produce a short writeup in this exact structure:

```
ROOT CAUSE: <one sentence>
EVIDENCE: <the actual R error message + file:line>
SUSPECT COMMIT CONFIRMED: <yes / no, with revert evidence>
FIX: <files changed, summary of change>
TEST ADDED: <path to test, what state it covers>
RESIDUAL RISK: <anything you patched around rather than fixed, or anything you couldn't reproduce>
```

## Constraints

- Do not commit or push. Leave the fix on a branch named `fix/datatables-ajax-class-effect-filter` and stop.
- Do not bump package versions in `renv.lock` unless the root cause is a package version, in which case flag it explicitly in RESIDUAL RISK.
- Do not add a blanket `tryCatch` that swallows the error and shows a friendly message without also fixing the underlying bug. That is the wrong direction here — the table is the product.
- If you cannot reproduce locally, stop and tell me. Don't speculate-fix.
- If the suspect commit is not the cause, say so plainly. Don't anchor.

## Useful starting commands

```bash
git log --oneline -20
git log --oneline -- app/ | head -20
git show $(git log --format=%H --grep="Lift class-effect" -1) -- app/
grep -rn "renderDT\|dataTableProxy\|replaceData" app/
grep -rn "class.effect\|class_effect\|classEffect" app/
```