# Agent review — 2026-11-11

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Status of prior reviews (not re-proposed)

The most recent prior review is `issues/agent-review-2026-07-29.md`. All three of
its proposals have since been resolved — I verified each against the current tree
rather than assuming:

1. **Dead `carbidopa`/`glp1` links on the AEMS page** — fixed. `app/static/aems.html:3578-3579`
   now link to `/methods` and `/christine_cotton` (both `published`); the draft ids
   are gone. A dead-internal-link guard was also added (`build_static_site.R:509-556`,
   `check_internal_links()`), and `check_site_consistency.R:127-145` now hard-fails if
   `aems.html`/`methods.html` link a draft id.
2. **"Signal methods" card stuck on "Coming soon"** — fixed. `app/logic/tools.R:24-25`
   is now `"Signal methods", "live", "/methods"`.
3. **CLAUDE.md / CI described the retired Shiny app as production** — fixed. CLAUDE.md
   now documents the static build as production, and `rhino-test.yml` is gone;
   `.github/workflows/site-checks.yml` is the only workflow.

The three drafts in `app/logic/articles.R` (`aav_gene_therapy_liver`, `glp1_alopecia`,
`carbidopa_levodopa_b6`) are **still** `draft` and unrendered, and the
one-article-per-week cadence locked in `articles/proposals/ARTICLE_QUEUE.md`
(first publish 2026-07-20) has not produced a single new publication since
`christine_cotton` (2026-06-13). That is a stalled roadmap item, but the bottleneck
is the human reMarkable approval gate (`ARTICLE_QUEUE.md:10-18`), not anything an
agent can move, so it is noted here rather than re-proposed.

The substantive change since the July review is the **ClinicalTrials.gov `/pipeline`
endpoint and the machine-access / LLM surface**, landed 2026-10-10
(`git log` — `bc855aa` "Add the ClinicalTrials.gov pipeline and the machine-access
pages", plus the 2026-10-10 follow-ups). All three proposals below concern that new
surface, because it shipped with gaps in documentation, test coverage, and content.

---

## 1. CLAUDE.md still describes a purely static site — the live `/pipeline` service is undocumented

**Severity:** doc correctness; a deploy-time trap for the next contributor (human or agent).

### Evidence

`/pipeline` is a **dynamic Python service**, not a static file:

- `deploy/gps-pipeline.service` — a systemd unit running
  `python3 /opt/gps-pipeline/gps_pipeline.py --bind 127.0.0.1 --port 3845` as
  `www-data`, `Restart=on-failure`.
- `deploy/nginx-pipeline.snippet` — `location = /pipeline { proxy_pass http://127.0.0.1:3845; ... }`.

It is linked from essentially every page:

- top nav: `build_static_site.R:202` (`<a ... href="/pipeline">Pipeline analysis</a>`)
- homepage hero button: `build_static_site.R:340`
- every article's sticky chrome: `build_static_site.R:443`
- **every page's `<meta name="description">`**, via `MACHINE_SENTENCE`
  (`build_static_site.R:108-111`) prepended to the description in `site_head()`
  (`build_static_site.R:115`): *"Machine path: GET /pipeline?sponsor= on this site…"*

Yet CLAUDE.md describes the domain as static-only and never mentions this service:

- `CLAUDE.md:9` — *"deployed to `/var/www/globalpatientsafety/` on the VPS (nginx,
  **zero R workers**)."* (The service is Python, but the framing is "nothing
  dynamic runs here.")
- `grep -niE 'pipeline|openapi|mcp|llms|systemd|3845|/opt/gps' CLAUDE.md` returns
  only the unrelated `faers-pipeline` data-flow rows. The Architecture table,
  Key Files table, and Deployment section contain **no** `/pipeline`, no
  `gps_pipeline.py`, no `static_site_access.R`, no `deploy/`, no machine-access
  files (`llms.txt`, `openapi.json`, `api.html`, `mcp.html`).
