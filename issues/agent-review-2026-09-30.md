# Agent review — 2026-09-30

Weekly reflection on globalpatientsafety.com (the static clearing-house site + its
registries and builder). Report-only; no files other than this one are touched.

Scope note: most `issues/*.md` from 2026-09-12…-17 are **faers-mobi** feature specs
(event briefs, `/signals` API, MCP, PDF export), not this repo — they are out of scope
here. The last agent-review for *this* repo is `agent-review-2026-07-29.md` (nine weeks
ago), and the site has moved on since: the "Signal methods" card is now `live`
(`app/logic/tools.R`), the Rhino app is archived, and the AEMS dead-links flagged on
2026-07-29 are resolved (only `aems.html`→`/christine_cotton`,`/methods` and
`methods.html`→`/aems` remain, all valid). The three items below are current and not
re-proposals.

---

## 1. The flagship "Signal & Noise" series advertises three *finished* installments as "In review" — they've sat approval-gated and unpublished for ~10 weeks

### Evidence

`/methods` ("Signal & Noise") is **live** and in the top nav (`app/logic/tools.R`,
`scripts/build_static_site.R:79`). Its published installments table
(`articles/methods.qmd:51–59`) tells every visitor:

| Row (methods.qmd) | Worked example | Status shown |
|---|---|---|
| :55 | GLP-1 → hair loss (alopecia) | **In review** |
| :56 | Carbidopa/levodopa → B6 seizures; AAV gene therapy → liver | **In review** |

Those three "in review" pieces are already **written in full** and only need rendering:

- `articles/glp1-alopecia.qmd` — 243 lines, complete
- `articles/carbidopa-levodopa-b6-seizures.qmd` — 293 lines, complete
- `articles/aav-gene-therapy-liver.qmd` — 202 lines, complete

All three are still `status = "draft"` with no `app/static/<id>.html`, so the builder
skips them (`app/logic/articles.R`; ids `glp1_alopecia`, `carbidopa_levodopa_b6`,
`aav_gene_therapy_liver`).

They are **not** blocked on technical work. `DECISION_LOG.md:1807–1819` records the real
gate: publishing is gated on the owner's per-article approval, read on the reMarkable
device first, with "first publish Monday 2026-07-20." The mechanics were also settled
then (`DECISION_LOG.md:1744–1750`: render `.qmd` → `app/static/<id>.html`, flip the
tribble row to `published`). The **fourth** article from that same approval batch — AEMS
(`DECISION_LOG.md:1811` lists "carbidopa, GLP-1, AAV, AEMS" as the four approval copies)
— cleared the gate and is now the `published`, `featured` splash article. The other three
never cleared it. As of 2026-09-30 that is ~10 weeks of a live series page promising
work that is done.

### Proposed change

This is **not** a request to bypass the owner's approval gate — it's to surface a stalled
decision and stop the live page from making an open-ended promise. Pick one:

- **(a) Unblock the gate (preferred, at least for `glp1_alopecia`** — the series' natural
  second piece after AEMS): owner approves from the device, then render each `.qmd` to
  `app/static/<id>.html`, flip its `articles.R` row to `published`, rebuild. The methods
  table rows then flip from "In review" to live `/glp1_alopecia` etc. links (the
  consistency check already forbids linking a *draft* id from `methods.html`, so the
  status flip and the link must land together).
- **(b) If approval is genuinely deferred:** soften `articles/methods.qmd:55–56` from "In
  review" to "Planned," so the live page isn't advertising indefinitely-pending pieces.

### Effort estimate

Rendering is minutes per article **where the FAERS signals parquet is reachable** — each
draft's `params$data_path` points at `/srv/shiny-server/.../signals_faers.parquet` with a
local-workstation fallback (`aav-gene-therapy-liver.qmd:18`). The dominant cost is the
owner's approval read, which is a human step, not engineering. Fallback (b) is a 2-line
table edit.

### Risk

Low. Path (a) respects the existing approval gate rather than removing it. The one real
dependency to name honestly: **the parquet is not in this checkout** (`data/` holds only
CSVs — `top1000_signals.csv`, `signal_triage.csv`, …), so rendering must happen on the
render host, then the resulting HTML is committed. Path (b) has no data dependency.

---

## 2. The dead-internal-link guard runs only in the builder, only *warns* (despite its own comment claiming it "fails hard"), and never runs in CI — so the 2026-07-29-class regression ships green

### Evidence

CI runs exactly one check (`.github/workflows/site-checks.yml`):
`Rscript --vanilla scripts/check_site_consistency.R`. That script validates
registry↔HTML **existence** and guards `aems.html`/`methods.html` against draft hrefs
(`check_site_consistency.R:127–145`) — but it does **not** scan the other published
article bodies (`christine_cotton`, `shingles`, `covid_vaccine`) for dead same-site links.

The only thing that scans built HTML for dead internal links is
`build_static_site.R:446` `check_internal_links()`. Two problems:

1. Its header comment says *"Fails hard on zero targets that look like article/standalone
   slugs"* (`build_static_site.R:444–445`), but the body only calls `warning()` and prints
   a `WARNING:` line (`:479–485`) — it never `quit(status = 1)`. The build "succeeds" with
   broken links.
