# Agent review — 2026-09-02

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no file other than this one is modified.

## Scope and what has changed since the last review

The production surface is the static site built by `scripts/build_static_site.R`
and rsync'd to nginx; the Rhino/Shiny portal was archived to `archive/rhino-app/`
(commit `c4506dd`) and production caught up (`6094985`, "Deploy static site;
production caught up after ~2.5 months"). So every portal-app finding from the
July reviews is now moot by construction — the app they described no longer runs.

Status of the four prior `issues/agent-review-*.md` (all landed via PR #9,
`issues/IMPLEMENTATION-2026-07-30-claude-prs.md`), confirmed against current code
so they are **not** re-proposed:

- "Signal methods" card `coming_soon` → now `live`, `/methods`
  (`app/logic/tools.R:26`). **Fixed.**
- `christine_cotton` unreachable in Shiny → app archived; now a static page.
  **Moot.**
- AEMS page linked to draft articles (404s) → de-linked; verified no draft slugs
  remain in `app/static/aems.html` today. **Fixed.**
- No dead-internal-link guard → `check_internal_links()` added to the builder
  (`scripts/build_static_site.R:463`). **Partially fixed — see finding 2, it
  does not run in CI.**

The active roadmap in `DECISION_LOG.md` (2026-08-07 → 2026-08-17) is the
MedDRA/MSSO subscription and the hierarchy/SMQ/triage features it gates. Those
live in the **sibling** `faers-mobi`/`aers-mobi` repos, not this clearing-house
repo, and cannot be advanced from here — so this review stays on the static-site
production surface, where all three findings below are concrete and portal-local.

Note: `Rscript` is not installed in this review environment, so
`scripts/check_site_consistency.R` could not be executed here; findings are from
static reading of the sources, not a run.

---

## 1. The public site ships no social-share or search metadata — no Open Graph / Twitter Card, no canonical URL, no sitemap.xml, no robots.txt

**Severity:** user-facing discoverability gap on the whole public surface. This is
the single highest-leverage fix available in this repo right now.

### Evidence

`site_head()` (the `<head>` used by every built page —
`scripts/build_static_site.R:107-135`) emits exactly one discovery-relevant tag:

```r
  <meta name="description" content="%s">   # build_static_site.R:114
```

Grepping the whole builder for `og:|twitter:|canonical|sitemap|robots` returns
**nothing**. The "Run all" block (`scripts/build_static_site.R:491-498`) writes
`index.html`, `articles.html`, the article pages, the standalone pages, and
`favicon.ico` — and no `sitemap.xml` or `robots.txt`. Neither file exists anywhere
in the repo (`find` for `sitemap*` / `robots.txt` → none).

Consequence, given the site's own stated strategy:

- The articles are written to be **shared and found**. When any of them
  (`/aems`, `/christine_cotton`, `/shingles`, `/covid_vaccine`) is posted to
  Slack, X, LinkedIn, iMessage, Signal, etc., the unfurled preview has no title
  image, no `og:title`, no `og:description` — it degrades to a bare URL or a
  guessed title. For a site whose growth path is people passing analyses around,
  this quietly suppresses every share.
- `app/logic/articles.R:14-16` records the explicit intent that the AEMS primer is
  "a good landing if MedDRA/MSSO or other licensors visit after a subscription
  ask." A licensor who searches for the site gets no `sitemap.xml` to crawl and no
  canonical hints — the featured landing page is harder to index than it should be.
- No `canonical` tag means the backward-compat `?article=<id>` redirect
  (`scripts/build_static_site.R` footer script) and any `/index.html` vs `/` split
  can be indexed as duplicate URLs.

This is a pure gap, not a regression — it has simply never been added.

### Proposed change

All in `scripts/build_static_site.R`, no new dependencies:

1. Extend `site_head()` to accept a `canonical` (and optional `image`) argument and
   emit `og:title`, `og:description`, `og:type`, `og:url`, `og:site_name`,
   `twitter:card` (`summary_large_image`), and `<link rel="canonical">`. Pass the
   per-page title/description/URL already available at each call site.
2. Add a `build_sitemap()` that walks `published$id`, `available_standalone$id`, and
   the `index`/`articles` roots, writing `static_site/sitemap.xml` with
   `https://globalpatientsafety.com/<id>` entries; add it to the "Run all" block.
3. Emit a minimal `static_site/robots.txt` (`Allow: /` + `Sitemap:` line).
4. Article/standalone pages are post-processed Quarto HTML — the builder only
   injects nav after `<body>` (`build_article_pages()`), so OG tags for those pages
   need a small `<head>` post-process (insert before `</head>`) or the tags added
   in the Quarto YAML. The `<head>` insertion in the builder is the lower-risk path
   and keeps the source of truth in one place.

### Effort estimate

~1.5–2 hours: ~30 min for the `site_head()` OG/canonical block and call-site
wiring, ~30 min for `build_sitemap()` + `robots.txt`, ~30 min for the article-page
`<head>` post-process, plus a rebuild and a spot-check of one unfurl (e.g. paste
`/aems` into a link-preview validator).

### Risk

Low. New tags and new files only; no existing output changes except an enlarged
`<head>`. Main care point is not double-injecting into Quarto pages that may already
carry a Quarto-generated `og:` block — check one rendered article's `<head>` first
and make the insertion idempotent (skip if `og:title` already present).

---

## 2. CI never runs the builder, so the dead-internal-link guard added to stop the AEMS-404 regression does not actually run in CI

**Severity:** process/correctness — the guard that the 2026-07-29 review's #1
finding motivated is not wired into the gate that would enforce it.

### Evidence

`.github/workflows/site-checks.yml` has one job, `static-site-consistency`, whose
only real step is:

```yaml
run: Rscript --vanilla scripts/check_site_consistency.R
```

It never invokes `scripts/build_static_site.R`. But the dead-internal-link
guard lives **inside the builder**: `check_internal_links()` is defined at
`scripts/build_static_site.R:463-489` and called only from the builder's "Run all"
block at `scripts/build_static_site.R:498`. So on push/PR, CI never builds the site
and never runs `check_internal_links()`.

That guard was added on 2026-07-30 (`issues/IMPLEMENTATION-2026-07-30-claude-prs.md`,
row "No dead-internal-link guard") specifically to catch the class of bug that the
2026-07-29 review flagged as its top finding: the AEMS page linking to
unpublished/404 articles. Today that exact regression could be reintroduced — e.g.
a new `<a href="./some_draft">` in a Quarto source, or flipping an article back to
`draft` while a page still links it — and **CI stays green**, because the only check
that would catch it is in a script CI never executes.

Two independent registry parsers also exist and can silently drift:
`load_tribble()` in the builder (`build_static_site.R:53-77`) and
`load_tribble_file()` in the checker (`check_site_consistency.R`). A change that
breaks the builder's parser (e.g. a `box::` reintroduction the builder rejects at
`build_static_site.R:57-61`) would not be caught by the checker's parser, and CI
runs only the latter.