- The Deployment section lists only the `rsync static_site/` step. A contributor
  following CLAUDE.md would **never deploy or restart the service**, so `/pipeline`
  — advertised in every meta description and the nav — would 502/404 while the
  static pages looked fine.

This is distinct from the July review's proposal #3 (static-vs-Shiny framing, now
fixed). This is fresh drift from the 2026-10-10 feature.

### Proposed change

Update CLAUDE.md to document the pipeline service as a first-class part of the
architecture:

- Add a row to the Architecture / Key Files tables for `scripts/gps_pipeline.py`
  (the `/pipeline` service), `scripts/static_site_access.R` (machine-access +
  accessibility page generator), and `deploy/gps-pipeline.service` /
  `deploy/nginx-pipeline.snippet`.
- In the Deployment section, state the **two** moving parts: (a) rsync
  `static_site/`; (b) the systemd service on `127.0.0.1:3845` behind the nginx
  `location = /pipeline` proxy, and how to install/restart it.
- Note that `/pipeline` is the one dynamic endpoint, so "zero workers" is no
  longer literally true.

### Effort estimate

~30–45 min. Pure documentation; the facts are already in `deploy/` and the two
scripts.

### Risk

None to runtime. The only risk is leaving the doc half-updated; keep the
service's port/user/paths copied verbatim from `deploy/gps-pipeline.service` to
avoid introducing a new inconsistency.

---

## 2. CI exercises none of the new dynamic surface — the most complex new code is untested on push/PR

**Severity:** correctness / regression risk; high-leverage.

### Evidence

`.github/workflows/site-checks.yml:28-30` runs exactly one step:
`Rscript --vanilla scripts/check_site_consistency.R`. That is the entire CI.

- **The Python service that backs `/pipeline` has 15 unit tests that CI never
  runs.** `scripts/test_gps_pipeline.py` (`grep -c 'def test_'` → 15) covers
  exactly the breakable logic: invented-NCT-id stripping, unknown-sponsor =
  HTTP 200 empty, timeout = 503 (not empty success), upstream 5xx = 502, the
  HTML/`brief`/`json` format branches, `role` default = lead vs `role=any` vs
  `collaborator`, status defaults, and the 400 paths. None of this is in CI.
- **`build_static_site.R` never runs in CI**, so its dead-internal-link guard
  (`check_internal_links()`, `build_static_site.R:509-556`) and the OpenAPI
  generation (`static_site_access.R:121-126`) are never exercised against a push.
- **The consistency checker's own machine-access checks are dead in CI.**
  `check_site_consistency.R:147-157`: when `static_site/` is absent — which it
  always is in CI, since it is gitignored build output — the script prints
  *"machine-access markers are checked after a local build"* and **exits 0**
  before reaching the marker/file checks at lines 159-184. So in CI only the
  registry↔`app/static` block (lines 64-145) ever runs.

Net: the simplest artifact (the registries) is guarded; the most complex and
most-recently-changed code (the pipeline service + machine-access generation) has
**zero** automated coverage on push/PR.

### Proposed change

Add a second job to `site-checks.yml`:

1. `python3 -m unittest discover -s scripts -p 'test_*.py'` (currently just
   `test_gps_pipeline.py`; `gps_pipeline.py` is import-only with `urllib`, so no
   third-party deps needed — confirm with a dry import in the job).
2. Optionally, a job that installs R + the three build deps
   (`tibble`, `dplyr`, `stringr`) and `python3` + whatever `polish_html.py`
   needs, runs `Rscript scripts/build_static_site.R`, then
   `Rscript --vanilla scripts/check_site_consistency.R` — which this time finds
   `static_site/` present and actually runs the lines 159-184 marker checks and
   the `check_internal_links()` guard. This closes the loop the checker already
   anticipates ("checked after a local build") but nothing automates.

Step 1 is the cheap, high-value half and can ship alone.

### Effort estimate

- Python test job: ~20–30 min (the tests already exist and pass locally with
  `cd scripts && python3 -m unittest test_gps_pipeline`).
