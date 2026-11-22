# Agent review — 2026-10-28

Weekly reflection for globalpatientsafety.com. Top 3 proposed improvements this
week, each anchored to specific files/lines. **Report-only** — nothing here is
deployed, and no files other than this one are modified.

## Scope and what has already shipped

Production is the static site built by `scripts/build_static_site.R` and rsync'd
to nginx (CLAUDE.md "Overview"). The three roadmap docs the prompt names mostly
target **sibling repos, not this one**, so I did not re-propose from them:

- `SEARCH_REDESIGN.md` is a `faers.mobi` change — its whole implementation table
  (`SEARCH_REDESIGN.md:865-876`) edits `faers-mobi/app/view/signal_timeline.R`,
  `faers-mobi/api/plumber.R`, etc. Not this repo.
- `NOVELTY_FILTER_ROADMAP.md` Round 2 is explicitly "needs offline data prep in
  signal-compute" and lives in `aers-mobi` / `faers-mobi` / `signal-compute`
  (`NOVELTY_FILTER_ROADMAP.md:42-48`, `:864-876`). Not this repo.
- `REDESIGN_FRONTEND.md` (three-audience patient/researcher/pharma pages) is a
  large, strategic, human-gated redesign dated 2026-05-03; the medication-input
  patient tool "doesn't exist yet" (`REDESIGN_FRONTEND.md:271`). Out of scope for
  a one-file weekly nudge.

**Status of prior `issues/agent-review-*.md` proposals** (the four July reviews,
most recent `agent-review-2026-07-29.md`):

- 2026-07-29 #1 (dead `carbidopa`/`glp1` links on `aems.html` + a build link
  check): **done.** `grep` finds no `href` to any draft id in `app/static/aems.html`,
  and `check_internal_links()` now exists in `build_static_site.R:509-556`.
- 2026-07-29 #2 ("Signal methods" card → live `/methods`): **done.**
  `app/logic/tools.R:24-25` is now `status = "live"`, `url = "/methods"`.
- 2026-07-29 #3 (reconcile CLAUDE.md + CI with the static site being production):
  **partially done.** CLAUDE.md now documents the static-vs-Shiny split and lists
  `build_static_site.R`. But part 3 of that proposal — "add a CI job that runs
  `build_static_site.R` and the link-integrity check" — was **not** done, and the
  machine-access layer built since (Sept–Oct) is undocumented. Proposals 1 and 2
  below carry that forward with new, more specific reasoning rather than repeating
  the generic ask.

---

## 1. CI never builds the production site, and the dead-link guard that exists only warns — so a broken link or missing machine-access page ships silently

**Severity:** correctness / release safety on the production artifact. This is the
unfinished half of 2026-07-29 #3, plus a defect in the guard that was added.

### Evidence

Three facts combine so that the production build is effectively unguarded in CI:

1. **CI runs only the registry check, never the builder.**
   `.github/workflows/site-checks.yml` has one job whose one step is
   `Rscript --vanilla scripts/check_site_consistency.R`. Nothing runs
   `scripts/build_static_site.R`.

2. **The consistency check's machine-access half silently no-ops in CI.**
   `scripts/check_site_consistency.R:153-157`: if `static_site/index.html` is
   absent it prints `"static_site/ not present; machine-access markers are checked
   after a local build"` and `quit(status = 0)` — skipping every check at
   `:158-184` (homepage machine-access markers; existence of `robots.txt`,
   `sitemap.xml`, `llms.txt`, `openapi.json`, `api.md`, `mcp.md`, `pipeline.md`,
   `accessibility.html`, …; and that `openapi.json` describes `/pipeline`). But
   `static_site/` is gitignored build output (`.gitignore:7`), so in a fresh CI
   checkout it is **always** absent. The entire second half of the script only
   ever runs on a developer's machine after a manual local build.

3. **The dead-internal-link guard only warns, contrary to its own header.**
   `build_static_site.R:512-513` states the check "Fails hard on zero targets that
   look like article/standalone slugs," but the implementation calls `warning()`,
   not `stop()` (`build_static_site.R:546-552`). A build with a dead `/<slug>`
   link still exits 0 and writes `static_site/`, ready to rsync.

