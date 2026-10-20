# Agent review — 2026-09-23

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines or DECISION_LOG entries.
**Report-only** — nothing here is deployed, and no files other than this one are
modified.

## Scope note

Production is the **static site** (`scripts/build_static_site.R` → `static_site/`
→ nginx), per `CLAUDE.md` and `articles/DEPLOY-christine-cotton.md`. The retired
Rhino/Shiny app now lives under `archive/rhino-app/` and is not built or tested.
The recent `issues/*-2026-09-*.md` files are **faers-mobi** handshake tickets
(sibling repo), not portal work, so they are not re-proposed here. The three
`review-*.md` files at repo root and the `NOVELTY_FILTER_ROADMAP.md` /
`SEARCH_REDESIGN.md` roadmaps also target the sibling apps, not this static site.

## Status of prior `agent-review-*.md` proposals (last was 2026-07-29; ~8 weeks ago)

Reconciling the four prior reviews against the current tree — most are **resolved**:

- **Signal-methods card stuck on "Coming soon"** (07-15 #1, 07-22 #2, 07-29 #2) —
  **DONE.** `app/logic/tools.R:24-25` is now `"Signal methods", "live", "/methods"`.
- **Dead `carbidopa`/`glp1` links on the live AEMS page** (07-29 #1) — **DONE.**
  `app/static/aems.html` now links only `/christine_cotton` and `/methods` (both
  live). A build-time link scan (`check_internal_links()`) was added — but see
  proposal 2 below: it is warn-only and outside CI.
- **CLAUDE.md / architecture misrepresents the deployed surface** (07-15 #2,
  07-22, 07-29 #3) — **DONE.** `CLAUDE.md` now leads with the static site,
  lists `scripts/build_static_site.R`, the VAERS tool, and the Rhino retirement.
- **Retired Rhino app is the only thing CI tests / carries dead-link bugs**
  (07-15 #2, 07-22 #1/#3, 07-29 #3) — **DONE.** The app was archived to
  `archive/rhino-app/`; CI (`.github/workflows/site-checks.yml`) now runs
  `scripts/check_site_consistency.R` against the registries, not a Cypress/rhino
  suite.
- **Nav links to `/methods` `/aems` decoupled from whether the page built**
  (07-15 #3) — **DONE.** `build_static_site.R:83-91,140-147` emits standalone nav
  links only when `app/static/<id>.html` exists.

The three proposals below are **new** — none repeats a still-open prior item.

---

## 1. The public marketing site ships with no social/SEO/LLM discovery metadata at all

**Type:** user-facing discoverability gap on the brand's marketing face. **Severity:**
medium-high (every shared link and every crawler is affected). **Effort:** ~1–1.5 hr.

### Evidence

`REDESIGN_FRONTEND.md:14` states this repo "stays public as the **marketing
face**." Yet the builder emits essentially no discovery metadata:

- `scripts/build_static_site.R:107-135` (`site_head`) writes only `<title>` and
  `<meta name="description">`. There is **no** `og:title` / `og:description` /
  `og:image` / `og:url`, no `twitter:card`, and no `<link rel="canonical">`. A grep
  of the whole builder for `og:|twitter:|canonical|sitemap|robots|schema.org`
  returns nothing.
- The Quarto-rendered article pages are worse: `app/static/christine_cotton.html`
  carries only a `<title>` in its head — **no `<meta name="description">` and no
  Open Graph tags** (the two `twitter` hits in `methods.html` are Bootstrap-icon
  CSS glyphs, `.bi-twitter::before`, not meta tags).
- No `static_site/sitemap.xml`, no `robots.txt`, and no `llms.txt` are produced
  anywhere (`find . -iname 'sitemap*' -o -iname 'robots.txt' -o -iname 'llms.txt'`
  is empty).

The contrast is the notable part: `DECISION_LOG.md` (2026-09-13 … 2026-09-17)
records a large, sustained investment in machine/LLM discovery for **faers-mobi**
— `llms.txt`, `api.md`, `openapi.json`, `chatgpt.md`, a bot-user-agent Markdown
homepage (`/bot-home.md`). None of that reached the **portal that links to all of
them**. When someone shares `globalpatientsafety.com` (or an article URL) in
Slack, iMessage, LinkedIn, or an LLM chat, there is no title card, no summary, no
image — and search/LLM crawlers get one `<title>` per page and no sitemap.

### Proposed change

In `site_head()` (`build_static_site.R:107-135`), add — from the `title`/
`description` already passed (index passes both at lines 285-286) plus a
per-page canonical URL and a single default `og:image`:

- `og:title`, `og:description`, `og:type`, `og:url`, `og:image`, `og:site_name`
- `twitter:card` = `summary_large_image`, `twitter:title`, `twitter:description`
- `<link rel="canonical" href="https://globalpatientsafety.com/…">`

For the Quarto article pages (post-processed in `build_article_pages`,
`build_static_site.R:393-410`), inject the same tags — the `ARTICLES` tribble
already holds per-article `title`/`subtitle` to source them from — and add a
`<meta name="description">` where absent. Then emit a `static_site/sitemap.xml`
(published articles + standalone pages + index) and a minimal `robots.txt`
pointing at it, as two more small writer functions called from the build's
"Run all" block (`build_static_site.R:491-498`). Optionally a portal-level
`llms.txt` mirroring the faers-mobi pattern, listing the article corpus and tool
subdomains.

### Risk

Low. All additions are `<head>` metadata and two new static files; no page
content, layout, or deploy path changes. Main care point: get the canonical
host/URL right (extensionless clean URLs, matching the existing nginx rule) and
supply one real `og:image` asset (the favicon is too small for a card).

---

## 2. The dead-internal-link guard is warn-only and never runs in CI; the CI check only inspects two pages for *draft* links

**Type:** correctness / recurrence-prevention gap. **Severity:** medium (a dead
link in a *published* article body ships silently). **Effort:** ~45 min.

### Evidence

Proposal 07-29 #1 asked for a durable dead-link guard "so the deployed artifact
is validated on every push." Half of it landed; the teeth did not:

1. **The build's link check only warns.** `check_internal_links()`
   (`build_static_site.R:446-489`) collects broken same-site slugs and calls
   `warning(...)` + `cat("WARNING: … dead internal link(s) detected")`
   (lines 480-485). It never `stop()`s. A build with dead links still writes
   `static_site/` and exits 0.
2. **The build never runs in CI.** `.github/workflows/site-checks.yml` runs only
   `Rscript --vanilla scripts/check_site_consistency.R`. It does **not** invoke
   `build_static_site.R` (which needs `tibble`/`dplyr`/`stringr`, not installed by
   the vanilla job), so `check_internal_links()` fires only on a developer's local
   build — exactly where a warning is easiest to scroll past.
3. **The base-R CI guard checks far less than "all internal links."**
   `scripts/check_site_consistency.R:127-145` scans only `aems.html` and
   `methods.html`, and only for hrefs pointing at **draft article ids**. It does
   not scan `christine_cotton.html`, `shingles.html`, `covid_vaccine.html`,
   `index`/`articles`, or any article body, and it does not catch a link to a slug
   that simply does not exist (a typo, a renamed article, a `/for/researchers`
   stub written before the page). So the one check that runs on every push covers
   a narrow slice of one failure mode.

Net: the AEMS 404s that 07-29 #1 fixed by hand could recur from any future `.qmd`
edit and CI would stay green.

### Proposed change

Extend the base-R, already-in-CI `check_site_consistency.R` into a full
dead-internal-link scan: after its existing checks, walk **every** `app/static/
*.html` (the shipped article + standalone bodies) plus the builder's index/
articles output if present, extract same-site `href="/slug"` / `href="./slug"`
(reusing the regex already in `build_static_site.R:462-467`), and `fail()` when a
slug is neither a published article id, a standalone id, nor `index`/`articles`.
This keeps the guard base-R and inside the existing CI job — no new build
dependency. In parallel, flip `check_internal_links()`
(`build_static_site.R:479-485`) from `warning()` to `stop()` so a local build also
refuses to ship a dead link. Keeping both is belt-and-suspenders; the CI half is
the one that actually gates.

### Risk

Low. Pure validation; no output or deploy change. One care point: the scan must
whitelist the known non-article slugs the nav already emits (`index`, `articles`,
and anchors like `#about`), which the builder's version already does
(`build_static_site.R:469`) and can be copied verbatim.

---

## 3. The locked one-article-per-week cadence has produced zero new articles in ~9 weeks; three approved-pending drafts were never even rendered

**Type:** stalled roadmap / user-facing content gap, decision-shaped next step.
**Severity:** medium (the site's stated distinctive lane is idle). **Effort:**
render is ~30 min once approved; the real item is a 5-minute decision.

### Evidence

- `articles/proposals/ARTICLE_QUEUE.md` locks a cadence: "**one article every
  week, published on MONDAY** (locked 2026-07-13). **First publish: Monday
  2026-07-20.**" It also freezes new drafting: "**do NOT draft new articles until
  this clears.**"
- Today is **2026-09-23** — ~9 Mondays past the 2026-07-20 first-publish date. The
  "Drafted / published" table in `ARTICLE_QUEUE.md` still lists the same three
  pieces as "Drafted — pending review + render/deploy": AAV gene therapy liver,
  GLP-1 alopecia, carbidopa/levodopa B6. **None has published since
  christine_cotton (2026-06-13).**
- Those three are `status = "draft"` in `app/logic/articles.R:25-36` (rows dated
  2026-07-21 / 2026-07-14 / 2026-07-12), and their `.qmd` sources exist
  (`articles/aav-gene-therapy-liver.qmd`, `articles/glp1-alopecia.qmd`,
  `articles/carbidopa-levodopa-b6-seizures.qmd`) — but **none is rendered**:
  `app/static/{aav_gene_therapy_liver,glp1_alopecia,carbidopa_levodopa_b6}.html`
  are all missing. So they are not even *deploy-ready*; the instant Harlan
  approves, there is still a render step in the way.
- The freeze compounds it: with three drafts stuck behind the reMarkable approval
  gate and a "don't draft new" rule, the entire content pipeline — the site's
  "methodology-first … distinctive lane" per `ARTICLE_QUEUE.md` — has been idle
  for two months.

### Proposed change

Two report-only recommendations, both requiring a human decision (publishing is
deliberately human-gated — this agent does not flip `status` or deploy):

1. **Pre-render the three approved-pending drafts to `app/static/<id>.html` now**,
   so the human gate (approval) is the *only* remaining step and a same-day flip
   of `status` → `published` + rebuild ships them. Rendering is not the gate;
   approval is. Doing it ahead removes the hidden second delay. (Note: the file
   stems must match the `id`s in `articles.R` — `aav_gene_therapy_liver` etc.,
   underscores — not the hyphenated `.qmd` names.)
2. **Decide the freeze.** Either work the approval queue (publish ≥1 of the three
   this cycle to restart the Monday cadence) or explicitly lift "do NOT draft new
   articles until this clears" in `ARTICLE_QUEUE.md`. A 9-week freeze that no
   longer reflects intent is itself worth reconciling in the file.

### Risk

Low, and entirely reversible — rendering produces draft HTML that the build still
skips (only `published` rows are emitted, `build_static_site.R:71`), and
`check_site_consistency.R` already forbids a `published` row without matching HTML,
so nothing goes live by accident. The only real decision cost is Harlan's review
time on the queue.

---

## Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Add Open Graph / Twitter / canonical + sitemap.xml / robots.txt (and portal llms.txt) to the builder | Discoverability / user-facing | ~1–1.5 hr | Low |
| 2 | Make the dead-internal-link guard fatal and run a full link scan in CI (extend `check_site_consistency.R`) | Correctness / recurrence-prevention | ~45 min | Low |
| 3 | Restart the stalled weekly-article cadence: pre-render the 3 approved-pending drafts and decide the drafting freeze | Stalled roadmap / content | decision + ~30 min | Low |
