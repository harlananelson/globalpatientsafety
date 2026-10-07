# Agent review — 2026-10-07

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Scope and what's already been fixed since the last reviews

Production is the **static site** built by `scripts/build_static_site.R` and
rsync'd to nginx; the Rhino/Shiny portal is archived (`archive/rhino-app/`). The
scheduled prompt still describes this repo as a "Rhino/Shiny" portal — that
framing is stale; this review treats the static site as the product, per
`CLAUDE.md` and the `build_static_site.R` header.

I checked the four prior `issues/agent-review-2026-07-*.md` files and will **not**
re-propose their items, because the code shows they are resolved:

- **2026-07-29 #1 (dead AEMS links to `carbidopa_levodopa_b6` / `glp1_alopecia`)**
  — fixed. `app/static/aems.html` now links only to `/christine_cotton` and
  `/methods` (both live), and a draft-href guard was added to
  `check_site_consistency.R:127-145`.
- **2026-07-29 #2 ("Signal methods" card said "Coming soon")** — fixed.
  `app/logic/tools.R:24-25` is now `"Signal methods", "live", "/methods"`.
- **2026-07-29 #3 (reconcile CLAUDE.md + CI with static-site reality)** — mostly
  done. `CLAUDE.md` now documents the static build as production;
  `.github/workflows/site-checks.yml` + `scripts/check_site_consistency.R` exist.
  The *one open half* — CI never actually builds or link-checks the deployed
  artifact — is picked up below as proposal #1, with new, specific reasoning.

The novelty/search roadmaps (`NOVELTY_FILTER_ROADMAP.md`, `SEARCH_REDESIGN.md`)
and almost all of the September `issues/*.md` + recent `git log` target the
sibling `faers-mobi` app and its monitor tooling, not this portal, so they are
out of scope for a globalpatientsafety.com reflection.

---

## 1. The deployed static site is never built or link-checked in CI, and the builder's own link check can't fail a build

**Type:** correctness / CI coverage. **Severity:** a dead public link can ship
with zero gate. This is the still-open half of the 2026-07-29 #3 proposal, now
with specifics that didn't exist when that review was written.

### Evidence

Three gaps compound:

1. **CI builds nothing.** `.github/workflows/site-checks.yml` has a single job
   whose only step runs `Rscript --vanilla scripts/check_site_consistency.R`. It
   never runs `scripts/build_static_site.R`, so `static_site/` — the artifact
   actually rsync'd to nginx — is never produced or validated in CI.
2. **The builder's link check is non-fatal.** `build_static_site.R:446-489`
   (`check_internal_links`) scans built HTML for dead same-site slugs, but on a
   hit it calls `warning(...)` (line 480-485) and prints `WARNING:` — it never
   `stop()`s. `Rscript` exits 0 on a warning, so even a *local* build succeeds
   with dead links, and the deploy step right after it (`rsync`, lines 500-502)
   has no reason not to run. The one check that would catch a dead link can't
   stop a deploy.
3. **The CI guard that exists covers 2 of ~8 pages.** The draft-href scan in
   `check_site_consistency.R:127-145` only iterates
   `standalone <- c("aems.html", "methods.html")` (line 128). It does **not**
   scan the published article pages (`christine_cotton.html`, `shingles.html`,
   `covid_vaccine.html`) or the generated `index.html` / `articles.html`. It also
   only flags links to *draft* ids, not links to ids that don't exist at all.

Concrete failure this allows: a future published Quarto article that cross-links
to `./aav_gene_therapy_liver` (still `draft` in `app/logic/articles.R:25-28`, no
rendered HTML) would produce a 404 for every visitor. The builder would `warning`
but exit 0; `check_site_consistency.R` would not scan that published page; CI
would stay green; the page would deploy. This is exactly the class of regression
the 2026-07-29 #1 fix caught manually for the AEMS page — but only for AEMS.

### Proposed change

Pick one (both are small):

- **Preferred — validate the real artifact in CI.** Add a second job/step to
  `site-checks.yml` that runs `Rscript scripts/build_static_site.R` and fails on
  dead links. The cleanest way to make it fail: have `check_internal_links()`
  honor an env var (e.g. `GPS_STRICT_LINKS=1` → `stop()` instead of `warning()`)
  and set it in CI. This also catches registry→HTML drift end-to-end, not just
  the two hand-listed standalone files. (Needs R + the build deps in the runner;
  the existing job already sets up R 4.4.)
- **Cheaper, no new runner deps.** Extend the base-R `check_site_consistency.R`
  draft-href scan at line 128 from the 2-file list to **every**
  `app/static/*.html`, and additionally flag same-site `href`s whose target id is
  neither a published article nor a standalone id nor `index`/`articles` (port
  the slug logic from `build_static_site.R:462-477`). Keeps CI base-R-only.

### Effort estimate

~45 min for the strict-link env var + CI step; ~30 min for the base-R extension.

### Risk

Low. Both are build-/CI-time only, no runtime or deploy-path change. The strict
flag defaults off, so local builds behave as today unless CI opts in.

---

## 2. The DuMouchel 1999 citation in the site footer links to the wrong paper

**Type:** user-facing correctness / credibility. **Severity:** a wrong canonical
citation on the site's two primary hub pages, for a site whose entire pitch is
methodological rigor.

### Evidence

