# Agent review — 2026-11-04

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Scope and prior-review status

The deployed surface is the static site (`scripts/build_static_site.R` →
`static_site/` → nginx) plus the machine-access layer added over Sept–Oct 2026
(`scripts/static_site_access.R`: `/api`, `/mcp`, `llms.txt`, `openapi.json`,
Markdown twins) and the dynamic `/pipeline` service (`scripts/gps_pipeline.py`).

Items from earlier `issues/agent-review-*.md` that are now **resolved** (not
re-proposed):

- **Dead `carbidopa_levodopa_b6` / `glp1_alopecia` links on the AEMS page**
  (2026-07-29 #1): fixed. `app/static/aems.html` now links only to
  `/christine_cotton` and `/methods`, both of which build.
- **"Signal methods" card stuck on *Coming soon*** (2026-07-15 #1, 2026-07-22 #2):
  fixed. `app/logic/tools.R:24-25` is now `status = "live"`, `url = "/methods"`.
- **CLAUDE.md / CI misrepresenting the retired Rhino app as production**
  (2026-07-15 #2, 2026-07-29 #3): reconciled. CLAUDE.md now frames the static
  build as production and the Rhino app as archived; nav links are coupled to
  `available_standalone` so a skipped render can't ship a dead nav link.

The large backlog under `issues/*-2026-09-*.md` is almost entirely **faers-mobi /
API-handshake / monitor** work on sibling repos, not portal work, so it is not
re-proposed here.

The **one** 2026-07-29 recommendation that was *not* finished is "give production
a CI test." It is picked up as Proposal 1 below, with materially new evidence: the
machine-access surface now exists and is entirely unguarded in CI.

---

## 1. CI never builds the site, so every machine-access consistency check silently no-ops and a broken builder ships undetected

**Type:** correctness / CI coverage. **Severity:** high — the production artifact
and the whole LLM/agent surface have no automated gate.

### Evidence

- `.github/workflows/site-checks.yml:30` runs only
  `Rscript --vanilla scripts/check_site_consistency.R`. Nothing in CI runs
  `scripts/build_static_site.R`.
- `scripts/check_site_consistency.R:153-157`: the machine-access block is guarded
  by `if (!file.exists(index_html)) { ok("static_site/ not present; …"); quit(status = 0) }`.
- `.gitignore:7` lists `static_site/` as build output. The CI checkout therefore
  never contains `static_site/`, and CI never builds it — so that early-exit
  branch is **always** taken in CI. The entire machine-access block that follows
  (`check_site_consistency.R:158-184`: homepage markers, and the presence of
  `robots.txt`, `sitemap.xml`, `llms.txt`, `openapi.json`, `api.md`, `chatgpt.md`,
  `mcp.md`, `methods.md`, `pipeline.md`, `accessibility.html`, `api.html`, plus
  the `openapi.json` → `/pipeline` check) **never executes in CI.**
- Consequence: the Sept–Oct machine-access work (built by
  `scripts/static_site_access.R`) has **zero** CI coverage, and a change that
  breaks the builder itself is invisible until a human runs it locally — e.g. a
  `stop()` in `load_tribble` (`build_static_site.R:52-56`), a `polish_html.py`
  failure (`build_static_site.R:460`), or `gps_pipeline.py --openapi` producing
  nothing (`static_site_access.R:124`).
- The builder's own dead-link guard, `check_internal_links()`
  (`build_static_site.R:513-556`), was added after 2026-07-29, but it only
  `warning()`s (lines 546-552) — it never `stop()`s — and it isn't run in CI, so
  it gates nothing. A deploy proceeds over a warning.

### Proposed change

1. Add a second job to `site-checks.yml` that installs `tibble`, `dplyr`,
   `stringr` and `python3` (stdlib only — `polish_html.py` imports just
   `html`/`re`/`sys`; `gps_pipeline.py --openapi` is offline, `openapi_spec()` at
   `gps_pipeline.py:723`), runs `Rscript scripts/build_static_site.R`, then runs
   `check_site_consistency.R` again. With `static_site/` now present, the
   machine-access block at lines 158-184 actually runs.
2. Make `check_internal_links()` fatal — `stop()` instead of `warning()` — or gate
   it on an env flag CI sets, so a dead internal link fails the build.

Keep the existing base-R-only job as-is; add the build job alongside it.

### Effort estimate

~1–1.5 hr. Heavier than the deliberately dependency-light base-R job (the `dplyr`
install is the main cost), which is why it was deferred; `r-lib/actions/setup-r` +
`setup-r-dependencies` handle it.

### Risk

Low–moderate. The only new flakiness source is R package install time;
`--openapi` is fully offline, so there is no network dependency in the build.

---

## 2. Every published article advertises a Markdown twin, but the twin is only the subtitle — not the article

**Type:** user-facing gap for the machine/LLM audience the recent work courts.
**Severity:** medium — the promise and the payload diverge on the site's
distinctive lane.

### Evidence

- `scripts/static_site_access.R:255-270` `twin_md()` emits only: the title, the
  machine-path sentence, a single `line`, a "Full page:" URL, and the disclaimer.
- `static_site_access.R:371-376`: the twin loop writes `<id>.md` for every row
  from `page_rows()`. For published articles, `page_rows()` sets
  `line = published$subtitle` (`static_site_access.R:39-47`). So, e.g.,
  `christine_cotton.md` is ~8 lines of title + subtitle + disclaimer — none of
  the article body.
- It is advertised as real content in three places:
  - `build_static_site.R:123` — `<link rel="alternate" type="text/markdown" href="/<page>.md">` on every page head;
  - `article_chrome()` (`build_static_site.R:429-451`) puts a "Markdown" link to `/<id>.md` on every article page;
  - `llms.txt` (`static_site_access.R:101-104`) lists each page with "Markdown: https://globalpatientsafety.com/<id>.md".
- The whole recent stream (llms.txt, MCP, OpenAPI, Markdown twins) is built for
  LLM/agent consumers. An agent that follows the advertised per-article Markdown
  for "Tested Against VAERS: Christine Cotton…" receives the subtitle, not the
  analysis — the exact content it was pointed at.

### Proposed change

Either:

- **(a) Serve real article Markdown.** Emit `static_site/<id>.md` from the article
  body in the build — the Quarto/pandoc already in the render path can produce
  `.md` alongside `.html`, or add a small HTML→Markdown pass over the Quarto body
  in `polish_html.py`. The existing `<id>.md` links then resolve to the real
  piece. Or
- **(b) Stop over-promising.** If full-article Markdown is deliberately out of
  scope, drop the per-article `/<id>.md` link from `article_chrome` and the
  "Markdown:" clause for article rows in `llms.txt`, so what is advertised matches
  what is served. (The page-level `<link rel="alternate">` can stay for the
  genuine twins like `/api.md`, `/pipeline.md`.)

Recommend (a): per-article Markdown is exactly the asset the machine-access push
is for.

### Effort estimate

(a) ~2–4 hr — wire a converter and verify output on the ~1.5 MB Quarto pages.
(b) ~30 min.

### Risk

(a) moderate — converting large Quarto HTML can yield noisy Markdown; validate a
sample before shipping. (b) low — pure removal of an over-promise.

---

## 3. The only draft/dead-link guard that runs in CI inspects 2 of the 5 shipped HTML pages

**Type:** consistency / correctness coverage hole. **Severity:** low-now,
medium-latent — it is the guard that would catch a recurrence of the 2026-07-29
dead-link bug, and it is half-blind.

### Evidence

- `scripts/check_site_consistency.R:127-145`: the hard-failing draft-link check
  iterates `standalone <- c("aems.html", "methods.html")` (`:128`) only. The three
  published article pages — `christine_cotton.html`, `shingles.html`,
  `covid_vaccine.html` — are never scanned for links to draft articles or for dead
  internal links.
- The 2026-07-29 #1 bug was precisely an article page recommending sibling
  articles that were still `draft`. Cross-references between articles are routine
  here, and there are three live drafts to trip over —
  `aav_gene_therapy_liver`, `glp1_alopecia`, `carbidopa_levodopa_b6`
  (`app/logic/articles.R:25-36`). A published article linking to any of them would
  404 in production and **pass CI.**
- Confirmed **latent, not active**: a grep across all five shipped pages
  (`app/static/{christine_cotton,shingles,covid_vaccine,aems,methods}.html`) for a
  link to any draft id returns nothing today. This is a coverage hole waiting for
  the next cross-referenced article, not a current outage.
- The builder's broader `check_internal_links()` (`build_static_site.R:513-556`)
  would catch it, but only warns and isn't in CI (see Proposal 1).

### Proposed change

In `check_site_consistency.R`, replace the hardcoded `standalone` list at `:128`
with every shipped HTML stem — the published article ids plus the standalone ids —
i.e. scan `app/static/<id>.html` for `id` in `c(published$id, "aems", "methods")`.
Stays base-R-only, needs no new dependencies and no builder run. It is the cheap
complement to Proposal 1 for keeping the CI job dependency-light: if the full
build job (Proposal 1) is not adopted, this still closes the specific recurrence
hole across all pages.

### Effort estimate

~20 min.

### Risk

Very low — a base-R string scan over files already on disk, hard-failing only on a
link to a `draft` id (the same rule already applied to 2 files, widened to 5).

---

## Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Build the site in CI (machine-access checks currently no-op) + make the link check fatal | Correctness / CI | ~1–1.5 hr | Low–moderate |
| 2 | Serve real per-article Markdown, or stop advertising a Markdown twin that is only the subtitle | User-facing (machine audience) | ~0.5–4 hr | Low–moderate |
| 3 | Widen the in-CI draft/dead-link guard from 2 shipped pages to all 5 | Consistency | ~20 min | Very low |
