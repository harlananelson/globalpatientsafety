# Agent review — 2026-08-26

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Status of prior reviews (resolved since 2026-07-29)

The three items in `issues/agent-review-2026-07-29.md` have all landed, so none are
re-proposed:

- **Retired-app / CLAUDE.md reconciliation (#3)** — done. Commit `c4506dd`
  ("Archive retired Rhino/Shiny portal to archive/rhino-app/") and `7bc690b`
  ("Make static builder independent of the box package") moved the Shiny app out.
  CLAUDE.md now documents the static site as production and the schema table uses
  the current `drug` / `event` columns. `.github/workflows/site-checks.yml` replaced
  the old `rhino-test.yml` and runs `check_site_consistency.R` (so the earlier
  "CI tests only the retired app" finding is also resolved).
- **"Signal methods" card (#2)** — done. `app/logic/tools.R:24-25` is now
  `"Signal methods", "live", "/methods"`, and `check_site_consistency.R:118-125`
  guards against it regressing to `coming_soon`.
- **Dead links on the AEMS page + build link-check (#1)** — the AEMS page no longer
  links to drafts (`app/static/aems.html` now links only `/methods` and
  `/christine_cotton`, both published), and a `check_internal_links()` guard was
  added to `scripts/build_static_site.R:446-489`. **But that guard is toothless and
  is not in the CI path** — which is Proposal 1 below.

Sibling-repo roadmaps (`SEARCH_REDESIGN.md`, `NOVELTY_FILTER_ROADMAP.md`) target
`faers-mobi` / `aers-mobi` and cannot be verified from this repo; not proposed.

---

## 1. The dead-internal-link guard added after 2026-07-29 is non-blocking and never runs in CI

**Severity:** correctness / CI coverage. The one production artifact (the static
site) still has no enforced link-integrity check, despite the guard that was written
to provide it.

### Evidence

The 2026-07-29 review asked for two things: a dead-link check in the builder, and a
CI job that runs it. The check was written, but neither property actually holds:

1. **It only warns — it never fails.** `scripts/build_static_site.R:446-489`
   (`check_internal_links()`) scans built HTML for same-site slug hrefs and, on a
   broken target, calls `warning(...)` (line 480) and prints a `cat("WARNING: ...")`
   (line 485). It never `stop()`s. Yet its own header comment claims the opposite:
   `build_static_site.R:444-445` — *"Fails hard on zero targets that look like
   article/standalone slugs."* Implementation and contract disagree; a dead link is
   a non-fatal warning that a deploy script (`rsync`, run right after per lines
   500-502) will scroll past.

2. **CI never runs it.** `.github/workflows/site-checks.yml` runs exactly one step —
   `Rscript --vanilla scripts/check_site_consistency.R`. It does **not** run
   `build_static_site.R` (which needs `dplyr`/`stringr`/`tibble` via renv; the CI job
   is deliberately base-R only). So `check_internal_links()` executes only on a
   developer's local build, if at all.

3. **The base-R CI check covers far less than the builder's check.**
   `scripts/check_site_consistency.R` scans for dead links only in **two** files and
   only for **draft-article** needles: `check_site_consistency.R:127-145` loops
   `standalone <- c("aems.html", "methods.html")` and fails only if one contains an
   `href` to a `draft` id. It never inspects the published article pages
   (`christine_cotton.html`, `shingles.html`, `covid_vaccine.html`) and never catches
   a link to a slug that was **never** an article (a typo, a renamed page, a deleted
   article). The published-article loop at `check_site_consistency.R:75-82` only
   checks that each `<id>.html` *exists*, not that its internal links resolve.

Net: a link like `href="/methdos"` or `href="/aav_gene_therapy_liver"` (a draft) added
to `christine_cotton.html` would ship — CI is green (that file isn't scanned) and the
local builder, if run at all, only warns.

### Proposed change

Close the gap in the base-R script that CI actually runs. In
`check_site_consistency.R`, after loading `ARTICLES`/`TOOLS`, scan **every**
`app/static/*.html` for same-site slug hrefs (`href="/slug"` / `href="./slug"`, the
same regex shape as `build_static_site.R:462-467`) and `fail()` if a slug is not in
the built set (`published$id` ∪ standalone ids ∪ `index`/`articles`). This subsumes
the existing draft-link check (a draft id is simply not in the published set) and
extends it to all shipped pages and all missing targets. Separately, either make
`build_static_site.R:check_internal_links()` `stop()` on broken links (so a local
build is trustworthy) or downgrade its header comment to match "warn only" — right
now the comment lies about the behavior.

### Effort estimate

~45–60 min. One added loop in `check_site_consistency.R` (base R, mirrors the regex
already in the builder) plus a one-line `stop()`-or-comment fix in the builder.

### Risk

Low. The CI script is base-R and non-deploying; a stricter check can only *reject*
bad states, never break a good one. Verify by adding a deliberate dead link to a
scratch copy and confirming the check exits 1; then confirm the real tree still
passes (it does today — all internal links currently resolve).

---

## 2. There is no source-of-truth mapping from an article `id` to its Quarto source, and nothing verifies one exists — a publish-time trap for the three reMarkable-gated drafts

**Severity:** correctness / maintainability. Latent, but it fires exactly when the
human-gated drafts are approved — the moment the publisher is least able to absorb a
silent naming mismatch.

### Evidence

The article `id` (which names the static HTML the builder reads, `app/static/<id>.html`)
and the Quarto source filename use **different, inconsistent conventions**, and no file
records the mapping:

- `app/logic/articles.R` ids use underscores: `aav_gene_therapy_liver`
  (`articles.R:25`), `glp1_alopecia` (`:29`), `carbidopa_levodopa_b6` (`:33`).
- The sources in `articles/` use hyphens — and one carries an extra suffix:
  `aav-gene-therapy-liver.qmd`, `glp1-alopecia.qmd`, and
  `carbidopa-levodopa-b6-seizures.qmd` (note the `-seizures` that the id
  `carbidopa_levodopa_b6` drops).
- Already-published articles show the mapping is genuinely ad hoc, not a rule:
  `christine_cotton` ← `articles/christine-cotton-vaers.qmd`; `shingles` ←
  `shingles_vaccine_analysis.qmd` (repo root, `.qmd` with a different stem, plus a
  stub `articles/shingles.md`); `covid_vaccine` ← `covid_vaccine_vaers_analysis.qmd`
  (repo root). Three different transforms, none documented.
- A **third** naming scheme lives in `scripts/render_remarkable.sh` (the `TITLES`
  map, e.g. `"AAV Gene Therapy Liver (FAERS)"`), used for the PDF filenames.

So publishing a draft requires the author to manually reconcile three naming schemes
per article — `quarto render aav-gene-therapy-liver.qmd` emits
`aav-gene-therapy-liver.html`, which must be renamed to
`app/static/aav_gene_therapy_liver.html` to match the `articles.R` id before the
builder will pick it up. Nothing guards this: `check_site_consistency.R:75-82` checks
only that `app/static/<id>.html` exists for *published* rows, so a mis-rendered stem
(or a typo'd id) surfaces as a CI failure with no hint that the cause is a
hyphen/underscore/suffix mismatch, and a `draft` id with no matching source at all is
never flagged.

### Proposed change

Make the source explicit and checkable. Cheapest first step: add a `source` column to
the `ARTICLES` tribble in `app/logic/articles.R` naming each row's `.qmd` path (e.g.
`articles/aav-gene-therapy-liver.qmd`). Then extend `check_site_consistency.R` to fail
if a row's `source` file is missing — for **every** row, `draft` included — so a
broken id↔source link is caught at review time, not publish time. A lighter
alternative if a schema change is unwanted: a short "Publishing" note in CLAUDE.md's
"Adding a published article" section spelling out the hyphen→underscore rename and the
`-seizures`-style suffix drops, with the current mapping table.

### Effort estimate

~30–45 min for the `source` column + one existence loop in the consistency check;
~15 min for the docs-only variant. No builder change needed for either.

### Risk

Low. Adding a column the builder ignores is inert (the loaders read named columns).
The consistency check is CI-only and non-deploying. Confirm the new column parses
through both tribble loaders (`build_static_site.R:49-66` and
`check_site_consistency.R:27-62`) — both are position-independent on named formulas,
so an appended column is safe.

---

## 3. The public "marketing-face" pages ship with no social-preview metadata and no sitemap/robots — links shared to reach licensors, researchers, and journalists render blank

**Severity:** user-facing reach / discoverability. Small and high-leverage: the whole
stated point of this repo is to be *found* and *shared*.

### Evidence

`REDESIGN_FRONTEND.md:11` frames the site as "the marketing face," and DECISION_LOG's
2026-08-07 entry describes the AEMS primer being featured as the landing "if licensors
or new visitors land first." Reach depends on shared links and search — and both are
under-served:

- **No OpenGraph / Twitter-card / canonical tags.** `site_head()`
  (`build_static_site.R:107-136`) emits only `<title>` (`:113`), a `description` meta
  (`:114`), a favicon link (`:115`), Bootstrap, and the Inter font. There is no
  `og:title`, `og:description`, `og:image`, `og:url`, `twitter:card`, or
  `<link rel="canonical">`. A grep of the builder for `og:|twitter:|canonical` returns
  nothing, and the Quarto article HTML has none either (`app/static/christine_cotton.html`
  has no `og:*` meta). Result: a link to globalpatientsafety.com or to any article,
  pasted into Slack / LinkedIn / X / iMessage, renders as a bare URL with no title,
  blurb, or image — the worst possible first impression for the exact audiences the
  site is courting.
- **No `sitemap.xml` and no `robots.txt`.** The build run block
  (`build_static_site.R:491-498`) writes `index`, `articles`, article pages,
  standalone pages, and the favicon — nothing else; `git ls-files` tracks no
  `robots.txt` or `sitemap.xml`. Search engines get no crawl hint and no canonical
  page list for a site that is otherwise a flat set of static pages ideal for a
  sitemap.

### Proposed change

All builder-local, no new dependencies:

1. Extend `site_head()` to accept an optional `image`/`url` and emit `og:title`,
   `og:description`, `og:type`, `og:url`, `og:image`, `twitter:card` (summary or
   summary_large_image), and a `<link rel="canonical">`. Default `og:title`/
   `og:description` to the existing title/description already passed in; pass the
   per-article title/subtitle from `build_article_pages()`. A single shared preview
   image under `app/static/` (copied like the favicon at `:434-440`) is enough to
   start.
2. Add a `build_sitemap()` that writes `static_site/sitemap.xml` from the same page
   set the builder already enumerates (index, articles, each `published$id`, each
   `available_standalone$id`), plus a two-line `static_site/robots.txt` pointing at it.
   Wire both into the run block after `build_standalone_pages()`.

### Effort estimate

~1–1.5 hr: `site_head()` signature/threading is the bulk; `build_sitemap()` +
`robots.txt` are ~20 lines of string-building over lists the builder already has.

### Risk

Low. Additive `<head>` tags and two new static files; no change to existing page
bodies or routes. Verify OG tags with a card validator (or by pasting a URL into a
chat app) after the next deploy, and confirm `sitemap.xml` lists only pages that
actually built (reuse `available_standalone`, not the full `STANDALONE_PAGES`, so a
skipped render never lands in the sitemap).

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Make the dead-internal-link guard blocking and run it in CI (port into `check_site_consistency.R`; fix builder comment/`stop()`) | Correctness / CI | ~1 hr | Low |
| 2 | Record each article `id`→source `.qmd` mapping and verify the source exists (add `source` column + consistency check) | Correctness / maintainability | ~30–45 min | Low |
| 3 | Add OpenGraph/Twitter/canonical meta + `sitemap.xml`/`robots.txt` to the static build | Reach / discoverability | ~1–1.5 hr | Low |
</content>
</invoke>