`build_static_site.R:181-184` (the `site_foot` constant) renders:

```
<a href="https://doi.org/10.1177/009286159903300105" ...>GPS framework (DuMouchel 1999)</a>
```

- `site_foot` is emitted by `build_index()` (`build_static_site.R:336`) and
  `build_articles_index()` (line 362), so this link is on the deployed
  **homepage** (`index.html`) and **articles index** (`articles.html`).
- The DOI `10.1177/009286159903300105` uses the `10.1177` (SAGE) prefix, and the
  suffix encodes ISSN `0092-8615` = the *Drug Information Journal*, 1999. It does
  **not** resolve to DuMouchel's paper.
- DuMouchel's actual GPS/EBGM paper is *"Bayesian Data Mining in Large Frequency
  Tables, with an Application to the FDA Spontaneous Reporting System,"* **The
  American Statistician 53(3):177-190 (1999)**, DOI **`10.2307/2686093`** (JSTOR
  stable; the Taylor & Francis DOI `10.1080/00031305.1999.10474456` also
  resolves). Confirmed via web lookup during this review.

So the footer credits "DuMouchel 1999" but the hyperlink sends a reader to a
different 1999 journal entry — the opposite of the trust signal it's meant to be.
The same DuMouchel framing appears in the About section's methods list
(`build_static_site.R:326`), which is correct in prose but undercut by the dead-end
footer DOI alongside it.

### Proposed change

In `build_static_site.R:182`, replace the DOI with `10.2307/2686093` (or the
Taylor & Francis DOI). One-line edit; rebuild regenerates `index.html` and
`articles.html`. Optionally make the footer link text name the venue
("DuMouchel 1999, *The American Statistician*") so a reader can sanity-check the
target.

### Effort estimate

~10 min (single string + rebuild). Worth a 30-second click-through on the
rebuilt pages to confirm the DOI resolves to the American Statistician article.

### Risk

Very low. Pure content fix; no structural or build-logic change.

---

## 3. `REDESIGN_FRONTEND.md` still specifies the retired Rhino app as the build target — reconcile or mark it superseded

**Type:** stalled roadmap item / doc consistency; a trap for the next contributor
(human or agent). This is the same class of win as the 2026-07-29 #3 CLAUDE.md
reconciliation, but for the one strategy doc that reconciliation left untouched.

### Evidence

`REDESIGN_FRONTEND.md` (dated 2026-05-03) is the site's documented product
direction: a three-audience structure (`/for/patients`, `/for/researchers`,
`/for/pharma`, lines 18-29) and a patient medication-checker tool (section 3).
Two problems make it a live trap rather than a plan:

- **It targets architecture that no longer exists.** Section 8 says the patient
  tool "can be built as a new tab in the globalpatientsafety Rhino app"
  (`REDESIGN_FRONTEND.md:282`) and section 2 (lines 18-20) assumes server-rendered
  landing pages. The Rhino app is archived (`archive/rhino-app/`, `CLAUDE.md`
  overview); the production surface is a static nginx site. A contributor who
  picks this up would start in a retired codebase.
- **None of Phase 0 exists, and the gap is invisible.** The deployed homepage is
  still the single generic page built by `build_index()`
  (`build_static_site.R:249-340`) — one hero, a tools grid, recent articles. There
  are no `/for/*` pages and no medication-input widget, yet the doc says Phase 0
  is "Now (this week)" (`REDESIGN_FRONTEND.md:234-240`). Five months on, the
  "this week" plan is both unbuilt and un-updated, so its status is unknowable
  from the repo.

Because this is the only remaining doc that still presents the Rhino app as the
product, it's the most likely place for the next agent to go wrong.

### Proposed change

A small, decision-first doc reconciliation (no code):

1. Add a status banner at the top of `REDESIGN_FRONTEND.md` stating the current
   architecture (static site + separate Shiny subdomains) and the doc's real
   status (actively pursued / parked / superseded).
2. Re-point the patient-tool implementation path (section 8) away from the
   retired Rhino app toward the pattern the other tools already use — a standalone
   Shiny app on a subdomain (e.g. `check.globalpatientsafety.com`), linked from
   the static site as a tool card in `app/logic/tools.R` — or explicitly mark the
   three-audience redesign superseded if it's no longer the plan.

If the three-audience split *is* still wanted, the smallest shippable slice on the
current static stack is to add `/for/researchers` as a new standalone page (a row
in `STANDALONE_PAGES`, `build_static_site.R:77-81`, + a rendered HTML) — a concrete
next step that fits the builder as-is, unlike the Rhino-tab path the doc names.

### Effort estimate

~30-45 min for the doc reconciliation (banner + section-8 rewrite). The
`/for/researchers` static page, if pursued, is ~1-2 hr on top.

### Risk

Low. Doc-only unless the optional static page is built, which is additive and
guarded by the proposal-#1 link checks.

---

## Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Build + link-check the static site in CI; make the builder's link check able to fail | Correctness / CI | ~30-45 min | Low |
| 2 | Fix the DuMouchel 1999 footer DOI (`10.1177/...` → `10.2307/2686093`) on homepage + articles index | User-facing correctness | ~10 min | Very low |
| 3 | Reconcile `REDESIGN_FRONTEND.md` with the static-site architecture (drop the retired Rhino-app path) | Doc consistency / stalled roadmap | ~30-45 min | Low |
