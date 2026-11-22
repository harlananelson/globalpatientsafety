# Agent review — 2026-10-21

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Environment note

`Rscript` and `quarto` are not installed in this review container (only
`python3`), so I could not run `scripts/build_static_site.R` or
`scripts/check_site_consistency.R`. Everything below is from reading the source
plus running the one suite I could: `scripts/test_gps_pipeline.py` (offline,
no network) — **15/15 pass** via `python3 -m unittest`.

## Status of prior reviews (not re-proposed)

The last weekly review was `issues/agent-review-2026-07-29.md` (≈12 weeks ago).
All three of its items are now resolved, verifiable in the current tree:

1. **Dead AEMS links → fixed.** `app/static/aems.html` now links only to
   `/christine_cotton` (published) and `/methods` (standalone); the two draft
   targets are gone. `scripts/check_site_consistency.R:127-145` now hard-fails
   on any `href` from `aems.html`/`methods.html` to a `draft` article, and
   `scripts/build_static_site.R:513-556` warns on dead same-site links.
2. **"Signal methods" card → fixed.** `app/logic/tools.R:24-25` is now
   `status = "live", url = "/methods"`; `check_site_consistency.R:118-125`
   guards against it regressing to `coming_soon`.
3. **CLAUDE.md ↔ static site → partially fixed, now superseded.** CLAUDE.md was
   reconciled to describe the static build as production and lists the VAERS
   tool. But a whole new subsystem has since landed undocumented — that is
   Proposal 1 below, a *new* instance of the same class of problem, not a
   re-proposal.

The `issues/*-2026-09-*.md` files are inbound-handshake feature specs for the
sibling `faers-mobi`/`vaers` services (API params, MCP tools, novelty filter);
the machine-access work they describe appears shipped in `static_site_access.R`
and `gps_pipeline.py`. `NOVELTY_FILTER_ROADMAP.md` Round 2 (canonical signal
math / adaptive Gamma prior) remains open but is explicitly `signal-compute` /
`faers-mobi` work, out of this repo's scope, so it is not proposed here.

---

## 1. The new `/pipeline` + machine-access subsystem is undocumented in CLAUDE.md and unlogged in DECISION_LOG

**Severity:** maintainability / doc consistency — a trap for the next contributor
(human or agent), on the largest feature addition since July.

### Evidence

Seven commits between 2026-10-10 and 2026-10-16 added a public HTTP service and a
machine-access layer:

- `bc855aa` "Add the ClinicalTrials.gov pipeline and the machine-access pages",
  `589d847` "Use port 3845 for the pipeline service", `de61c45` "Default the
  pipeline sponsor search to the lead sponsor", `fa5c1a8`, `6ebd047`, `36da40a`,
  `1a49d98`.

The product of those commits:

- `scripts/gps_pipeline.py` — an **828-line public HTTP service** answering
  `GET /pipeline?sponsor=…` (ClinicalTrials.gov proxy), run as a separate process
  (`--bind 127.0.0.1 --port 3845`, `gps_pipeline.py:1-18`), i.e. **not a static
  file** — it needs nginx to route `/pipeline` to it on the VPS.
- `scripts/static_site_access.R` — sourced by the builder
  (`build_static_site.R:565-566`) and emits `robots.txt`, `sitemap.xml`,
  `llms.txt`, `openapi.json` (via `gps_pipeline.py --openapi`), `api.{md,html}`,
  `mcp.{md,html}`, `chatgpt.md`, `accessibility.{md,html}`, and a Markdown twin
  per page.
- This is now wired into **every built page**: `build_static_site.R:108-111`
  (`MACHINE_SENTENCE`), `:177-216` (`/pipeline` nav link), `:340` (hero's primary
  CTA is `/pipeline`), `llm_banner()` (`:163-175`).

Yet the documentation of record does not mention any of it:

- **CLAUDE.md "Key Files" table** lists only `build_static_site.R`,
  `app/logic/articles.R`, `app/logic/tools.R`, `app/static/<id>.html`,
  `check_site_consistency.R`, `site-checks.yml`, `archive/`. It omits
  `scripts/gps_pipeline.py`, `scripts/static_site_access.R`,
  `scripts/polish_html.py`, and the `scripts/monitor_*` watchdogs.
- **CLAUDE.md "Tool Suite" / architecture** says nothing about the `/pipeline`
  endpoint, the `openapi.json`/`llms.txt`/hosted-MCP machine surface, or the
  fact that a second long-running process (the Python service) now exists on the
  VPS alongside nginx. CLAUDE.md still frames this domain as "zero R workers …
  static files served by nginx," which is now only *half* true.
