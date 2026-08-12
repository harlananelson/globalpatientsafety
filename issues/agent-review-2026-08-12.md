# Agent review — 2026-08-12

Weekly reflection for globalpatientsafety.com. **Report-only** — this file is the
only change; nothing is built, deployed, or otherwise modified.

## Scope and what has already shipped

Production is the static site (`scripts/build_static_site.R` → `static_site/` →
nginx); `app/logic/{articles,tools}.R` are the registries; the Rhino app is
archived. This is the first review since 2026-07-29 (the 08-05 slot was skipped).

Before proposing anything I checked that the four prior reviews' findings are
**actually landed**, not just proposed (they were merged as PR #9 per
`issues/IMPLEMENTATION-2026-07-30-claude-prs.md`), so I do not re-raise them:

- "Signal methods" card is now `status = "live"`, `url = "/methods"`
  (`app/logic/tools.R:24-25`). ✅
- Articles index filters to published (`build_articles_index()` iterates
  `published`, `build_static_site.R:345`). ✅
- AEMS page no longer links the draft articles — `app/static/aems.html` now links
  only `/christine_cotton` and `/methods` (verified by grep; DECISION_LOG
  2026-08-07). ✅
- A base-R consistency check + CI job exist
  (`scripts/check_site_consistency.R`, `.github/workflows/site-checks.yml`). ✅
- CLAUDE.md rewritten around the static builder; VAERS is a live tool. ✅

The `ajax-error.md` / `signal-disconnection.md` issues are `aers-mobi`/`faers-mobi`
triage, not portal work, and are not re-litigated here.

The three items below are **new** and each cites specific files/lines. Two of them
are the exact "Still open" items the DECISION_LOG itself flags on 2026-07-30 and
2026-07-31.

---

## 1. The production build is never run in CI, and the dead-internal-link guard only warns — so the guard added to stop the AEMS→draft 404 gives no protection on push/PR

**Severity:** correctness/process on the production surface. Highest leverage this
week — it re-arms a safety net that is currently disconnected.

### Evidence

Three facts compound:

1. **CI runs only the base-R consistency check, never the builder.**
   `.github/workflows/site-checks.yml` has a single job whose only step is
   `Rscript --vanilla scripts/check_site_consistency.R`. `build_static_site.R` is
   never executed in CI.

2. **The builder's link guard only warns; it never fails.**
   `check_internal_links()` ends with `warning(...)` + `cat("WARNING: ...")`
   (`scripts/build_static_site.R:479-486`) — no `stop()`, no non-zero exit. Yet the
   function's own header comment claims the opposite:
   `scripts/build_static_site.R:444-446` — *"…and warn when the target file is
   missing… **Fails hard** on zero targets that look like article/standalone
   slugs…"*. The documented contract ("fails hard") and the behavior ("warn and
   continue") disagree. Even a local `Rscript build_static_site.R` exits 0 with a
   dead link present.

3. **The base-R check that *does* run in CI does not cover this case.** Its
   dead-link scan is limited to two hardcoded standalone files
   (`scripts/check_site_consistency.R:128` — `standalone <- c("aems.html",
   "methods.html")`) and only looks for links to *draft* ids
   (`check_site_consistency.R:127-145`). A published article whose HTML links to a
   nonexistent or draft slug — the exact shape of the July AEMS→`carbidopa`/`glp1`
   404 that motivated the guard — is scanned on `aems.html`/`methods.html` only,
   never on `christine_cotton.html`, `shingles.html`, or `covid_vaccine.html`.

Net: the "durable, prevents recurrence" link check proposed in review 2026-07-29 §1
and recorded as landed exists in the builder, but the builder isn't in CI and the
check doesn't fail — so on a push or PR, nothing catches a dead internal link in a
rendered article. The protection reads as present but is inert.

### Proposed change

Pick one of two paths (the first is smaller and stays base-R):

