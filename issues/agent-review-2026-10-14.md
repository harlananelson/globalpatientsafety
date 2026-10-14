# Agent review — 2026-10-14

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Scope and what has changed since the last reviews

Production is the static site built by `scripts/build_static_site.R` and rsync'd
to nginx (confirmed by the builder header and CLAUDE.md). The in-scope surface for
*this* repo is now: the static builder, the machine-access layer
(`scripts/static_site_access.R`, `llms.txt`, `openapi.json`, the `.md` twins), the
Python pipeline service that backs the live `/pipeline` endpoint
(`scripts/gps_pipeline.py`), and CI. `NOVELTY_FILTER_ROADMAP.md` and
`SEARCH_REDESIGN.md` both target the sibling **faers-mobi** repo (every code path
in SEARCH_REDESIGN cites `faers-mobi/app/view/signal_timeline.R`), so they are not
portal work and are not re-proposed here.

Status of the three items in the most recent prior review
(`issues/agent-review-2026-07-29.md`):

- **#2 (Signal methods card said "Coming soon")** — **resolved.** `app/logic/tools.R:24-25`
  is now `status = "live"`, `url = "/methods"`.
- **#1 (dead `carbidopa`/`glp1` links on the AEMS page)** — **partly resolved.**
  `app/static/aems.html` no longer links to those draft ids, and a general
  dead-link scan (`check_internal_links()`) was added to the builder. But the
  scan does not block — see Proposal 2, which carries that item's "durable
  prevention" half forward with new reasoning.
- **#3 (production surface has no CI; reconcile CLAUDE.md)** — **doc half resolved**
  (CLAUDE.md now describes the static build as production), **CI half still open**,
  and now more material because a large machine-access + Python surface has landed
  since. See Proposal 1.

None of the dense `issues/*-2026-09-*.md` specs (signals API, MCP, llms.txt,
ChatGPT actions) overlap with the three below.

---

## 1. CI never builds the static site or runs the pipeline tests — the production artifact and the live `/pipeline` backend ship unverified

**Severity:** correctness / release safety. The deployed surface and the live
API backend have effectively zero automated coverage, while a passing test suite
for the backend already exists and simply isn't wired in.

### Evidence

- `.github/workflows/site-checks.yml` defines exactly one job, which runs only
  `Rscript --vanilla scripts/check_site_consistency.R`. It never runs
  `scripts/build_static_site.R` and never runs any Python.
- `scripts/check_site_consistency.R:147-157` short-circuits: if
  `static_site/index.html` is absent it prints
  `"static_site/ not present; machine-access markers are checked after a local build"`
  and `quit(status = 0)`. `static_site/` is gitignored build output and CI never
  builds it, so in CI this branch is **always** taken. The entire machine-access
  validation block below it never executes in CI:
  - `check_site_consistency.R:158-172` — homepage markers (`href="/pipeline"`,
    `id="main"`, `"Machine path:"`, etc.).
  - `check_site_consistency.R:173-179` — existence of 11 shipped machine files
    (`robots.txt`, `sitemap.xml`, `llms.txt`, `openapi.json`, `api.md`,
    `chatgpt.md`, `mcp.md`, `methods.md`, `pipeline.md`, `accessibility.html`,
    `api.html`).
  - `check_site_consistency.R:180-183` — that `openapi.json` actually describes
    `/pipeline`.
  So the only thing CI guards is registry ↔ `app/static` drift
  (`check_site_consistency.R:64-145`).
- The live `/pipeline` endpoint is served by `scripts/gps_pipeline.py`, and that
  same script generates the shipped `openapi.json` (`static_site_access.R:121-126`
  calls `python3 gps_pipeline.py --openapi`). Its test suite
  `scripts/test_gps_pipeline.py` has **15 offline tests** covering the 502/503
  outage contract, the 400-on-bad-input contract, role/status filtering, and the
  "drop invented NCT ids" guarantee. I ran it this session:
  `python3 -m unittest test_gps_pipeline` → **15 passed in 0.005s**, no network.
  Nothing in `.github/workflows/` runs it, so a regression in the live API
  contract (or in the OpenAPI spec that ships to clients) would pass CI silently.

This is the open half of 2026-07-29 #3, with the new facts that (a) a machine
surface and a Python backend were added in the interim and (b) a fast, offline,
already-green test suite for that backend exists and is trivial to wire in.

### Proposed change

Add a second job (or two steps) to `site-checks.yml`:

1. **Python:** `python3 -m unittest discover -s scripts -p 'test_*.py'` (or pin
   `test_gps_pipeline`). No extra deps, no network.
2. **Build + full consistency:** set up R 4.4, install `tibble`, `dplyr`,
   `stringr`, run `Rscript scripts/build_static_site.R`, then re-run
   `Rscript --vanilla scripts/check_site_consistency.R`. Because `static_site/`
   now exists, the machine-access block (lines 158-184) finally runs.
   **Quarto is not needed** — the builder reads the committed `app/static/*.html`;
   it only needs R + `python3` (for `polish_html.py` and `gps_pipeline.py --openapi`),
   both already required by step 1.

### Effort estimate

~1–1.5 hr. The Python step is ~5 min (suite is green and offline). Most of the
time is the R setup + confirming the builder runs clean on a fresh runner.

### Risk

