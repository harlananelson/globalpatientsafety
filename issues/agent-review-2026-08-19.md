# Agent review — 2026-08-19

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed and no file other than this one is modified.

## Scope and what has changed since prior reviews

Production is the static site built by `scripts/build_static_site.R` and rsync'd to
nginx; the interactive Rhino/Shiny app was archived to `archive/rhino-app/` on
2026-07-30. That archival **resolved the bulk of the four prior reviews** — I
verified this against the current tree rather than re-proposing:

- **Signal-methods card** (proposed 07-08, 07-15, 07-22, 07-29): now `"live", "/methods"`
  in `app/logic/tools.R:24-25`. Fixed.
- **Dead AEMS → draft-article links** (proposed 07-29): `app/static/aems.html` no
  longer links to any draft id; its only same-site links are `/christine_cotton`
  and `/methods`, both live (verified by grep). Fixed.
- **Build-time link check** (proposed 07-29): a `check_internal_links()` was added
  to `build_static_site.R:442-489` — but it is toothless and never runs in CI. That
  is Proposal 1 below, with materially new reasoning.
- **Retired-app dead buttons / CLAUDE.md drift / Rhino CI** (proposed 07-08→07-29):
  moot — the app is archived, CLAUDE.md now documents the static build as
  production, and `.github/workflows/site-checks.yml` replaced the Rhino CI with a
  base-R consistency check.

Sibling-repo roadmaps (`SEARCH_REDESIGN.md`, `NOVELTY_FILTER_ROADMAP.md`) target
`faers-mobi` / `aers-mobi` and cannot be verified from this repo — not proposed.
The three remaining `draft` articles (`aav_gene_therapy_liver`, `glp1_alopecia`,
`carbidopa_levodopa_b6`) are a deliberately human-gated reMarkable-approval backlog
(`articles/proposals/ARTICLE_QUEUE.md`), not a bug — not proposed.

---

## 1. Nothing actually fails when the production site ships a dead internal link

**Severity:** correctness / release-safety on the only deployed surface. Highest
priority — it re-opens the exact class of bug (dead links on a live page) that
07-29 tried to close.

### Evidence

The site has *two* link guards and **neither can stop a dead internal link from
shipping**:

1. **The comprehensive check only warns — and contradicts its own comment.**
   `scripts/build_static_site.R:442-445` documents the check as:
   > "Scan built HTML for same-site hrefs … **Fails hard** on zero targets that look
   > like article/standalone slugs."

   But the function body never fails. On a broken link it calls
   `warning(...)` (`:480-484`) and `cat("WARNING: …")` (`:485`), then the run
   proceeds to `cat("\nDone. Deploy with: …")` (`:500`). In a non-interactive
   `Rscript`, `warning()` neither stops execution nor sets a non-zero exit code, so
   `build_static_site.R` exits 0 with a dead link in `static_site/`, and the printed
   next step is "rsync to the VPS." The comment even contradicts itself — "warn
   when the target file is missing" vs "Fails hard."

2. **CI never runs the build, so that check never executes in CI at all.**
   `.github/workflows/site-checks.yml` runs exactly one command:
   `Rscript --vanilla scripts/check_site_consistency.R`. It never runs
   `build_static_site.R` (deliberately — CI is base-R only, the builder needs
   `dplyr`/`stringr`). So `check_internal_links()` fires only if a human runs the
   build locally and happens to read the warning.

3. **The base-R CI check does not resolve internal links.**
   `scripts/check_site_consistency.R` verifies that every published article has an
   `app/static/<id>.html` (`:75-82`) and scans `aems.html`/`methods.html` for
   *draft* hrefs (`:127-145`) — but it never checks that the same-site links **inside**
   the shipped pages resolve to a real page. A misspelled or unpublished link (e.g.
   `href="/christine_coton"` or a link to an article later set back to `draft`)
   passes CI green and 404s in production.

No live link is broken *today* (all three current same-site links resolve), so this
is a latent gap, not an active outage — but it is precisely the gap that let the
07-29 AEMS dead links ship, and the guard added in response cannot catch a repeat.

### Proposed change

Make dead-internal-link detection a hard CI failure. Cheapest durable path, since
CI runs only base R:

- Generalize the draft-href scan in `check_site_consistency.R` into a full
  resolver: enumerate the set of buildable slugs (published ids + `STANDALONE_PAGES`
  ids + `index`/`articles`), scan every `app/static/*.html` for same-site
  single-segment hrefs (`href="/slug"`, `href="./slug"`, with or without `.html`),
  and `fail()` on any slug not in the buildable set. This subsumes the existing
  draft-only check.
- Separately, fix `build_static_site.R:442-489` so it matches its comment: collect
  `broken` and `quit(status = 1)` (or `stop()`) instead of `warning()`, so a local
  build refuses to print the deploy line with a dead link present.

### Effort estimate

~1 hr. The resolver is ~25 lines of base R modeled on the existing needle scan
(`:127-145`); the builder change is a two-line swap (`warning` → collect + `quit`).

### Risk

Low, CI/build-time only. It may surface currently-latent broken links on first run —
that is the intended outcome. Watch one false-positive source: the scan must ignore
anchors (`/#about`), external URLs, and asset paths, exactly as
`check_internal_links()` already does (`build_static_site.R:468-472`).

---