### Proposed change

Add a second step (or job) to `.github/workflows/site-checks.yml` that runs the
builder and fails on its warnings:

- `Rscript scripts/build_static_site.R` (needs `tibble`, `dplyr`, `stringr` — use
  `r-lib/actions/setup-r-dependencies@v2` or install the three), then
- promote the link check to a hard failure in CI: either run a step that greps the
  build log for `WARNING:` / `dead internal link` and exits non-zero, or add a
  `--strict` flag to the builder that turns `check_internal_links()`'s warning into
  a non-zero exit. The builder already prints
  `"WARNING: N dead internal link(s) detected."` (`build_static_site.R:483`), so the
  grep approach is a one-liner.

Keep the base-R `check_site_consistency.R` job as-is (fast, dependency-free); this
adds the build-level guard alongside it.

### Effort estimate

~45–60 min: add the dependency install + build step, decide warning→failure
mechanism, confirm the job goes red on a deliberately broken link and green
otherwise.

### Risk

Low–medium. The only real risk is CI flakiness from installing R package deps;
mitigated by `r-lib`'s cached setup actions. No production or source changes.

---

## 3. Article source-of-truth is split between `articles/` and the repo root, contradicting CLAUDE.md, with a stale 4.8 MB duplicate at root

**Severity:** maintainability/correctness — "which file do I edit to fix the
deployed COVID article?" currently has no correct answer from the documentation.

