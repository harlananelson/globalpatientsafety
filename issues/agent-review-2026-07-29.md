# Agent review — 2026-07-29

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

Scope note that shaped the picks: `scripts/build_static_site.R` (header comment)
and `articles/DEPLOY-christine-cotton.md` both state plainly that **the
interactive Shiny app at this domain was retired**, and the static site written
by `build_static_site.R` is what is rsync'd to nginx at
`globalpatientsafety.com`. So the *production* surface is the static site, not the
Rhino app under `app/`. The novelty-filter and dropdown roadmaps
(`NOVELTY_FILTER_ROADMAP.md`, `DEPLOY_PLAN.md`) target the sibling `faers-mobi` /
`aers-mobi` repos, and the two files under `issues/` (`ajax-error.md`,
`signal-disconnection.md`) are `aers-mobi` triage — none are portal work, so they
are not re-proposed here.

No prior `issues/agent-review-*.md` files exist; this is the first.

---

## 1. Dead internal links on the live "Signal & Noise" AEMS page

**Severity:** user-facing correctness on a flagship public page.

### Evidence

The live standalone page `app/static/aems.html` (built + deployed by
`build_static_site.R::build_standalone_pages`, source `articles/aems-analysis.qmd`)
recommends two sibling articles as reading:

- `app/static/aems.html:3578` — `<a href="./carbidopa_levodopa_b6">A Warning Built on 14 Cases</a>`
- `app/static/aems.html:3579` — `<a href="./glp1_alopecia">A Moving Target</a>`

Both target article ids are **`status = "draft"`** in `app/logic/articles.R`:

- `app/logic/articles.R:19` — `glp1_alopecia` … `"draft"`
- `app/logic/articles.R:23` — `carbidopa_levodopa_b6` … `"draft"`

`build_static_site.R::build_article_pages` iterates `published <- ARTICLES |>
filter(status == "published")` only, so it never emits `/carbidopa_levodopa_b6`
or `/glp1_alopecia`. Result: both links 404 for every visitor of the AEMS page.
(`app/static/methods.html` was checked too — its only relative link is
`href="/aems"`, which is fine.)

This is not a stale-render accident so much as a sequencing gap: the AEMS page was
written assuming those two drafts would already be live. Per
`articles/proposals/ARTICLE_QUEUE.md:12-15` they are still in the reMarkable
review backlog awaiting Harlan's approval (publishing is deliberately
human-gated), so the AEMS page shipped ahead of the articles it points to.

### Proposed change

Two parts, both report-only recommendations:

1. **Immediate (stops the 404s):** in the source `articles/aems-analysis.qmd`,
   render the two forthcoming pieces as plain (non-link) "forthcoming" text until
   they are approved and published, then re-render to `app/static/aems.html` and
   rebuild. Alternatively, if the two articles are approved this cycle, publishing
   them (flip `status` to `published` in `app/logic/articles.R`, render each `.qmd`
   → `app/static/<id>.html`) resolves the links — but that is the human-gated
   deploy step, out of scope for this report.
2. **Durable (prevents recurrence):** add a dead-internal-link check to
   `build_static_site.R`. After all pages are written, scan every emitted HTML for
   `href="./<id>"` / `href="/<id>"` and `stop()` (or warn loudly) if `<id>` is not
   in the set of pages actually emitted (published article ids + standalone ids +
   `index`/`articles`). This is the one build that has no such guard and it is the
   production artifact.

### Effort estimate

- Interim source edit + re-render: ~20 min (needs the `nix develop` + Quarto render
  path documented in `DEPLOY-christine-cotton.md`).
- Link-integrity check in `build_static_site.R`: ~30–45 min, pure string scan over
  the already-in-memory HTML.

### Risk

Low. The link check is build-time only. The interim `.qmd` edit touches only
prose. Main risk is forgetting to re-render `app/static/aems.html` after editing
the `.qmd` (the `.html`, not the `.qmd`, is what the build reads) — the proposed
link check would itself catch that.

---

## 2. "Signal methods" tool card advertises "Coming soon" for a page that is already live

**Severity:** user-facing consistency; small, high-leverage.

### Evidence

The landing-page tool grid is generated from `app/logic/tools.R`. It still carries:

- `app/logic/tools.R:24-25` — `"Signal methods", "coming_soon", NA_character_,`
  `"Reference documentation for the four disproportionality methods implemented
  across the apps: GPS/EBGM, PRR, ROR, BCPNN/IC."`

`build_static_site.R::tool_card_html` renders any `coming_soon` row greyed out and
unclickable (`style="opacity:0.55; cursor: not-allowed;"`).

But that reference documentation now exists and is live:

- `build_static_site.R::site_nav` has `<a class="nav-link" href="/methods">Signal
  &amp; Noise</a>` in the top nav of every page.
- `app/static/methods.html` exists and is emitted by `build_standalone_pages`
  (`STANDALONE_PAGES` row `"methods", "Signal & Noise"` in `build_static_site.R`).
- DECISION_LOG entry `2026-07-13 — Signal & Noise: named series + /methods page`
  records building and wiring it.

So a visitor sees a live "Signal & Noise" link in the nav *and* a greyed-out
"Signal methods — Coming soon" card in the tool grid, for the same content. The
card understates what is shipped and reads as a broken promise.