## 2. The homepage shows the featured article (AEMS) twice — as "Start here" and again in "Recent articles"

**Severity:** user-facing polish on the landing page; small, high-leverage.

### Evidence

`build_index()` builds two article blocks from the same `published` set:

- **Featured card:** `featured <- published |> filter(featured == TRUE) |> slice(1)`
  (`scripts/build_static_site.R:72`) → `aems` (the only `featured = TRUE` row,
  `app/logic/articles.R:24`). Rendered as the "★ Start here — how we read the data"
  card (`:252-270`).
- **Recent articles:** `recent_articles <- published |> arrange(desc(date)) |> head(3)`
  (`:277`). Published rows by date desc are `aems` (2026-07-14), `christine_cotton`
  (2026-06-13), `shingles` (2026-05-12). So `aems` is the **first** recent card too
  (`:302-310`).

Net: a first-time visitor sees the AEMS primer as the big featured card and then
immediately again as the top-left of the three-card "Recent articles" row. The
"Recent" strip effectively shows only two *new* things while spending a slot on the
item already featured directly above it.

### Proposed change

Exclude the featured id from the recent list in `build_index()`:

```r
recent_articles <- published |>
  filter(id != featured$id[1]) |>
  arrange(desc(date)) |>
  head(3)
```

(Guard for the `nrow(featured) == 0` case, where `featured$id[1]` is absent — keep
the current unfiltered list then.) This fills the third recent slot with
`covid_vaccine` and removes the duplication.

### Effort estimate

~10 min (one `filter` + a rebuild to eyeball the homepage).

### Risk

Very low, presentation-only. Confirm the recent strip still renders three cards
after the exclusion (there are four published articles, so it will).

---

## 3. `REDESIGN_FRONTEND.md` is a 3.5-month-old "Draft" spec that the shipped site has already diverged from — decide revive-or-close

**Severity:** doc/direction consistency; a standing trap for the next contributor
or agent that reads the specs to learn "the plan." Favors the "stalled roadmap item
with a clear next step" lane.

### Evidence

`REDESIGN_FRONTEND.md` is still marked **"Status: Draft — 2026-05-03"** (`:3`) and
specifies a three-audience architecture — `/` (patients), `/for/researchers`,
`/for/pharma` — with the tagline **"Know before it becomes a headline."** (`:12`)
and "Patient Landing Page (Build First)" as the first deliverable (`:32`).

None of that shipped, and the project has since committed to a *different*
direction:

- The live site is a **single** landing page. `build_static_site.R` emits only
  `/`, `/articles`, article pages, and the `/methods` + `/aems` standalone pages —
  no `/for/*` routes anywhere in `STANDALONE_PAGES` (`:77-81`) or `site_nav()`
  (`:138-176`).
- The hero still carries the **old** tagline, not the spec's:
  `build_static_site.R:286` and `:292` both read *"Open tools for pharmacovigilance
  signal detection and clinical research acceleration."* — directly contradicting
  `REDESIGN_FRONTEND.md:12`.
- `articles/proposals/ARTICLE_QUEUE.md` ("Editorial direction — methodology first",
  cadence "locked 2026-07-13") documents a decisive pivot to a **methodology-first,
  one-article-per-week** strategy anchored on the "Reading FDA Adverse-Event Data"
  series and the `/methods` page — a different product thesis from the three-audience
  patient-first funnel in the redesign spec.

So the repo now ships a methods-series content site while carrying a live "Draft"
spec for a patient/researcher/pharma funnel that was never built. Two prior reviews
(07-15, 07-22) *noted* this in passing but explicitly declined to propose it; a
quarter later it is still unreconciled, so I am proposing the actual decision, with
the concrete cheap slice.

### Proposed change

Make the decision explicit rather than leaving a contradictory spec live:

1. **Close/supersede (recommended):** add a status banner to
   `REDESIGN_FRONTEND.md` — e.g. *"Superseded 2026-08 by the methodology-first
   direction; see `articles/proposals/ARTICLE_QUEUE.md`."* — so no future agent
   treats the three-audience build as the active plan. Doc-only.
2. **Or revive one slice:** if the brand tagline is still wanted, the single
   cheapest adoption is swapping the hero copy at `build_static_site.R:286,292` to
   the spec's *"Know before it becomes a headline."* — one string, no structural
   change. The `/for/*` pages are a multi-page build and out of scope for a weekly
   fix.

Recommend #1 now (removes the trap in minutes); treat #2 as an independent copy
decision for Harlan.

### Effort estimate

- Supersede banner: ~10 min, doc-only.
- Tagline swap (if chosen): ~10 min + rebuild.
- Full three-audience build (explicitly **not** proposed this week): multi-day.

### Risk

Minimal for the doc banner. The tagline swap is copy that Harlan should sign off on
(brand voice), hence it is offered as an option, not bundled.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Make dead-internal-link detection a hard CI failure (build check is warn-only + mislabeled "Fails hard", and CI never runs it) | Correctness / release-safety | ~1 hr | Low |
| 2 | Stop the homepage showing the featured article (AEMS) twice | User-facing polish | ~10 min | Very low |
| 3 | Reconcile the stale `REDESIGN_FRONTEND.md` "Draft" with the shipped methods-first direction (supersede, or adopt the spec tagline) | Doc / direction consistency | ~10 min (doc) | Minimal |
