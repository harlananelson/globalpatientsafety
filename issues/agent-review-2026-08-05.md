# Agent review — 2026-08-05

Weekly reflection for globalpatientsafety.com. Report-only — this file is the
only change; nothing here is deployed.

## What changed since the last review (why prior findings are not re-raised)

The four prior `issues/agent-review-*.md` files (2026-07-08 → 2026-07-29) and
`IMPLEMENTATION-2026-07-30-claude-prs.md` describe a batch of fixes that have now
**landed on `main` and deployed**, so their findings are closed, not re-proposed:

- **Retired Shiny app** — archived to `archive/rhino-app/` (commit `c4506dd`); every
  prior "featured article unreachable in the Shiny portal / dead-click index" finding
  is moot. The production surface is now unambiguously the static builder.
- **"Signal methods" card** — now `live`, `url = "/methods"` (`app/logic/tools.R:24-25`).
- **CLAUDE.md drift** — rewritten around the static builder; schema is `drug`/`event`;
  VAERS listed live.
- **AEMS draft-link 404s** — de-linked; `check_site_consistency.R:127-145` now guards it.
- **CI** — `.github/workflows/site-checks.yml` runs `check_site_consistency.R`.
- **Builder `box` dependency, `NAV_INJECTION` sprintf warnings** — fixed
  (DECISION_LOG 2026-07-31).
- **Deploy** — production caught up to `main` on 2026-07-30 (`/methods`, `/aems`,
  `/christine_cotton` now 200; the two remaining drafts correctly 404).