2. The builder is **not invoked in CI at all** (the workflow sets up base R only and runs
   the consistency script), so even that warning is never seen by a gate.

This exact bug class has shipped before: `issues/agent-review-2026-07-29.md` #1 was live
dead internal links on the AEMS page. There is currently no live dead link (verified:
only the three valid cross-links above), so this is preventing a *recurrence*, not fixing
a live break.

### Proposed change

Port the internal-link scan into the base-R script that already runs in CI. Concretely,
in `check_site_consistency.R` after the existing checks: for every shipped
`app/static/<published id>.html` (and the standalone pages), extract `href="/slug"` /
`href="./slug"` same-site slugs and `fail()` if any slug is neither a published id, a
standalone id, `index`/`articles`, nor a pure `#anchor`. That reuses the base-R-only
constraint the CI job depends on. Separately, align `check_internal_links()` in the
builder with its own comment — `quit(status = 1)` on broken links — so a manual build also
fails loudly.

### Effort estimate

Small, ~1–2 hours: ~30 lines of base R plus a test run of `check_site_consistency.R`
against the current tree (should stay green) and against a deliberately-broken href
(should fail).

### Risk

Low. Keep the scan base-R (`readLines`/`regmatches`) so the CI job needs no new deps
(don't try to run the full builder in CI — it pulls `tibble`/`dplyr`/`stringr`, which the
current base-R-only job avoids). Only failure mode is a false positive on an unusual href
shape; scope the regex to single-segment slugs, exactly as the builder already does.

---

## 3. Two published articles' sources live at the repo root under mismatched names, beside a stray 4.8 MB rendered HTML — the source-of-truth for `covid_vaccine`/`shingles` is ambiguous and the repo carries avoidable bloat

### Evidence

CLAUDE.md documents one article path: Quarto `articles/*.qmd` → `app/static/<id>.html`,
with the `id` matching the HTML stem ("Adding a published article"). Every source obeys
this **except** the two oldest published articles:

- Published id `covid_vaccine` (`app/logic/articles.R`) → `app/static/covid_vaccine.html`,
  but its source is `./covid_vaccine_vaers_analysis.qmd` at the **repo root** (19 KB) — not
  `articles/covid_vaccine.qmd`. There is no covid source under `articles/`.
- Published id `shingles` → `app/static/shingles.html`, but its source is
  `./shingles_vaccine_analysis.qmd` at the root (17.9 KB). `articles/shingles.md` exists
  but is only a **prompt stub** ("Breaking topic… Prompt: …"), not the article source.
- `./covid_vaccine_vaers_analysis.html` (**4.8 MB**) is committed at the repo root and is
  **not** the file the builder ships (the builder reads `app/static/covid_vaccine.html`).
  It's a stray full render sitting in git history forever.

Net effect: someone asked to update the COVID or shingles article has to guess which of
three files (`app/static/*.html`, root `*_analysis.qmd`, or `articles/shingles.md`) is
canonical, and `git clone` pays 4.8 MB for an artifact nothing reads.

### Proposed change

Normalise to the documented layout: `git mv covid_vaccine_vaers_analysis.qmd
articles/covid_vaccine.qmd` and `git mv shingles_vaccine_analysis.qmd
articles/shingles.qmd` (id-matched sources), fold the `articles/shingles.md` prompt into
the qmd or drop it, and `git rm` the root `covid_vaccine_vaers_analysis.html` (the shipped
copy in `app/static/` is untouched). Optionally extend `check_site_consistency.R` to
assert every published id has a matching `articles/<id>.qmd`, so this can't drift again.

### Effort estimate

~30–60 min: the moves/deletes, a rebuild to confirm `static_site/` is byte-identical
(the builder never reads the root files, so output is unchanged), and a `git log`
sanity-check that nothing else references the moved paths.

### Risk

Low, and **zero production/deploy impact** — the builder reads `app/static/`, which this
proposal does not touch. Pure source hygiene. Only caution: confirm no script or
`DEPLOY-*.md`/qmd references the old root paths before removing them (grep first).

---

## Summary ranking

| # | Proposal | Type | Effort | Why now |
|---|---|---|---|---|
| 1 | Publish (or re-label) the 3 finished "Signal & Noise" installments | Stalled roadmap / user-facing | Human approval + minutes to render | Live series page has promised done work for ~10 weeks |
| 2 | Move the dead-link guard into CI and make it fail, not warn | Correctness / CI gap | ~1–2 h | Same bug class already shipped once (2026-07-29) |
| 3 | Normalise root-level article sources; drop the 4.8 MB stray HTML | Consistency / hygiene | ~30–60 min | Ambiguous source-of-truth + clone bloat |

All three cite specific files/lines and none duplicate the 2026-07-08…-29 reviews (whose
Christine-Cotton dead-link, "Signal methods = Coming soon," and retired-Rhino-CI items are
now resolved; the `REDESIGN_FRONTEND.md` three-audience landing noted on 2026-07-22 remains
a genuine but larger, separately-tracked item, not re-scoped here).