### Evidence

`CLAUDE.md:23` states the contract plainly:

> | **Article HTML** | Quarto sources in `articles/*.qmd` → render into `app/static/<id>.html` |

That contract already does not hold for two of the four shipped articles:

- **`covid_vaccine`** (shipped as `app/static/covid_vaccine.html`, title "COVID-19
  Vaccine Safety Signals in VAERS") has **no** `articles/covid*.qmd`. The only
  matching Quarto source is `covid_vaccine_vaers_analysis.qmd` **at the repo root**,
  and a stale rendered `covid_vaccine_vaers_analysis.html` (**4.8 MB**) sits beside
  it at root. Neither is referenced by the builder or the registries
  (`grep covid_vaccine_vaers_analysis scripts/ app/ .github/` → not referenced).
- **`shingles`** has **two** candidate sources: `articles/shingles.md` and
  `shingles_vaccine_analysis.qmd` at the repo root. Nothing records which one
  produced the shipped `app/static/shingles.html`.

So a maintainer following `CLAUDE.md` would look in `articles/` for the COVID
source, not find it, and never know the real source is a root-level file that also
has a stale 4.8 MB HTML twin. The root artifacts also bloat every clone.

By contrast the drafts and the other published pieces do follow the convention
(`articles/aems-analysis.qmd`, `articles/christine-cotton-vaers.qmd`,
`articles/methods.qmd`, plus the three draft `articles/*.qmd`), which makes the two
root exceptions pure drift rather than an intended pattern.

### Proposed change

Report-only recommendation (no files changed by this review):

1. Move `covid_vaccine_vaers_analysis.qmd` → `articles/covid-vaccine-vaers.qmd`
   (or otherwise into `articles/`), and reconcile `shingles`: keep exactly one of
   `articles/shingles.md` / root `shingles_vaccine_analysis.qmd` as the source of
   `app/static/shingles.html`, delete the other.
2. Delete the orphaned root `covid_vaccine_vaers_analysis.html` (4.8 MB) — the
   shipped page is `app/static/covid_vaccine.html`; the root copy is not built,
   deployed, or referenced.
3. Add an explicit `id → source .qmd` mapping to `CLAUDE.md` (a column in the
   architecture table or a short list under "Adding a published article") so the
   source of every `app/static/<id>.html` is documented, and consider a
   consistency-check assertion that each published `id` has a known source path.

### Effort estimate

~30–45 min: confirm which shingles source is canonical (diff each against
`app/static/shingles.html`), move/delete files, update `CLAUDE.md`. No builder
change strictly required, though a source-path assertion in
`check_site_consistency.R` would be a nice guard (~20 min extra).

### Risk

Low. These are untracked-by-the-build root files; moving/removing them cannot change
built output (the builder reads only `app/static/<id>.html`). Verify the canonical
shingles source by diffing before deleting the other, so no source is lost.

---

## Minor, noted but not ranked

- **Homepage shows the featured article twice.** `featured` is `aems`
  (`app/logic/articles.R`, `featured = TRUE`), which is also the newest `published`
  row, so it is both the "★ Start here" featured card and the first of the three
  "Recent articles" cards (`scripts/build_static_site.R:277`,
  `recent_articles <- published |> arrange(desc(date)) |> head(3)` does not exclude
  the featured id). A one-line fix — drop the featured id before `head(3)` — would
  de-duplicate the splash. Cosmetic; folded here rather than ranked.