### Proposed change

In `app/logic/tools.R`, either:

- flip the row to `status = "live"`, `url = "/methods"`, and align the name/tagline
  with the page (e.g. name it "Signal & Noise" and describe it as the "reading FDA
  adverse-event data" methodology series, consistent with
  `ARTICLE_QUEUE.md:23-48`); or
- remove the row, since the nav already surfaces `/methods`.

Recommend the first: a tool card is higher-visibility than a nav link for a
first-time visitor, and the methodology series is the site's stated distinctive
lane.

### Effort estimate

~10 minutes (single tribble row). Rebuild picks it up automatically; no template
change needed.

### Risk

Very low. `/methods` is same-origin, so the extensionless URL resolves under the
same nginx clean-URL rule the other pages already rely on (the deploy doc's
smoke-test hits `/christine_cotton` the same way). Worth a one-line confirmation
that `/methods` serves before flipping.

---

## 3. The retired Shiny app is documented as production and is the only thing CI tests — reconcile it

**Severity:** correctness/maintainability + doc consistency; a trap for the next
contributor (human or agent).

### Evidence

Production is the static site (see scope note; `build_static_site.R` header and
`DEPLOY-christine-cotton.md` both say the Shiny app "was retired"). Yet:

- **CLAUDE.md still frames the Shiny app as the product.** Its overview calls the
  repo a "Rhino/Shiny portal app … Renders a landing page," and the Key Files table
  lists `app/main.R` as "App entry point" with **no mention of
  `scripts/build_static_site.R`** — the file that actually produces the deployed
  site. The tool-suite table also omits the now-live **VAERS** tool that is present
  in `app/logic/tools.R:22-23` (`"VAERS vaccine safety", "live"`). A future agent
  reading CLAUDE.md would edit and test the wrong surface.
- **CI tests only the retired app.** `.github/workflows/rhino-test.yml` runs
  `rhino::lint_r/js/sass`, `rhino::test_r()`, and a Cypress e2e against
  `npm run run-app` (the Shiny app). Nothing runs `build_static_site.R` or
  validates `static_site/`. The production artifact has **zero** automated coverage;
  the retired one has full coverage.
- **The retired app has already rotted, unnoticed, precisely because nothing
  exercises it against real data:**
  - `app/main.R:70-97` `.featured_article_card` renders a "Read article →" button
    for the featured article, which is `christine_cotton`
    (`app/logic/articles.R:27`, `featured = TRUE`). Clicking it calls
    `nav_to_article("christine_cotton")` → tab value `article_christine_cotton`.
    But `.ARTICLE_MODULES` (`app/main.R:25-28`) registers only `shingles` and
    `covid_vaccine`, and there is no `app/view/article_christine_cotton.R`, so
    `.build_articles_menu` (`app/main.R:35-66`) never creates that tab. The
    featured button is dead in the Shiny app.
  - `app/view/articles.R:49` renders a card + "Read →" button for **every** row of
    `ARTICLES`, including the three `draft` rows and `christine_cotton`, none of
    which have tabs — four of the six index buttons are dead.
  - The existing smoke test `tests/testthat/test-main.R` only asserts the server
    starts; it cannot catch either. The Cypress test `tests/cypress/e2e/app.cy.js`
    is a bare `it('starts', () => {})`.

  These are harmless *today* only because the Shiny app isn't served — which is
  exactly the point: it's unmaintained code carrying live-looking bugs, presented
  by CLAUDE.md as the product.

### Proposed change

1. **Cheapest, highest-leverage:** update `CLAUDE.md` to state that the deployed
   site is the static build (`scripts/build_static_site.R` → `static_site/` →
   nginx), that `app/` is a retired interactive app, and add `build_static_site.R`
   to the Key Files table; add the VAERS row to the tool-suite table so it matches
   `tools.R`.
2. **Decide the app's fate:** either (a) prune the retired Rhino app and its
   Cypress/rhino CI, or (b) if it is kept as a fallback, fix the two dead-link
   defects above (add `article_christine_cotton` to `.ARTICLE_MODULES` — the static
   HTML `app/static/christine_cotton.html` already exists — and filter
   `app/view/articles.R:49` to published+registered rows).
3. **Give production a test:** add a CI job that runs `build_static_site.R` and the
   link-integrity check from proposal #1, so the deployed artifact is validated on
   every push.

Recommend #1 now (minutes, removes the trap), then #3; make the #2 keep-or-prune
call with Harlan.

### Effort estimate

- CLAUDE.md reconciliation: ~20–30 min.
- CI job to build + link-check the static site: ~1 hr.
- Prune-or-fix the retired app: ~1–2 hr depending on the decision.

### Risk

Low for the doc and CI-build changes (no runtime/deploy impact). Pruning the Shiny
app is the only higher-risk option and should be a deliberate, separate decision —
hence it is split out above rather than bundled.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Fix dead `carbidopa`/`glp1` links on live AEMS page + add build link-check | Correctness / user-facing | ~1 hr | Low |
| 2 | Make "Signal methods" card live → `/methods` (or remove it) | Consistency / user-facing | ~10 min | Very low |
| 3 | Reconcile CLAUDE.md + CI with the static site being production; decide retired-app fate | Maintainability / doc consistency | ~30 min–2 hr | Low (doc/CI) |