Per the DECISION_LOG 2026-07-30 directive ("check the deployed site, not just the
source"), I tried to fetch `https://globalpatientsafety.com/{,methods,aems,christine_cotton,…}`
from this sandbox. **All requests returned curl code `000` (connection failed) — the
sandbox has no outbound route to the VPS**, so I could not independently verify live
state. The findings below are all source-anchored and do not depend on live inspection.

Sibling-repo roadmaps are out of scope and unverifiable from here: `NOVELTY_FILTER_ROADMAP.md`
(aers/faers.mobi) and `SEARCH_REDESIGN.md` (faers.mobi top-2000 search) both target
other repos. `REDESIGN_FRONTEND.md` is portal-scoped and noted at the end.

---

## 1. The site ships zero social-share / discoverability metadata — no Open Graph, no Twitter card, no `sitemap.xml`, no `robots.txt`

**Severity:** user-facing discoverability gap on the site whose stated job is to be the
public "marketing face." Small, high-leverage.

### Evidence

`site_head()` (`scripts/build_static_site.R:107-136`) is the `<head>` for every
builder-generated page (`index.html`, `articles.html`). It emits **only** `<title>`,
`<meta name="description">`, and a favicon link. Verified absence across the whole
deployed set:

```
og:/twitter:/canonical in build_static_site.R site_head()   → NONE
og:/twitter: in the Quarto article pages
  christine_cotton.html, shingles.html, covid_vaccine.html,
  methods.html, aems.html                                    → NONE (all five)
robots.txt / sitemap.xml anywhere in the repo                → NONE
builder writeLines/file.copy targets                         → index, articles,
                                                               <id>.html, favicon.ico only
```

So neither the builder-generated pages nor the Quarto-rendered article pages carry a
single `og:title` / `og:description` / `og:image` / `twitter:card` / `<link rel="canonical">`,
and the builder never emits `sitemap.xml` or `robots.txt`.

Why this matters specifically here, not as generic SEO advice:

- The project's own spec calls globalpatientsafety.com the **"marketing face"**
  (`REDESIGN_FRONTEND.md:9`, §1). A marketing face whose links unfurl as a bare URL on
  every platform is working against its stated purpose.
- The **content pipeline is built on social sharing**. `articles/proposals/attkisson-monitor.md`
  sources article ideas from a Substack feed, and the whole article strategy is "publish a
  reanalysis, get it read." When any of these article URLs is pasted into Substack, X,
  LinkedIn, Slack, or iMessage, it currently unfurls with no title card, no image, no
  summary — the worst-case presentation for exactly the distribution channel the project
  depends on.
- There is no `sitemap.xml` telling search engines the article set exists, and no
  `robots.txt`; the builder already knows the complete URL list (`published$id`,
  `available_standalone$id`, plus `index`/`articles`), so a sitemap is nearly free to emit.

### Proposed change

Two additive builder changes, no content edits:

1. In `site_head()`, add per-page `og:title`, `og:description`, `og:type`,
   `og:url` (canonical), `twitter:card = summary_large_image`, and a single default
   `og:image` (a static banner under `app/static/` copied to `static_site/`, mirroring
   the favicon copy at `build_static_site.R:426-432`). `build_index()` /
   `build_articles_index()` already have the title+description in hand to pass through.
   For the article pages, the nav is injected via `sub("(<body[^>]*>)", …)` — add a
   symmetric `sub("(</head>)", paste0(meta, "\\1"), …)` in `build_article_pages()`
   (`:385-402`) to inject per-article OG tags built from the `ARTICLES` row
   (`title`, `subtitle`), so shared article links unfurl with real copy.
2. Emit `sitemap.xml` (loop the same known-URL set `check_internal_links()` already
   computes at `:443-448`) and a minimal `robots.txt` pointing at it, as two more
   `writeLines` in the run block (`:483-490`).

### Effort estimate

~1.5–2 hr. OG/Twitter tags in `site_head` + article injection: ~1 hr. sitemap/robots:
~20 min (the URL set is already assembled). Sourcing one default `og:image`: ~15 min.

### Risk

Low. Purely additive `<head>` content and two new static files; no existing page body or
route changes. Only judgment call is the canonical host string (hardcode
`https://globalpatientsafety.com`). Verify one article's unfurl with a card validator
after deploy.

---

## 2. CI validates dead links on only 2 of the site's pages; the one comprehensive link checker is warn-only and never runs in CI (and its own docstring claims otherwise)

**Severity:** correctness/consistency guard that under-covers the artifact it exists to
protect. Concrete, source-anchored.

### Evidence

There are two link guards, and there is a gap between them:

- **The comprehensive one is non-blocking and out of CI.** `check_internal_links()`
  (`scripts/build_static_site.R:438-481`) scans **every** built page for same-site
  slugs and reports anything with no matching output file. But it calls **`warning()`**
  (`:471-477`), not `stop()`, so `Rscript scripts/build_static_site.R` still **exits 0**
  with a dead link present. Worse, the function's own docstring says the opposite:
  `build_static_site.R:437` — *"Fails hard on zero targets that look like article/standalone
  slugs."* It does not fail hard. And CI never runs the builder at all —
  `.github/workflows/site-checks.yml:30` runs only `check_site_consistency.R`.

- **The one CI *does* run scans only two pages, for only one class of bad link.**
  `check_site_consistency.R` confirms every `published` article has a static HTML file
  (`:75-82`), but it scans page **bodies** for bad links on just the two standalone
  pages — `standalone <- c("aems.html", "methods.html")` (`:128`), loop `:129-145` — and
  only for links to **draft** article ids (`draft_ids`, `:127`). It never scans the three
  **published** article pages (`christine_cotton.html`, `shingles.html`,
  `covid_vaccine.html`), and it never catches a link to a slug that simply **does not
  exist** (typo, renamed, or unpublished-and-not-a-draft).

Net: the guard that would catch a published article linking to a missing/renamed target
is (a) advisory-only and (b) never executed in CI. Today no published page has internal
cross-links (verified: `grep -oE 'href="\.?/[a-z0-9_-]+"'` over the three published
`app/static/*.html` returns nothing), so the gap is latent — but it is exactly the case
that will occur when the three queued drafts (§ "also noted") are rendered and cross-link
each other or the methods series, which is the project's stated near-term content plan
(`articles/proposals/ARTICLE_QUEUE.md`). The `methods.html → /aems` link
(`app/static/methods.html`) shows cross-linking between standalone pages is already the
norm.

### Proposed change

1. Reconcile the docstring with behavior: either make `check_internal_links()`
   `stop()` on a broken link (matching `:437`), or, if warn-only is intentional for
   local builds, correct the docstring — do not leave the comment claiming a guard the
   code doesn't provide.
2. Extend the CI check (`check_site_consistency.R`) to scan **all** shipped page bodies
   — the three published article HTMLs plus the standalones — for internal `href`s that
   point at a slug with no `app/static/<slug>.html` (superset of the current draft-only
   check), and `fail()` on any. This is the guard that actually runs on every push/PR.
3. Optionally add a CI step that runs `build_static_site.R` into a temp dir purely to
   exercise `check_internal_links()`, so the comprehensive scanner has a home in CI.

### Effort estimate

~1–1.5 hr. Docstring/`stop()` reconciliation: ~10 min. Generalizing the CI body-scan to
all pages + nonexistent-target detection: ~45 min (base-R string scan, same shape as the
existing `:129-145` loop). Optional builder-in-CI step: ~20 min YAML.

### Risk

Low. Tightening a guard can only reject builds that were already shipping a dead link.
Main caution: the broadened scan must whitelist non-page hrefs (assets, anchors, external)
the same way `check_internal_links()` already does at `:459-461`, or it will false-positive
on Quarto's own `<head>`/nav markup. Test against the current three published pages (which
must pass) before enabling `fail()`.

---

## 3. The CI consistency check duplicates the standalone-page list and a tool name as hardcoded literals, drifting from `STANDALONE_PAGES` — a known-open item with a clear fix