Net: the exact recurrence-prevention the 2026-07-29 review asked for exists in
code but gates nothing. A published article whose HTML is missing is still caught
(the registry check at `:75-82` runs in CI), but a dead *internal link* in prose,
a renamed standalone page, or a machine-access page that failed to generate (e.g.
`gps_pipeline.py --openapi` producing nothing — `static_site_access.R:124`) would
reach the VPS with no CI failure.

### Proposed change

Add a second CI job to `site-checks.yml` that actually exercises the production
path:

1. Install R + `tibble`/`dplyr`/`stringr` + `python3` (the builder shells out to
   `scripts/polish_html.py` and `scripts/gps_pipeline.py --openapi`).
2. Run `Rscript scripts/build_static_site.R`.
3. Re-run `Rscript --vanilla scripts/check_site_consistency.R` — now that
   `static_site/` exists, its machine-access block (`:158-184`) actually fires.

And make the link guard enforce its own contract: change `warning()` to `stop()`
in `check_internal_links()` (or honor a `GPS_STRICT=1` env the CI job sets), so a
dead internal slug fails the build. Keep the local-dev run a warning if the
maintainer prefers, but CI should be strict.

### Effort estimate

~1–1.5 hr. Mostly the workflow YAML (an R job that needs a few CRAN packages and
python3 is the fiddly part); the `warning`→`stop` flip is one line.

### Risk

Low, and it only *tightens* the gate. The one real risk is a flaky CRAN/python
install making CI slower or occasionally red on infra, not on content — pin the
`setup-r` action's package cache as the existing job pattern allows. No runtime or
deploy behavior changes; the builder still writes the same `static_site/`.

---

## 2. CLAUDE.md documents the static site but omits the entire machine-access / pipeline surface — which is now the homepage's primary CTA

**Severity:** doc consistency; a trap for the next contributor (human or agent),
the same failure mode as 2026-07-29 #3 but for the layer built *after* that review.

### Evidence

Since July the repo grew a large "machine path" surface, recorded across the
Sept–Oct DECISION_LOG and the recent git history (`bc855aa "Add the
ClinicalTrials.gov pipeline and the machine-access pages"`, `fa5c1a8`, `6ebd047`,
`de61c45`, `589d847`). It is now front-and-center in the UI:

- The homepage hero's only button is `Pipeline analysis` → `/pipeline`
  (`build_static_site.R:340`), and `/pipeline` is the first nav item after Home
  on every page (`build_static_site.R:202`).
- A whole file, `scripts/static_site_access.R` (378 lines), builds `robots.txt`,
  `sitemap.xml`, `llms.txt`, `openapi.json`, `api.{md,html}`, `mcp.{md,html}`,
  `chatgpt.md`, `accessibility.{md,html}`, and per-page Markdown twins. It is
  `source()`d by the builder at `build_static_site.R:565-566`.
- `scripts/gps_pipeline.py` backs the `/pipeline` endpoint and emits the OpenAPI
  spec; the MCP story points at `https://faers.mobi/mcp` (`static_site_access.R:180-208`).
- `scripts/monitor_faers_mobi.sh`, `scripts/monitor_heartbeat.sh`, and
  `scripts/claims_audit.sh` are an entire monitoring/self-audit apparatus
  (DECISION_LOG 2026-09-18 entries).

None of this is in CLAUDE.md. Its "Key Files" table lists `build_static_site.R`,
`articles.R`, `tools.R`, `check_site_consistency.R`, `site-checks.yml`, and the
archive — but not `static_site_access.R`, `gps_pipeline.py`, or the monitor
scripts. Its "Tool Suite" table lists faers.mobi / aers.mobi / pico-dag / VAERS /
Signal methods / MAUDE — but **not the ClinicalTrials.gov Pipeline analysis**, the
very thing the homepage hero now sends every visitor to. The "Development" section
also doesn't mention that the build now requires `python3` (for `polish_html.py`
and `gps_pipeline.py --openapi`), so a contributor following CLAUDE.md's build
steps on a python-less shell gets a build that `stop()`s at
`static_site_access.R:124-125`.

### Proposed change

Edit `CLAUDE.md` only:

1. Add a "Machine / LLM access" subsection under Architecture describing
   `/pipeline`, `/api`, `/openapi.json`, `/llms.txt`, the markdown twins, and the
   MCP pointer to faers.mobi, naming `scripts/static_site_access.R` and
   `scripts/gps_pipeline.py` as the producers.
