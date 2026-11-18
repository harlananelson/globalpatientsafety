# Agent review — 2026-11-18

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Scope and what has changed since the last review

The weekly `agent-review-*.md` series lapsed after `2026-07-29`; this is the first
since. A lot shipped in the gap, and the July backlog is largely cleared — so none
of it is re-proposed:

- **July review #1 / #2 (dead `carbidopa`/`glp1` links on the AEMS page; "Signal
  methods" card stuck on *Coming soon*)** — **resolved.** `app/logic/tools.R:24-25`
  now has the row `live` → `/methods`; `app/static/aems.html` no longer links the
  draft ids (grep returns nothing); and `scripts/check_site_consistency.R:118-145`
  now fails CI if the card regresses or if `aems.html`/`methods.html` link a draft.
- **July review #3 (CLAUDE.md framed the retired Shiny app as production; CI only
  tested the Rhino app)** — **mostly resolved.** The Rhino app was archived to
  `archive/rhino-app/` (DECISION_LOG 2026-07-30), the Rhino/Cypress workflow is
  gone, `.github/workflows/site-checks.yml` now runs the static-site consistency
  check, and CLAUDE.md documents the static builder as production. The **one piece
  of that recommendation not done** — "give the production artifact a test" — is
  the subject of proposals #1 and #3 below, with new specifics.

The September `issues/*.md` files are faers-mobi/handshake feature tickets, not
portal work, and the November DECISION_LOG entries are the **Portfolio safety**
service (`/portfolio`, `scripts/gps_portfolio.py`), shipped 2026-11-17 and still
being filled/iterated. That new service is the context for proposal #1.

---

## 1. The two production Python services have 46 passing tests that CI never runs

**Severity:** correctness/maintainability on actively-iterated production code.
**Type:** CI coverage gap. **Highest leverage of the three.**

### Evidence

The site now fronts two Python HTTP services that are the live surfaces behind
`/pipeline` and `/portfolio` on the VPS:

- `scripts/gps_pipeline.py` — ClinicalTrials.gov pipeline analysis (`/pipeline`).
- `scripts/gps_portfolio.py` (1,193 lines) — Portfolio safety (`/portfolio`),
  added 2026-11-17 and still being changed (full cache fill started 2026-11-18,
  bulk-export ticket PR #119 open).

Both ship with real test suites in the same directory:

- `scripts/test_gps_portfolio.py` — 31 tests.
- `scripts/test_gps_pipeline.py` — 15 tests.

I ran them this session (stdlib `unittest`, no third-party deps):

```
$ cd scripts && python3 -m unittest test_gps_portfolio   # Ran 31 tests ... OK
$ cd scripts && python3 -m unittest test_gps_pipeline    # Ran 15 tests ... OK
```

All 46 pass. Crucially, they pin the subtle logic the DECISION_LOG records getting
wrong and then fixing by hand:

- `test_gps_portfolio.py:164 test_family_bucket_not_learned_from_one_brand_row`
  is the exact Ferrlecit/iron synonym-over-learning regression described in
  DECISION_LOG 2026-11-17 ("the synonym learner took `iron` from a single row
  reported as 'ferrlecit', which let every iron product … Regression test added").
- `test_gps_portfolio.py:269 test_small_n_pairs_not_shown` and `:276
  test_min_n_sent_to_faers` pin the `MIN_N = 10` decision (DECISION_LOG
  2026-11-17 "top signals need n ≥ 10").
- `:118 test_prefix_kept_so_zaltrap_is_not_eylea` pins the biologic-prefix rule
  (`ziv-aflibercept` must not merge Zaltrap with Eylea).

**But CI never runs any of it.** `.github/workflows/site-checks.yml` has exactly
one job (`static-site-consistency`) whose only step is
`Rscript --vanilla scripts/check_site_consistency.R`. There is no Python job, no
`pytest`/`unittest` invocation anywhere in `.github/`, and no `pyproject.toml`/
`pytest.ini`/`tox.ini` in the repo. So the author's own regression tests for the
most-churned production code are green on disk and ungated: a future edit to
`row_belongs` or the synonym learner can reintroduce the Ferrlecit bug and every
check stays green.

### Proposed change

Add a second job to `.github/workflows/site-checks.yml`:

```yaml
  python-service-tests:
    name: Python service tests
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.11" }
      - run: python -m unittest discover -s scripts -p 'test_*.py' -v
```

The suites are stdlib-only, so no dependency install is needed. (Optionally pin
the discovery to the two files if other `test_*.py` appear later.)

### Effort estimate

~15 minutes (one YAML job). Verified locally that discovery + both suites pass.

### Risk

Very low — CI-only, no runtime/deploy impact. Only risk is a path/working-dir
mismatch; the tests import `gps_portfolio`/`gps_pipeline` as siblings, so
`discover -s scripts` (run from repo root) resolves them, as the manual run above
confirms from within `scripts/`.

---

## 2. The weekly article cadence has been stalled for ~4 months — 3 finished drafts never shipped

**Severity:** user-facing content gap on the site's stated distinctive lane.
**Type:** stalled roadmap item with a concrete, mostly-mechanical next step.

### Evidence

`articles/proposals/ARTICLE_QUEUE.md` locks the editorial plan: "**one article
every week, published on MONDAY** (locked 2026-07-13). **First publish: Monday
2026-07-20.**" and lists a review backlog of four drafts delivered to the
reMarkable in July: *Carbidopa-Levodopa B6 Seizures · GLP-1 Alopecia · AAV Gene
Therapy Liver · Inside the AEMS Data*, to "Publish ~one per Monday as approved,
starting 2026-07-20."

Four months and ~17 Mondays later, only **one** of those four is live:

- `aems` — published (`app/logic/articles.R:21-24`, `status = "published"`,
  `app/static/aems.html` present).
- `aav_gene_therapy_liver` — still `"draft"` (`app/logic/articles.R:25-28`).
- `glp1_alopecia` — still `"draft"` (`app/logic/articles.R:29-32`).
- `carbidopa_levodopa_b6` — still `"draft"` (`app/logic/articles.R:33-36`).

The three drafts are **fully written** — the Quarto sources exist and are
substantial (`articles/aav-gene-therapy-liver.qmd` 12 KB,
`articles/glp1-alopecia.qmd` 13 KB, `articles/carbidopa-levodopa-b6-seizures.qmd`
17 KB). What is missing for each is only (a) the rendered `app/static/<id>.html`
(none of the three exists under `app/static/`) and (b) flipping `status` to
`published`. The builder already skips drafts and the consistency check already
forbids linking them, so nothing is broken — the pipeline has simply gone quiet.
No published article is dated later than `aems` (2026-07-14); the "Recent
articles" block on the homepage (`scripts/build_static_site.R:328`,
`head(recent_articles, 3)`) has shown the same three pieces since July.

This is exactly the "stalled roadmap item" the review is meant to catch, and it is
the site's *declared* value lane: ARTICLE_QUEUE.md's "Editorial direction —
methodology first (the site's distinctive lane)" says the durable value Harlan
adds is pharmacovigilance methodology. That lane has produced nothing new in a
third of a year despite three finished drafts.

### Proposed change

Report-only; the publish step is human-gated and needs local FAERS numbers
verified, so this is a prompt to Harlan, not an edit:

1. Confirm the reMarkable approval status of the three July drafts (the queue's
   gate: "every article is sent as a reMarkable Paper Pro PDF *before*
   publishing"). If any is already approved, the remaining work is mechanical:
   render its `.qmd` → `app/static/<id>.html`, flip the `articles.R` row to
   `published`, run `scripts/build_static_site.R`, deploy.
2. If the cadence is being retired or paused deliberately, say so in
   ARTICLE_QUEUE.md and DECISION_LOG so the next agent doesn't keep treating a
   dead "one per Monday" plan as current — right now the repo asserts an active
   weekly cadence that has not fired since July.

Either resolution is fine; the problem is the silent limbo.

### Effort estimate

- Per approved draft: ~20-30 min to render + register + rebuild (the content work
  is done).
- Documentation-only resolution (option 2): ~10 min.

### Risk

Low. Publishing touches only prose pages the builder already handles; the
consistency check guards against half-published state (a `published` row with no
HTML fails CI). The real cost of *not* acting is reputational — a methodology site
whose newest analysis is four months old.

---

## 3. The production builder's dead-link guard is advisory-only, and the builder is never run in CI

**Severity:** correctness guard that cannot actually fail. **Type:** small,
high-leverage fix.

### Evidence

`scripts/build_static_site.R` grew a `check_internal_links()` pass
(lines 525-568) — the durable fix recommended in the July review. But it can never
stop a bad build:

- On finding dead links it calls `warning()` and `cat("WARNING: …")`
  (`scripts/build_static_site.R:558-564`), not `stop()`/`quit(status = 1)`. A
  warning does not set a non-zero exit, so `Rscript scripts/build_static_site.R`
  succeeds even with dead internal links, and a `rsync` deploy right after ships
  them.
- The builder is **not run in CI at all.** `.github/workflows/site-checks.yml`
  runs only `scripts/check_site_consistency.R`, which does **not** build the site;
  its own comment says so ("CI checks registries against app/static and does not
  run the builder", `check_site_consistency.R:150-151`).
- The consistency check's link scan is narrow: it only reads `aems.html` and
  `methods.html` (`check_site_consistency.R:128` `standalone <- c("aems.html",
  "methods.html")`) and only for **draft-article** hrefs. The three published
  article bodies (`christine_cotton`, `covid_vaccine`, `shingles`) are never
  link-scanned by anything that can fail. A dead cross-reference inside a
  published Quarto article — e.g. a `href="/some_future_piece"` written ahead of
  publication, the precise failure mode of the July AEMS incident — ships silently.

So the guard that exists to prevent the exact class of bug the July review found is
cosmetic: it prints a warning into build output that no automated gate reads.

### Proposed change

Two small, independent steps:

1. **Make the guard bite.** In `check_internal_links()`
   (`scripts/build_static_site.R:558`), after collecting `broken`, `stop()` (or
   `quit(status = 1)`) instead of `warning()` when `length(broken) > 0`. Keep the
   human-readable listing. (If a soft mode is wanted for local iteration, gate the
   hard stop behind an env var that CI sets.)
2. **Run the builder in CI.** Add a job to `site-checks.yml` that installs the
   builder's handful of deps (`tibble`, `dplyr`, `stringr`) and runs
   `Rscript scripts/build_static_site.R`, so a dead link fails the PR. This also
   exercises `build_machine_access()` and would have caught any regression in the
   `/api`, `/llms.txt`, `/openapi.json` emission that `check_site_consistency.R`
   only verifies *after* a local build (it early-exits when `static_site/` is
   absent, `check_site_consistency.R:153-157` — i.e. in CI it skips those checks
   entirely today).

Step 1 is the higher-leverage half and is a one-line change; step 2 makes it
enforce on every push.

### Effort estimate

- Step 1 (`warning` → `stop`): ~5 minutes.
- Step 2 (builder CI job with R deps): ~45-60 minutes (dependency install is the
  only real cost; could share a step with proposal #1's job setup).

### Risk

Low. Step 1 turns a silent ship into a loud failure — the intended behavior; the
only risk is an existing latent dead link turning CI red, which is a disclosure,
not a regression (worth running the builder once locally first to confirm the
tree is clean). Step 2 is additive CI.

---

## Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Run the 46 passing `scripts/test_gps_*.py` unittest suites in CI | CI coverage / correctness | ~15 min | Very low |
| 2 | Unstick (or formally retire) the weekly article cadence — 3 finished July drafts never published | Content / stalled roadmap | ~20-30 min per draft, or ~10 min to document | Low |
| 3 | Make `check_internal_links()` fail the build (`warning`→`stop`) and run the builder in CI | Correctness guard / small fix | ~5-60 min | Low |