**Severity:** maintainability / silent under-coverage. Explicitly logged open twice; low
effort.

### Evidence

`STANDALONE_PAGES` in the builder (`scripts/build_static_site.R:77-81`) is the single
source of truth for non-article nav pages:

```r
STANDALONE_PAGES <- tibble::tribble(
  ~id,        ~title,                 ~nav_label,
  "methods",  "Signal & Noise",       "Signal &amp; Noise",
  "aems",     "Inside the AEMS Data", "AEMS"
)
```

But `check_site_consistency.R` — the base-R script CI actually runs — re-hardcodes the
same facts instead of deriving them:

- `check_site_consistency.R:128` — `standalone <- c("aems.html", "methods.html")`
  (the standalone id list, duplicated).
- `check_site_consistency.R:119` — `TOOLS[TOOLS$name == "Signal methods", …]`
  (the tool-name string literal, coupled to a specific row of `tools.R`).

This is called out as unfinished in the DECISION_LOG **twice** on 2026-07-31:
> "`check_site_consistency.R` still hardcodes `standalone` and `"Signal methods"` in
> duplicate of `STANDALONE_PAGES`."
> "`check_site_consistency.R` hardcodes `standalone <- c("aems.html","methods.html")`
> and the literal `"Signal methods"` tool name, duplicating `STANDALONE_PAGES`."

Concrete failure mode: add a third standalone page to `STANDALONE_PAGES` (the documented
way to add a `/`-nav page), and the CI check will **silently skip** scanning it for
draft-article links — the exact drift the check exists to catch — because its
`standalone` list still only names two files. The check would pass while shipping the
regression.

### Proposed change

Have `check_site_consistency.R` derive the standalone id list from the builder's source
of truth rather than restating it. Since the check is deliberately base-R with no `box`
(and `STANDALONE_PAGES` is a plain `tibble::tribble` in `build_static_site.R`), the
low-coupling option is to parse the `STANDALONE_PAGES` block out of `build_static_site.R`
with the same textual approach `load_tribble_file()` already uses (`:27-62`), or to lift
`STANDALONE_PAGES` into a tiny shared data file both scripts read. Then the draft-link
scan (`:129-145`) iterates the derived id list, and the `"Signal methods"` special-case
(`:118-125`) keys off the tool whose `url` resolves to a `/`-path rather than a hardcoded
name.

### Effort estimate

~45 min–1 hr. The riskier-but-cleaner shared-source refactor vs. the quick textual parse;
either is small. Naturally fixed alongside finding #2, since both touch
`check_site_consistency.R`.

### Risk

Low. Test surface is the check script itself, not the site. Verify by adding a throwaway
third `STANDALONE_PAGES` row locally and confirming the check now scans it, then reverting.

---

## Also noted (not in the top 3)

- **Three finished draft analyses are written but unpublished.** `articles/` contains
  complete Quarto sources `aav-gene-therapy-liver.qmd` (12 KB),
  `glp1-alopecia.qmd` (13 KB), and `carbidopa-levodopa-b6-seizures.qmd` (17 KB), all still
  `status = "draft"` in `app/logic/articles.R:19-30` with no rendered `app/static/<id>.html`.
  Publishing is human-gated (reMarkable review per `articles/proposals/ARTICLE_QUEUE.md`),
  so this is not an agent-actionable fix — but it is real shipped-authoring capacity sitting
  behind a render+approve step. Flagged so the queue isn't forgotten.
- **`REDESIGN_FRONTEND.md` brand facts vs. the live hero.** The homepage hero copy is the
  generic "Open tools for pharmacovigilance signal detection and clinical research
  acceleration" (`build_static_site.R:284`), while the decided brand tagline is *"Know
  before it becomes a headline."* (`REDESIGN_FRONTEND.md:9`, §1). Prior reviews (07-15,
  07-22) rightly judged the *three-audience page structure* (§2) superseded by the
  weekly-article strategy — but the **tagline and brand hierarchy in §1 are not part of
  that superseded structure**; they are standing brand decisions. New reasoning for
  raising it now: with the correctness backlog cleared and production caught up (2026-07-30),
  a one-line hero copy change is a genuinely marginal, near-zero-risk improvement, and it
  lands naturally in the same `site_head`/`build_index` edit as finding #1. Left off the
  top 3 only because it is a copy decision for the author, not a defect.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Add OG/Twitter/canonical meta + `sitemap.xml` + `robots.txt` to the builder | Discoverability / user-facing | ~1.5–2 hr | Low |
| 2 | Make the dead-link guard actually block, and have CI scan all pages for missing targets | Correctness / consistency | ~1–1.5 hr | Low |
| 3 | De-duplicate `STANDALONE_PAGES` / tool name out of `check_site_consistency.R` | Maintainability (known-open) | ~45 min | Low |