2. Add `static_site_access.R`, `gps_pipeline.py`, and the monitor/`claims_audit.sh`
   scripts to the Key Files table.
3. Add a "Pipeline analysis — ClinicalTrials.gov registry lookup, `/pipeline`" row
   to the Tool Suite table.
4. Note the `python3` build dependency in the Development section.

### Effort estimate

~30–45 min. Pure documentation; no code or build change.

### Risk

Very low. Docs-only. The only "risk" is drift if the machine layer keeps moving —
mitigated by keeping the description at the level of "what exists and which file
owns it," not endpoint-by-endpoint detail (that already lives in `api.md`).

---

## 3. Every page's `<meta name="description">` leads with API boilerplate, pushing the human-readable description out of search snippets and social cards

**Severity:** user-facing / SEO; small and high-leverage (one line).

### Evidence

`build_static_site.R:113-115`:

```r
site_head <- function(title, description = "", page = "/") {
  md <- if (identical(page, "/")) "/index.md" else paste0(page, ".md")
  desc <- paste(MACHINE_SENTENCE, description)
```

`MACHINE_SENTENCE` (`build_static_site.R:108-111`) is:

> "Machine path: GET /pipeline?sponsor= on this site, and GET https://faers.mobi/signals for FAERS signals."

Because `site_head()` prepends it to the real `description` for **every** page it
renders (index, articles index, every article, and — via
`static_site_access.R:287-288` the same sentence opens the `/api` body), the
`<meta name="description">` of the homepage is:

> "Machine path: GET /pipeline?sponsor= on this site, and GET
> https://faers.mobi/signals for FAERS signals. Open tools for pharmacovigilance
> signal detection and clinical research acceleration. CDC VAERS and FDA FAERS …"

The `<meta name="description">` tag is the one field whose audience is **humans** —
it is what Google and social cards show as the result snippet. The machine
audience is already served, redundantly, by the visible "LLM / API access" banner
(`build_static_site.R:163-175`), the `<link rel="alternate" href="/llms.txt">` and
`rel="service-desc" href="/openapi.json"` head links (`:124-125`), and `llms.txt`
itself. So the one human-facing description field now opens with a `curl`-shaped
sentence on ~13 pages, truncating the actual pitch in a ~155-char snippet.

I take this to be a side effect of the 2026-10-10 "handshake" machine-discovery
push (the comment at `build_static_site.R:107` — "First sentence of every
description names the machine path"), applied to the wrong field: discoverable to
crawlers, but at the cost of the human snippet.

### Proposed change

In `build_static_site.R`, stop prepending `MACHINE_SENTENCE` to the
`<meta name="description">`. Options, least invasive first:

1. Emit the human `description` as the `<meta name="description">`, and put the
   machine sentence in its own tag instead, e.g.
   `<meta name="x-machine-path" content="…">` — keeps crawler-visible, drops it
   from the snippet. (~2 lines.)
2. Or simply drop it from the meta entirely; the banner + `rel="alternate"` links
   + `llms.txt` already carry it. (~1 line.)

Keep the `/api` page's visible mention (`static_site_access.R:288`) — that one is
on-page body text for a machine-facing page and is appropriate there.

### Effort estimate

~10–15 min plus a rebuild. One-line change in `site_head()`.

### Risk

Low, but confirm intent with Harlan first: if a specific crawler/LLM workflow was
relying on the machine sentence being in `<meta name="description">`
specifically (not the banner or llms.txt), option 1 preserves a machine-readable
tag while fixing the human snippet. Worth one check against the DECISION_LOG
handshake entry before changing.

---

### Summary

| # | Proposal | Type | Effort | Risk |
|---|----------|------|--------|------|
| 1 | CI builds the site + runs the (now-firing) machine-access checks; make the dead-link guard `stop()` not `warn` | Release safety / correctness | ~1–1.5 hr | Low |
| 2 | Document the machine-access / pipeline surface in CLAUDE.md (Key Files, Tool Suite, python3 dep) | Doc consistency | ~30–45 min | Very low |
| 3 | Stop prepending the machine sentence to `<meta name="description">` so the human snippet survives | User-facing / SEO | ~10–15 min | Low |