- **Extend the CI check (recommended).** In `check_site_consistency.R`, replace the
  hardcoded 2-file draft scan with a loop over **every** `app/static/*.html` that
  the registries actually ship, and flag any `href="./slug"` / `href="/slug"` whose
  `slug` is neither a published article id, a standalone id, nor `index`/`articles`.
  `fail()` (exit 1) on a hit. This makes the one job CI runs cover all shipped
  pages with no new dependency. (This also subsumes Finding 3's coverage half.)
- **Or run the builder in CI** and make `check_internal_links()` honor its own
  docstring: `stop()` on broken links (optionally behind a `STRICT=1` env so a
  deliberately-unrendered standalone during a WIP render doesn't wedge the build).
  This needs `tibble`/`dplyr`/`stringr` on the runner, which the current base-R job
  deliberately avoids — heavier, hence the recommendation above.

Either way, reconcile the `build_static_site.R:444-446` comment with the actual
behavior so the next reader isn't misled about "fails hard."

### Effort estimate

~45–60 min for the base-R extension (one loop + reuse the existing regex/`fail`
helpers) plus a manual red-path check (temporarily point a `published` article's
HTML at a bogus slug and confirm exit 1). ~1.5 hr for the run-the-builder path
because of the CI dependency setup.

### Risk

Low. Tightening a check can only reject builds that are actually broken today. The
one real risk is a false positive on an `href` the regex misclassifies (e.g. an
asset or in-page anchor) — mitigate by reusing the existing allow-list
(`index`, `articles`, `#about`, published + standalone ids) already present at
`check_site_consistency.R` and `build_static_site.R:468-469`.

---

## 2. The homepage renders the featured article twice — once as the "Start here" card, once as the first "Recent articles" card

**Severity:** user-facing polish; small, one-line fix.

### Evidence

`build_index()` builds two independent blocks from `published`:

- **Featured** — `featured <- published |> filter(featured == TRUE) |> slice(1)`
  (`scripts/build_static_site.R:72`), rendered as the prominent "★ Start here" card
  (`build_static_site.R:257-270`).
- **Recent** — `recent_articles <- published |> arrange(desc(date)) |> head(3)`
  (`scripts/build_static_site.R:277`), rendered as the three-card "Recent articles"
  row (`build_static_site.R:278-281`), with **no exclusion of the featured id**.

Today the featured article is `aems` (`app/logic/articles.R:21-24`,
`status = "published", featured = TRUE`), and `aems` is also the newest published
piece (`2026-07-14`, vs `christine_cotton` `2026-06-13`, `shingles` `2026-05-12`).
So `aems` is the featured "Start here" card **and** the first card in the Recent row
immediately below it — the same title, subtitle, and `/aems` link shown twice on
one screen. This is not hypothetical; it is the live homepage state after the
2026-08-07 splash refocus (DECISION_LOG 2026-08-07 made `aems` featured).

### Proposed change

Exclude the featured id when selecting recent cards, e.g. at
`scripts/build_static_site.R:277`:

```r
recent_pool <- if (nrow(featured)) published |> filter(id != featured$id[1]) else published
recent_articles <- recent_pool |> arrange(desc(date)) |> head(3)
```

This surfaces one additional real article (`covid_vaccine`, currently the 4th by
date) instead of repeating the hero, giving the homepage four distinct articles
rather than three-plus-a-duplicate.

### Effort estimate

~10 min (one line + a rebuild eyeball of `static_site/index.html`).

### Risk

Very low. Pure selection logic; when no featured article exists the expression
falls back to today's behavior. Confirm the Recent row still shows 3 cards after
the change.

---

## 3. `check_site_consistency.R` duplicates the builder's `STANDALONE_PAGES` and the "Signal methods" tool name as hardcoded literals — the DECISION_LOG's own standing open item

**Severity:** maintainability/consistency; a drift trap for the next editor.

### Evidence

The DECISION_LOG flags this twice, unresolved:

- 2026-07-30 — *"`check_site_consistency.R` still hardcodes `standalone` and
  `"Signal methods"` in duplicate of `STANDALONE_PAGES`."*
- 2026-07-31 — *"Still open. `check_site_consistency.R` hardcodes
  `standalone <- c("aems.html","methods.html")` and the literal `"Signal methods"`
  tool name, duplicating `STANDALONE_PAGES` in the builder."*

Confirmed in the current code:

- `scripts/check_site_consistency.R:118-124` special-cases the literal tool name
  `TOOLS$name == "Signal methods"` and the literal path `app/static/methods.html`.
- `scripts/check_site_consistency.R:128` hardcodes
  `standalone <- c("aems.html", "methods.html")`.
- The builder's single source of truth for these pages is
  `scripts/build_static_site.R:77-81` (`STANDALONE_PAGES` tribble:
  `methods`, `aems`).

The two lists are maintained by hand in two files. Add a third standalone page (say
a future `/glossary`) to `STANDALONE_PAGES` and the consistency check keeps passing
while never validating it — the check silently under-covers exactly the surface it
exists to guard. The `"Signal methods"` string coupling is more brittle still: the
prior reviews floated renaming that card to "Signal & Noise" to match the nav label
(2026-07-15 §1, 2026-07-22 §2); if that rename ever happens, the special-case at
`check_site_consistency.R:119` silently stops firing and the card→`methods.html`
invariant goes unchecked.

### Proposed change

Make the check derive its standalone set instead of restating it. Two options,
either fine:

1. Have `check_site_consistency.R` read the standalone ids from the builder's
   `STANDALONE_PAGES` — parse them out the same textual way it already parses the
   tribbles (`load_tribble_file`), so there is one list.
2. Or drop the file-name and tool-name literals entirely and generalize: validate
   the card→page invariant for **every** `live` tool whose `url` is a same-site
   `/slug` (the loop at `check_site_consistency.R:99-116` already does exactly this
   for live tools — the separate `"Signal methods"` special-case at 118-124 is
   redundant with it and can likely just be deleted), and scan **every** shipped
   `app/static/*.html` for draft/dead links (this is the coverage half of
   Finding 1).

Option 2 removes code rather than adding it and folds cleanly into Finding 1's fix;
recommend doing them together.

### Effort estimate

~30–45 min, base-R only, no new dependency. Most of it is re-verifying the check
still passes on the current tree and fails on a planted violation.

### Risk

Low. It only changes a build-time validator, never the deployed site. Keep the
existing `fail()`/`ok()` semantics so CI output stays readable; run the script once
against the current tree to confirm it still exits 0.

---

## Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Make CI actually catch dead internal links (builder not run; guard only warns; check covers 2 of 6 pages) | Correctness / process | ~45–60 min | Low |
| 2 | Stop rendering the featured article twice on the homepage (`build_static_site.R:277`) | User-facing polish | ~10 min | Very low |
| 3 | De-duplicate `check_site_consistency.R`'s hardcoded standalone list + "Signal methods" literal (DECISION_LOG open item) | Maintainability | ~30–45 min | Low |

Findings 1 and 3 are complementary and share a fix surface (`check_site_consistency.R`);
doing them in one pass is the efficient path. Finding 2 is independent and the
quickest win.

### Noted, not proposed (context for next week)

- **Three fully-written draft analyses are stalled unrendered.**
  `articles/aav-gene-therapy-liver.qmd` (12 KB), `articles/carbidopa-levodopa-b6-seizures.qmd`
  (16 KB), and `articles/glp1-alopecia.qmd` (13 KB) are complete sources, but their
  `status = "draft"` rows (`app/logic/articles.R:25-36`) have **no** rendered
  `app/static/<id>.html`, so they are neither built nor checked. Publishing is
  human-gated (reMarkable review, per 2026-07-29 §1), so this is not a code proposal
  — but the bottleneck is the review, not the writing; the mechanical render step is
  unblocked whenever approval lands.
- **Repo hygiene (public repo).** The two article *sources* for the published
  `covid_vaccine` and `shingles` pieces live at the repo root
  (`covid_vaccine_vaers_analysis.qmd`, `shingles_vaccine_analysis.qmd`) while every
  other article source lives under `articles/`, and a stale 4.8 MB rendered
  `covid_vaccine_vaers_analysis.html` is committed at root (md5 differs from the
  shipped `app/static/covid_vaccine.html`; nothing references it). `articles/.gitignore`
  already ignores `*.html` for exactly this reason; the root has no such rule. A
  small cleanup (move the two sources into `articles/`, git-rm the orphan render,
  extend the ignore rule) would remove ~4.8 MB of dead weight and the source-location
  inconsistency — flagged for a dedicated hygiene pass, not bundled into the fixes above.
</content>
</invoke>
