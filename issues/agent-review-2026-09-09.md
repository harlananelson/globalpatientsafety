# Agent review — 2026-09-09

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines or DECISION_LOG entries.
**Report-only** — no file other than this one is modified, and nothing is deployed.

## Status of the earlier reviews (not re-proposed)

Every concrete finding from `agent-review-2026-07-08` … `-07-29` has since landed
(see `issues/IMPLEMENTATION-2026-07-30-claude-prs.md` and DECISION_LOG 2026-07-30/31):

- "Signal methods" card is now `live → /methods` (`app/logic/tools.R:24`).
- The retired Rhino/Shiny app was archived to `archive/rhino-app/`, so the
  `app/main.R` / `article_christine_cotton` / dead-index-card findings are moot —
  `app/` now holds only `logic/` registries and `static/` HTML.
- CLAUDE.md was rewritten around the static builder; the `drug`/`event` schema and
  the VAERS tool row are correct.
- CI gained `scripts/check_site_consistency.R` (`.github/workflows/site-checks.yml`).
- The AEMS page's two draft-article links were replaced with live `/methods` and
  `/christine_cotton` links (DECISION_LOG 2026-08-07); I re-scanned every file in
  `app/static/` this week and found **no** remaining dead internal links.

So none of the above is re-proposed. The three items below are new. Two of them
(#1, #3) build directly on that now-clean baseline; #2 is the stalled roadmap item
that the most recent log entries leave open.

---

## 1. The site ships a "Copy link" share button but no social-preview or SEO metadata — every shared article link renders as a bare URL

**Type:** user-facing gap in the portal. **Severity:** high for a site whose entire
current strategy is publishing shareable weekly articles and making a good first
impression on visitors (incl. MSSO).

### Evidence

- The builder deliberately adds a share affordance to every article/standalone page:
  `scripts/build_static_site.R:386` (`NAV_INJECTION`) renders a **"Copy link"**
  button (`navigator.clipboard.writeText(location.href)`). Sharing is a designed
  feature.
- But `site_head()` (`scripts/build_static_site.R:107-136`) emits only three meta
  tags — `charset`, `viewport`, and a single `<meta name="description">`
  (`:112-114`). There is **no** `og:title` / `og:description` / `og:image` /
  `og:url` / `og:type`, no `twitter:card`, and no `<link rel="canonical">`.
- The article and standalone pages are worse: `build_article_pages()`
  (`:393-410`) and `build_standalone_pages()` (`:415-431`) never call `site_head()`
  at all — they just prepend `NAV_INJECTION` to the raw Quarto HTML. Confirmed on the
  shipped files: `grep -oE 'property="og:[a-z]+"|name="twitter:[a-z]+"|rel="canonical"'`
  over `app/static/*.html` returns **nothing** (the only `og:` substrings are the
  Bootstrap-icon class `bi-cloud-fog`). So the exact pages users are invited to
  copy-and-paste have zero social metadata.
- Consequence: a link pasted into X/Twitter, LinkedIn, Slack, iMessage, or WhatsApp
  renders with no title card, no summary, no image — just the raw URL. For a project
  whose editorial plan is "one article every Monday" with a review/approval pipeline
  (`articles/proposals/ARTICLE_QUEUE.md`) and whose splash was refocused specifically
  to look credible to an outside licensor (DECISION_LOG 2026-08-07 "Splash refocused
  on the AEMS primer (MSSO-visitor framing)"), the missing preview is a direct hit to
  reach and to first impressions.
- Separately, there is **no `sitemap.xml` and no `robots.txt`** anywhere in the build
  output or `app/static/` (checked). A public content site with a stable page set and
  a publishing cadence has nothing telling search engines what exists.

### Proposed change

All inside `scripts/build_static_site.R`, self-contained:

1. Extend `site_head()` to take the page's canonical path + image and emit
   `og:title/description/url/type/image`, `twitter:card=summary_large_image`, and a
   `<link rel="canonical">`. Pass real values from `build_index()` /
   `build_articles_index()`.
2. Give article/standalone pages the same treatment. Since those pages reuse the
   Quarto `<head>` rather than `site_head()`, inject the OG/twitter/canonical block
   (built from the `ARTICLES`/`STANDALONE_PAGES` row: `title`, `subtitle` →
   `og:description`, `/<id>` → `og:url`/canonical) with a `sub("(</head>)", …)`
   splice in `build_article_pages()`/`build_standalone_pages()`, mirroring the
   existing `<body>` splice at `:405` / `:427`.
3. Add a tiny `build_sitemap()` (index + `/articles` + `published$id` +
   `available_standalone$id`) writing `static_site/sitemap.xml`, and a static
   `robots.txt` pointing at it. Both use lists the builder already has in memory.
4. One share image: a single default `og:image` (e.g. a site card in
   `app/static/`) is enough to start; per-article images can come later.

### Effort estimate

~1.5–2 hours: ~1 hr for the OG/twitter/canonical helper threaded through the three
builders, ~20 min for sitemap/robots, plus a rebuild and a validator pass
(e.g. paste a built page URL through a card-preview debugger after deploy).

### Risk

Low. Additive `<head>` content and two new static files; no change to existing page
bodies or routing. Main care point: `og:url`/canonical must use the absolute
`https://globalpatientsafety.com/<id>` form (the clean-URL nginx paths the site
already relies on), not a relative path.

---

## 2. The MedDRA/MSSO subscription is the top stalled roadmap item, and its next step is now cheap and concrete ($139/yr) — it just needs to be executed

**Type:** stalled roadmap item with a clear next step; unblocks multiple gated
features. **Severity:** medium-high (it is the single dependency gating the site's
next content lane).

### Evidence

The most recent three log entries are all about this thread, and they leave it
**open with an explicit ordered next step** — the definition of a stalled item worth
surfacing:

- DECISION_LOG 2026-08-17 ("MSSO replied: individual = COMMERCIAL subscription,
  $139/yr"): the eligibility question that stalled this for months is **resolved and
  cheap** — an individual buys a Commercial **Level 0** subscription at **$139
  USD/year**, no 501(c)(3) or non-profit verification. To invoice, MSSO needs "a
  signed statement in **PDF**, stating income or confirming it is below $1M USD."
- The same entry lists the concrete next actions, in order: **(1)** open the full,
  un-clipped MSSO reply and check whether question 3 (may hierarchy groupings / SMQ
  membership be *publicly displayed*) was answered — the saved copy ends at Gmail's
  "[Message clipped]"; **(2)** if absent, reply asking Q3 alone; **(3)** send the
  signed income PDF and pay the $139 invoice ("Worth doing regardless … a precondition
  for the hierarchy data either way").
- What it unblocks (DECISION_LOG 2026-08-07 "MedDRA/MSSO subscription letter SENT",
  the gated-work table): **D2** — PT → HLT/HLGT/SOC hierarchy walk; the **non-clinical
  / low-information PT badge** in triage; and **SOC-level / SMQ-level public views**.
  These are the three things standing between today's PT-only presentation and the
  richer methodology surface the editorial plan wants
  (`articles/proposals/ARTICLE_QUEUE.md`, "methodology first" section; the AEMS page's
  whole thesis is "the raw leaderboard lies," which SOC/SMQ grouping directly supports).

Nothing currently published depends on this, so there is no fire — but that is exactly
why it has sat: it is unblocked, cheap, and un-owned. The eligibility unknown that
justified waiting is gone.

### Proposed change

Execute the log's own three steps. Note the actual correspondence and the signed PDF
live in the private repo (`globalpatientsafety-private:correspondence/meddra/`) and
Gmail, per DECISION_LOG 2026-08-17 — so this is not a code change in *this* repo, and
the deliverable here is only to flag it as the top stalled item and (once done) record
the outcome in `DECISION_LOG.md`. Split the two halves:

- **Immediately doable, no dependency:** send the signed income statement (PDF, income
  < $1M) and pay the $139 invoice — unblocks D2/hierarchy regardless of the Q3 answer.
- **Blocking the public-display features:** get a definitive Q3 answer (open the
  un-clipped reply; if silent, send the one-line Q3 follow-up) before shipping any
  SOC/SMQ or hierarchy-derived view. Do **not** treat the clipped/silent Q3 as
  permission — the log is explicit on this.

Also (2-minute correctness fix flagged in the same entry): the `.claude/` memory note
should record that the individual path is **Commercial Level 0**, not non-commercial.

### Effort estimate

~30 min of correspondence + a $139 payment for the unblocking half; the D2/hierarchy
build that follows is a separate, larger piece (sibling data work, out of scope here).

### Risk

Low, and asymmetric: paying is cheap and reversible-in-effect; the only real risk is
publishing hierarchy/SMQ groupings before Q3 is answered in writing, which the staged
split above avoids.

---

## 3. The dead-internal-link guard added in July is toothless: it only `warning()`s, and CI never runs the build that contains it

**Type:** correctness / consistency; a guard that does not do the job it was added
for. **Severity:** medium — it is latent today (link scan is clean) but it is the
exact class of bug — a shipped 404 on an article link — that it was created to prevent.

### Evidence

- The July work added `check_internal_links()` specifically to stop a recurrence of
  the AEMS-page 404s (see `issues/IMPLEMENTATION-2026-07-30-claude-prs.md`, row "No
  dead-internal-link guard"). But the function **only warns** — it never fails:
  `scripts/build_static_site.R:479-489` calls `warning(...)` + `cat("WARNING: …")` and
  returns; the build still exits 0 with dead links present. A `warning()` in a long
  build log is easy to miss in a manual `Rscript scripts/build_static_site.R` run,
  which is the only time it fires.
- CI does **not** run the build at all. `.github/workflows/site-checks.yml` runs only
  `Rscript --vanilla scripts/check_site_consistency.R` (base-R, by design, to avoid
  the `tibble`/`dplyr`/`stringr` deps). So `check_internal_links()` never executes in
  CI — the production artifact (`build_static_site.R` → `static_site/`) has **no**
  build-time validation on any push or PR.
- The base-R consistency check does *not* cover the same ground. It scans only
  `aems.html` and `methods.html`, and only for links to **draft** article ids
  (`scripts/check_site_consistency.R:127-145`). It does not scan the article bodies
  (`christine_cotton.html`, `covid_vaccine.html`, `shingles.html`) for internal
  `href`s, and does not catch a link to a *typo'd* or *removed* published slug. So a
  future article that links to, say, `/glp1_alopecia` (still `draft`,
  `app/logic/articles.R:29`) from within `covid_vaccine.html` would ship a 404 with a
  green CI.

### Proposed change

Close the loop the July guard was meant to close, two low-risk parts:

1. **Make the guard bite.** In `build_static_site.R`, have `check_internal_links()`
   (`:446-489`) `quit(status = 1)` (or `stop()`) when `broken` is non-empty, so a
   dead link fails the build instead of printing a warning. Keep the informative
   message.
2. **Run it where CI can see it.** Either add a second CI job that runs the full
   `build_static_site.R` (accepting the `tibble`/`dplyr`/`stringr` install cost), or —
   cheaper and consistent with the base-R design — extend
   `check_site_consistency.R` to scan **all** shipped `app/static/*.html` for
   single-segment internal `href`s and fail on any slug that is not a published
   article id or an available standalone id (it already parses both registries in
   base R at `:64-73`). The second option keeps CI dependency-free.

### Effort estimate

~30–45 min: a few lines to escalate the warning, plus ~20 min to add a base-R href
scan to the consistency check (the registry parsing it needs already exists there).

### Risk

Low. The scan is read-only over built/shipped HTML. The one care point is
false positives: constrain the match to true same-site single-segment slugs
(exclude anchors, assets like `favicon.ico`, and absolute-URL hosts), exactly as the
existing `check_internal_links()` regex already does (`:462-469`).

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Add Open Graph / Twitter / canonical meta + sitemap.xml + robots.txt to the builder | User-facing / SEO | ~1.5–2 hr | Low |
| 2 | Execute the MSSO subscription next step ($139 + Q3), unblocking D2 / SOC-SMQ / non-clinical badge | Stalled roadmap | ~30 min + $139 | Low |
| 3 | Make the dead-link guard fail the build and run in CI (base-R href scan) | Correctness / CI | ~30–45 min | Low |