Low — CI-only, no runtime/deploy change. The one thing to confirm on a clean
runner is that `build_static_site.R` completes without the archived rhino/`box`
stack; the builder already strips `box::use` textually
(`build_static_site.R:49-66`) specifically to avoid that dependency, so it should.

---

## 2. The builder's dead-internal-link check advertises "fails hard" but only warns — the general guard is toothless

**Severity:** correctness / consistency (comment contradicts behavior) plus a
real gap: dead internal links cannot fail a build or (today) CI.

### Evidence

- `scripts/build_static_site.R:511-512` (header of `check_internal_links()`):
  *"Fails hard on zero targets that look like article/standalone slugs (not
  anchors or assets)."*
- The implementation does not fail. On finding broken links it calls `warning()`
  and prints a `WARNING:` line (`build_static_site.R:546-552`), then returns. An
  Rscript `warning()` does **not** set a non-zero exit status, and it is the last
  step in the run (`build_static_site.R:567`), so the build exits 0 regardless.
- The only *hard* dead-link gate anywhere is the narrow check in
  `check_site_consistency.R:127-145`, which inspects **only** `aems.html` and
  `methods.html` and **only** for links to `status = "draft"` article ids. A dead
  link in an article body, or a link to a slug that simply doesn't exist (not a
  draft), is caught by neither gate — the builder would only warn, and CI does not
  run the builder (Proposal 1).

This is the "durable prevention" recommendation from 2026-07-29 #1. The scan was
added but left non-blocking, so the recurrence it was meant to stop can still
reach production.

### Proposed change

Make `check_internal_links()` authoritative:

- Collect `broken` as it already does, and when non-empty, `stop()` (non-zero
  exit) instead of `warning()`, so the build fails and — once Proposal 1 lands —
  CI fails with it.
- Before flipping, confirm the `known` allowlist (`build_static_site.R:519-523`:
  `index`, `articles`, `pipeline`, `api`, `mcp`, `accessibility`, published ids,
  standalone ids) covers every legitimate single-segment same-site link. Note the
  matching regex (`build_static_site.R:531`) only captures slugs with no `.`, so
  `/llms.txt`, `/openapi.json`, `/api.md`, `/mcp.md` and the `.md` twins are
  already excluded and will not trip the gate.

### Effort estimate

~30 min: one `warning()` → `stop()` plus a dry run of the builder to confirm the
allowlist is complete (I could not run it here — no R in this environment).

### Risk

Low–moderate. The only failure mode is a *valid* build being rejected because the
allowlist misses a legitimate slug; the pre-flight check above removes that risk.
This is exactly why it is proposed rather than applied blind.

---

## 3. The homepage hero's only call-to-action is `/pipeline` — the weakest value proposition — while the flagship tools and the "Start here" primer sit below the fold

**Severity:** user-facing; small, high-leverage presentation fix.

### Evidence

- `scripts/build_static_site.R:336-342` renders the hero with a single button:
  `<p class="mb-0"><a class="btn" href="/pipeline">Pipeline analysis</a></p>`.
  There is no other CTA in the hero.
- `/pipeline` is a ClinicalTrials.gov registry lookup whose own copy frames it as
  *"Registry facts, not a safety conclusion"* (`scripts/static_site_access.R:29`;
  the `/pipeline` page `.md` and `llms.txt` repeat the caveat). It is the newest,
  most-caveated, least safety-relevant feature on the site.
- CLAUDE.md frames the site as the **clearing house** for the pharmacovigilance
  tool suite (faers.mobi, VAERS, pico-dag) and the methodology articles. The
  builder even has special handling to label the featured AEMS primer
  *"★ Start here — how we read the data"* (`build_static_site.R:295-298`), yet that
  primer card and the Tools grid both render in later `<section>`s
  (`build_static_site.R:300-358`) with no hero CTA pointing to them.

Net effect for a first-time human visitor: the single most prominent action on
the landing page routes to the feature the project itself describes as not a
safety conclusion, while faers.mobi and the "Start here" primer require a scroll.
(The `/pipeline`-forward framing is clearly intentional for *machines* — every
meta description leads with the `MACHINE_SENTENCE` at `build_static_site.R:108-111`
— but that rationale does not transfer to the human hero button.)

### Proposed change

Give the hero a primary CTA to the flagship surface and demote `/pipeline` to a
secondary link. Two low-effort options in `build_index()`:

- Primary button → the featured "Start here" primer (`/` already computes
  `featured$id`, e.g. `/aems`), or → the Tools section anchor; keep a smaller
  secondary "Pipeline analysis" link beside it. ~5 lines of template.

Worth a one-line confirmation with Harlan that the `/pipeline`-only hero was not a
deliberate recent choice; if it was, this can be closed as working-as-intended.

### Effort estimate

~15 min (template edit in `build_index()`, then rebuild).

### Risk

Very low — purely presentational, same-origin links, no data or deploy impact.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | Run the builder + the (green, offline) `gps_pipeline` tests in CI so the production artifact and the live `/pipeline` backend are actually verified | Correctness / release safety | ~1–1.5 hr | Low |
| 2 | Make `check_internal_links()` `stop()` instead of `warning()` so dead internal links fail the build/CI (its header already claims it does) | Correctness / consistency | ~30 min | Low–moderate |
| 3 | Give the homepage hero a primary CTA to the flagship tools / "Start here" primer instead of only `/pipeline` | User-facing | ~15 min | Very low |
