# Agent review — 2026-11-25

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines or DECISION_LOG entries.
**Report-only** — nothing here is deployed, and no files other than this one are
modified.

## Scope and what has already been done

Production is the **static site** built by `scripts/build_static_site.R` and
rsync'd to nginx; the Rhino/Shiny portal is archived under `archive/rhino-app/`.
CLAUDE.md now describes this correctly, so the architecture-drift and
retired-app items from the July reviews are resolved. Spot-checking the prior
`issues/agent-review-2026-07-*.md` picks against the current tree:

- **Resolved:** "Signal methods" card is now `live → /methods`
  (`app/logic/tools.R:24-25`); `christine_cotton` is published and reachable;
  CLAUDE.md names `build_static_site.R` and lists VAERS; the Rhino app and its CI
  are gone; `site_nav()` now gates `/methods` and `/aems` on file existence
  (`build_static_site.R` `available_standalone`); the `carbidopa`/`glp1` dead
  links are gone from `app/static/aems.html` (verified: the only internal hrefs
  now are `/methods`, `/christine_cotton`, `/aems`, all of which resolve).
- **Partially done — the basis of Proposal 1 below:** July review #1 asked for a
  build-time dead-internal-link check. One was added
  (`check_internal_links()`), but it only *warns* and CI never runs it.

None of the three picks below repeats a prior proposal.

---

## 1. The dead-internal-link guard does not actually gate, and CI never runs it

**Type:** correctness / process (regression protection). **Severity:** the exact
failure it is meant to stop has already shipped to production once.

### Evidence

Three facts combine so that a dead same-site link — or a link to a `draft`
article that is never built — can reach the live site with a green CI:

1. **The builder's link check is warn-only.** `scripts/build_static_site.R`
   `check_internal_links()` ends with:
   ```r
   if (length(broken) > 0) {
     warning("Dead internal links in built site:\n  - ", ...)
     cat("WARNING: ", length(unique(broken)), " dead internal link(s) detected.\n", ...)
   } else { cat("  internal-link check: OK\n") }
   ```
   It calls `warning()` + `cat()`, never `stop()`. The build still exits 0. The
   function's own header comment claims it "Fails hard on zero targets that look
   like article/standalone slugs" — that is not what the body does.

2. **CI never runs the builder.** `.github/workflows/site-checks.yml` has one
   step: `Rscript --vanilla scripts/check_site_consistency.R`. The builder (and
   therefore `check_internal_links()`) is never invoked in CI, so even the
   warning is invisible there.

3. **The CI consistency check scans only 2 of the 6 content pages for dead/draft
   links.** `scripts/check_site_consistency.R` hard-codes
   `standalone <- c("aems.html", "methods.html")` and checks only those two files
   for `href` to `draft` ids. The published article pages
   (`christine_cotton.html`, `shingles.html`, `covid_vaccine.html`) are never
   scanned — not for draft links, not for dead internal links at all.

Net failure mode: an editor adds a cross-reference in, say,
`articles/covid_vaccine*.qmd` pointing at `/glp1_alopecia` (a `draft` id in
`app/logic/articles.R`, never built), re-renders to
`app/static/covid_vaccine.html`, and rebuilds. The builder prints a WARNING that
is easy to miss in local output; CI is green because it only looks at
`aems.html`/`methods.html`; the 404 ships. This is precisely the
`carbidopa`/`glp1`-on-`aems.html` break that July review #1 documented — the
guard added in response does not block it.

(There is no *currently* live dead link — all internal hrefs resolve today — so
this is preventive, not a present outage.)

### Proposed change

1. In `check_internal_links()`, collect broken links and `stop()` instead of
   `warning()` (keep the existing allowlist of dynamic routes — `pipeline`,
   `portfolio`, `api`, `mcp`, `accessibility` — and the anchor/asset
   exemptions), so a bad local build fails loudly.
2. In `scripts/check_site_consistency.R`, widen the draft-link scan from the two
   hard-coded standalone files to **every** `app/static/<id>.html` for published
   ids plus the standalones. This is base-R only and runs inside the existing CI
   job with no builder and no new dependencies — the smallest change that closes
   the CI gap.
3. Optional/stretch: add a CI step that runs `build_static_site.R` so the
   production artifact itself is validated on push.

### Effort estimate

~45 min for (1) + (2). The optional CI build step is ~1 hr (needs R + python +
quarto, or a cut-down path that only reads existing `app/static/`).

### Risk

Low. (1) is build-time only. (2) may surface a currently-latent link that is
technically broken — that is the intent; verify a clean local build passes first.
No runtime or deploy-path change.

---

## 2. The featured primer (`aems`) is rendered twice on the homepage

**Type:** user-facing consistency; small, high-leverage. **Severity:** cosmetic
but on the single highest-traffic page.

### Evidence

`scripts/build_static_site.R` `build_index()` builds the featured card and the
"Recent articles" strip from the same pool with no deduplication:

```r
featured <- published |> filter(featured == TRUE) |> slice(1)      # → aems
...
recent_articles <- published |> arrange(desc(date)) |> head(3)     # no exclusion
```

With the current registry (`app/logic/articles.R`), `aems` is both
`featured = TRUE` and the most recent published article (`2026-07-14`, ahead of
`christine_cotton` `2026-06-13` and `shingles` `2026-05-12`). So on `/` the
visitor sees the big "★ Start here" featured card for *Inside the AEMS Data*, and
then the same article again as the first card in the three-up "Recent articles"
row directly below it. One of the three recent slots is spent re-advertising the
featured piece instead of surfacing a fourth distinct article
(`covid_vaccine`, `2026-05-04`).