- Full build + post-build consistency job: ~1–1.5 hr (the long pole is making
  `polish_html.py`'s Python deps available in the runner).

### Risk

Low. New CI jobs don't touch runtime or deploy. Only risk is a flaky build job if
`polish_html.py` needs a dep not pinned in the repo — mitigated by shipping the
Python-unit-test job first and treating the build job as a follow-up.

---

## 3. Every article's Markdown "twin" is a content-free stub, defeating the advertised LLM/Markdown access

**Severity:** user-/machine-facing content gap on the site's core content.

### Evidence

The site markets a Markdown twin of every page for LLMs/agents:

- `build_llms()` writes `llms.txt` with, for each published article, a line ending
  *"Markdown: https://globalpatientsafety.com/<id>.md"* (`static_site_access.R:100-104`).
- Each article's sticky chrome links **"Markdown" → `/<id>.md`**
  (`build_static_site.R:437`), and `site_head()` emits
  `<link rel="alternate" type="text/markdown" href="/<id>.md">`
  (`build_static_site.R:123`).

But the generated `<id>.md` for an article contains **none of the article's
prose**. In `build_machine_access()` the per-page loop
(`static_site_access.R:371-376`) writes `<id>.md` via
`twin_md(row$title, row$line, row$path)`, and for an article row `row$line` is just
the **subtitle** (`page_rows()`, `static_site_access.R:41-45`). `twin_md()`
(`static_site_access.R:255-270`) emits only: the title, the generic
"Machine path: GET /pipeline?sponsor=" boilerplate, that one subtitle sentence, a
"Full page:" link, and a disclaimer.

So, e.g., `static_site/christine_cotton.md` is ~6 lines and contains the subtitle
but not the analysis — while `christine_cotton.html` is a full Quarto document and
`llms.txt` points an LLM at the `.md` as the machine-readable version. I confirmed
no full-text Markdown is generated anywhere else:
`grep -rniE 'pandoc|--to gfm|to markdown|html2text' scripts/` finds only the
reMarkable **typst** render (`render_remarkable.sh:45`), which is unrelated. The
pipeline/api/mcp/accessibility twins are fine because those pages genuinely are
short — but the articles, the substantive content, are exactly where the stub
hurts.

### Proposed change

Generate real Markdown for article (and standalone) twins instead of the stub.
Two options:

1. **Render from the Quarto source** (cleanest): add a `--to gfm` output to the
   article render step so `app/static/<id>.md` exists alongside `<id>.html`, and
   have `build_machine_access()` copy that into `static_site/<id>.md` (keeping the
   machine header + disclaimer from `twin_md()` as a prepended block) instead of
   writing a stub for ids that have a rendered Markdown source.
2. **Convert the built HTML** (no Quarto dependency at twin time): run the article
   HTML through a lightweight HTML→Markdown step in `polish_html.py`/a helper and
   write that as `<id>.md`.

Either way, keep the current stub behaviour for pages that have no long-form
source (`/api`, `/mcp`, `/accessibility`, `/pipeline`), and only upgrade article/
standalone ids. Then `check_site_consistency.R` could add a check that an
article's `<id>.md` exceeds some minimum length so this can't silently regress.

### Effort estimate

~2–3 hr. Option 1 is a render-flag change plus a copy branch in the twin loop;
option 2 is an HTML→Markdown helper. The twin-loop change in
`static_site_access.R:371-376` is small; the work is the conversion step.

### Risk

Low–medium. Risk is a conversion producing messy Markdown (tables, figures,
footnotes from the Quarto HTML). Mitigate by preferring option 1 (Quarto's own
`gfm` writer) and spot-checking one article before rolling to all.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Document the live `/pipeline` service + machine-access surface in CLAUDE.md | Doc correctness / deploy trap | ~30–45 min | None (doc) |
| 2 | Add CI for `test_gps_pipeline.py` (15 tests) + build/post-build consistency | Test coverage / regression risk | ~20 min–1.5 hr | Low |
| 3 | Generate real Markdown twins for articles instead of subtitle-only stubs | Machine-/user-facing content gap | ~2–3 hr | Low–medium |