- **DECISION_LOG.md** — whose most recent entries (2026-09-18, around line 2958)
  are a multi-day exercise in record-keeping discipline ("after claiming a fix,
  grep the file for it before writing the claim down") — has **no 2026-10 entry
  at all** (`grep -nE '^#+ 2026-10' DECISION_LOG.md` → empty). The single biggest
  feature since July shipped with the log silent, which is exactly the gap that
  discipline was meant to close.

A next agent reading CLAUDE.md would not know the pipeline service exists, that
it is a separate process, which port it binds, or how `/pipeline` reaches it —
and would likely assume `/pipeline` is a dead nav link.

### Proposed change

1. CLAUDE.md: add `scripts/gps_pipeline.py` and `scripts/static_site_access.R`
   (and the `monitor_*`/`polish_html.py` helpers) to the Key Files table; add a
   short "Pipeline analysis & machine access" section stating that `/pipeline` is
   served by the Python service on `127.0.0.1:3845` behind nginx, that the
   build emits `llms.txt`/`openapi.json`/`api`/`mcp`/`accessibility`, and that
   `openapi.json` comes from `gps_pipeline.py --openapi`. Correct the "zero R
   workers" framing to "static HTML + one Python pipeline process."
2. DECISION_LOG: add a backfill entry for the 2026-10-10→16 pipeline /
   machine-access / VAERS-API work (even a terse one), restoring the log's
   continuity.

### Effort estimate

~45–60 min (documentation only; all facts are already in the commits/files).

### Risk

Very low — touches no runtime code or deploy path.

---

## 2. The `/pipeline` HTTP service has zero CI coverage

**Severity:** correctness/regression risk on a public, contract-pinned endpoint;
small, high-leverage fix.

### Evidence

- `.github/workflows/site-checks.yml` runs exactly one step:
  `Rscript --vanilla scripts/check_site_consistency.R`. Nothing else runs on
  push/PR.
- `scripts/gps_pipeline.py` is **828 lines** serving the public `/pipeline`
  endpoint, and `scripts/test_gps_pipeline.py` has **15 offline unittest cases**
  covering the contract that matters: `status=ALL` vs ongoing default, `role`
  lead/collaborator/any, invented-NCT-id dropping, `400` on unknown
  `format`/`role`, `502`/`503` on upstream error/timeout (never an empty 200),
  and the HTML/brief/JSON content-negotiation. I ran them in this container:
  `cd scripts && python3 -m unittest test_gps_pipeline` → **`Ran 15 tests … OK`**.
- Those tests run **only by hand**. A change to the service's parameter contract
  can land on `main` green, because CI never executes them.
- This is not hypothetical coupling: `openapi.json` (shipped by the build and
  asserted present by `check_site_consistency.R:173-183`) is generated by
  `gps_pipeline.py --openapi` (`static_site_access.R:121-126`), and the external
  monitor "compares the live openapi enum against the live validator"
  (DECISION_LOG, 2026-09-17). A silent service regression therefore surfaces only
  in production monitoring, not in CI.

### Proposed change

Add a second job (or step) to `site-checks.yml` that runs the Python suite:

```yaml
  pipeline-tests:
    name: Pipeline service tests
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: python3 -m unittest discover -s scripts -p 'test_*.py' -v
```

Optionally also assert the schema builds:
`python3 scripts/gps_pipeline.py --openapi | python3 -m json.tool >/dev/null`,
mirroring the consistency check's `/pipeline`-in-openapi marker.

### Effort estimate

~20–30 min. The tests are already green and fully offline (no ClinicalTrials.gov
calls), so there is nothing to stub.

### Risk

Very low — additive CI only; cannot affect the deployed site.

---

## 3. The machine sentence pollutes every human `<meta name="description">`

**Severity:** user-facing (SEO / social snippets); small, specific fix.

### Evidence

`scripts/build_static_site.R:108-115` prepends a fixed machine sentence to the
description of every shell page, and `site_head()` writes the result straight
into the human description meta:

```r
MACHINE_SENTENCE <- paste(
  "Machine path: GET /pipeline?sponsor= on this site, and",
  "GET https://faers.mobi/signals for FAERS signals."
)
...
desc <- paste(MACHINE_SENTENCE, description)   # build_static_site.R:115
...
<meta name="description" content="%s">         # build_static_site.R:121
```

`site_head()` builds `index.html`, `articles.html`, and (via
`static_site_access.R::shell_page`) `api.html`/`mcp.html`/`accessibility.html`.
So the homepage's `<meta description>` — the text search engines and link-preview
cards show to **people** — now reads:

> Machine path: GET /pipeline?sponsor= on this site, and GET
> https://faers.mobi/signals for FAERS signals. Open tools for pharmacovigilance
> signal detection and clinical research acceleration…

The human-readable sentence is pushed past where most engines truncate. The
machine audience is *already* served through its proper channels, all on the same
pages: `robots.txt`, `llms.txt`, `openapi.json`, the visible `.llm-access` banner
(`build_static_site.R:163-175`), and the `<link rel="alternate"
type="text/markdown">` head link (`:123`). Putting the API path in the human
description meta is redundant for machines and degrades the snippet for humans.

Note the coupling: `check_site_consistency.R:159-166` asserts `index.html`
contains the literal `"Machine path:"`, and that string currently lives **only**
in the meta description on the homepage — so this cannot simply be deleted
without also moving the marker.

### Proposed change

Use the human `description` directly in `site_head()`'s meta
(drop the `MACHINE_SENTENCE` prefix), and surface the machine path where it
belongs and stays CI-guarded — add the "Machine path: …" line as visible text
inside the `.llm-access` banner. Then update the `check_site_consistency.R`
`"Machine path:"` marker to match the banner rather than the meta. Net: humans
get a clean snippet, machines still get the path on the page, CI still guards it.

### Effort estimate

~30 min (two small string changes in `build_static_site.R`, one marker update in
`check_site_consistency.R`); re-run the consistency check after a local build.

### Risk

Low. Confined to generated `<meta>`/banner markup. The only trap is the CI marker
coupling called out above, which the proposed change handles explicitly.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Document the `/pipeline` + machine-access subsystem in CLAUDE.md; backfill DECISION_LOG | Maintainability / doc consistency | ~45–60 min | Very low |
| 2 | Add the Python pipeline test suite (15 cases, already green) to CI | Correctness / regression guard | ~20–30 min | Very low |
| 3 | Stop prefixing the machine sentence onto every human `<meta description>`; move it to the LLM banner | User-facing / SEO | ~30 min | Low |