### Proposed change

Exclude the featured id from the recent list in `build_index()`:

```r
recent_articles <- published |>
  filter(id != featured$id[1]) |>
  arrange(desc(date)) |>
  head(3)
```

(Guard for the `nrow(featured) == 0` case so the filter is skipped when there is
no featured article.) The recent strip then shows `christine_cotton`, `shingles`,
`covid_vaccine` — three distinct pieces.

### Effort estimate

~5–10 min (one expression), picked up automatically on rebuild.

### Risk

Very low. Pure presentation logic on the index page; no template, nav, or
machine-access change.

---

## 3. This domain is publishing inflated EB05 values live via `/portfolio`

**Type:** correctness (numbers shown to users). **Severity:** high — it
undermines the headline quantity the portfolio report ranks on — but the root
cause is upstream (signal-compute / faers.mobi), and the decision to redeploy is
Harlan's.

### Evidence

- `deploy/portfolio.live` **exists**, so `/portfolio` is live on this domain and
  the builder emits its links, docs, and OpenAPI path.
- `scripts/gps_portfolio.py` surfaces numeric EB05 directly to users: HTML at
  `scripts/gps_portfolio.py:926` (`EB05 {_num(sig['eb05'])}`), the text brief at
  `scripts/gps_portfolio.py:1009`, and JSON at `scripts/gps_portfolio.py:585`.
  These values come straight from faers.mobi `/signals`
  (`faers_filters = "...sort=eb05"`, `scripts/gps_portfolio.py:781`), ranked by
  EB05 (`scripts/gps_portfolio.py:514`).
- **DECISION_LOG 2026-11-19 — "The Oct-17 EB05 change, as reported by
  faers-mobi-7d"** documents that signal-compute applies
  `stats::filter(method="recursive")` with 0.3, which computes
  `y[t] = x[t] + 0.3·y[t−1]` — **not** an EWMA. A constant series converges to
  `c/0.7 ≈ 1.43·c`, and faers.mobi publishes `eb05` = the max of that series over
  flagged quarters. On the July data, **92% of pairs have a published eb05 above
  their largest quarterly EB05** (the log's example: tiopronin × Cystinuria,
  5,149.6 vs 4,986.3). The same entry states plainly: *"every EB05 this site
  shows (Portfolio, pipeline, articles that quote faers.mobi) currently carries
  the 1/0.7 inflation."*
- **DECISION_LOG 2026-11-19 — "The Oct-17 signals build is not live"** confirms
  live faers.mobi still serves `signals_faers_v2026-07-08`; the corrected build
  is uncommitted and gated on Harlan's decision (latest-vs-peak for the EWMA fix,
  plus explaining an unexplained 1.72M→568k flagged-pair drop; open items D1–D5
  on the 2026-11-19 reMarkable sheet).

So today, `/portfolio` on globalpatientsafety.com ranks a company's products by,
and prints to users, EB05 numbers that are known to be ~1.43× too high. (The
VAERS articles — `covid_vaccine`, `shingles`, `christine_cotton` — are **not**
implicated: they come from the separate VAERS pipeline, not signal-compute/
faers.mobi. The exposure on this domain is the `/portfolio` endpoint, and any
future FAERS-sourced numbers in the `aems` primer.)

### Proposed change

The fix itself is upstream and is Harlan's call; this repo is the live consumer,
and the actions it controls are:

1. **Keep the weekly portfolio refresh timer disabled** until the corrected
   parquet is live, so the cache is not re-baked from inflated inputs. (The log
   records the timer is installed but not enabled as of 2026-11-18 — confirm it
   is still off.)
2. **Add a dated, removable caveat** to the EB05 descriptions this repo owns —
   `portfolio_api_md()` / the `/portfolio` HTML in `gps_portfolio.py` and
   `api_md()` in `scripts/static_site_access.R` — noting EB05 magnitudes are
   under revision and should be read as relative ranks, not absolute values,
   until the EWMA fix ships. (Rank is largely preserved — the log reports within-
   drug Spearman 0.97–1.00 — so the ranking stays usable while magnitudes don't.)
3. **Treat the upstream fix as an inbound change** per
   `issues/inbound-change-protocol.md`: when faers.mobi redeploys the corrected
   build, re-fill the portfolio cache and capture the old EB05 values before they
   are gone (the log already flags this for the export switch).

### Effort estimate

~15 min to confirm the timer state and draft the caveat text; the caveat edit
itself is ~30 min across the two files. The cache re-fill is a downstream
operation triggered by the upstream deploy, not in-scope to do now.

### Risk

Low for the in-repo caveat (prose only; the page already carries heavy "not
causation / not this company's product alone" disclaimers). The judgment call is
whether to publicly flag the inflation now versus waiting for the imminent fix —
that is Harlan's to make; this proposal is to surface it, not to act unilaterally.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Make the dead-link guard `stop()` and widen the CI draft-link scan to all published pages | Correctness / process | ~45 min | Low |
| 2 | Exclude the featured article from the homepage "Recent articles" strip (no double-render) | Consistency / user-facing | ~10 min | Very low |
| 3 | Surface that `/portfolio` publishes ~1.43× inflated EB05 live; hold refresh, caveat, treat upstream fix as inbound change | Correctness | ~45 min (in-repo parts) | Low |
