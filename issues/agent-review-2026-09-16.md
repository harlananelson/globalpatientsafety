# Agent review — 2026-09-16

Weekly reflection on the **globalpatientsafety.com portal / clearing-house repo**.
Report-only: every proposal cites specific files/lines. No file other than this one
is modified, and nothing is deployed.

## Scope and what has changed since the last review

The production surface of this repo is the static site built by
`scripts/build_static_site.R` and rsync'd to nginx (`build_static_site.R:17-19`);
the Rhino/Shiny portal was retired and archived (`archive/rhino-app/`,
DECISION_LOG `2026-07-30`). Findings below are portal-local.

**Prior `issues/agent-review-*.md` status (not re-proposed):**

- `agent-review-2026-07-15` #1 and `agent-review-2026-07-29` #2 — "Signal methods"
  tool card stuck on `coming_soon`: **fixed.** `app/logic/tools.R` now ships it
  `live` → `/methods`, and `check_site_consistency.R:118-125` guards the regression.
- `agent-review-2026-07-29` #1 — dead `href="./carbidopa_levodopa_b6"` /
  `"./glp1_alopecia"` links in `app/static/aems.html`: **fixed.** Those links are
  gone (`aems.html` now links only `/christine_cotton` and `/methods`), the
  build-time `check_internal_links()` guard was added (`build_static_site.R:446-489`),
  and `check_site_consistency.R:127-145` fails on any draft-article href in the
  standalone pages.
- `agent-review-2026-07-08` / `-07-22` — dead "Read" paths in the Rhino portal
  (`app/main.R`, `article_christine_cotton.R`): **moot.** That app is archived; the
  files those reviews cite no longer exist under `app/`.

**Not re-proposed because out of this repo's scope:** the ~40 `issues/*-2026-09-*.md`
tickets (llms.txt, `/api`, OpenAPI, MCP, bot homepage, brief/PDF formats, idle
timeout) are **handshake tickets for the sibling `faers-mobi` repo** — each says
"Implement in `/projects/faers-mobi/`" and "Do not merge this GPS PR"
(e.g. `issues/llms-txt-2026-09-12.md`, `issues/linux-implementer-handoff-2026-09-13.md`).
This repo is only the coordination surface for them. The three findings below are
about the portal repo's *own* code, which has not been touched since ~August.

---

## 1. The umbrella landing site has no machine/LLM discoverability, while the entire tool suite's strategy this quarter has been LLM-first

**Severity: medium — user-facing gap, and a strategic inconsistency the site can close cheaply.**

### Evidence

Every September ticket in `issues/` has been about making **faers.mobi** legible to
LLM agents: a public `/llms.txt` (`issues/llms-txt-2026-09-12.md`), `/openapi.json`,
`/api`, hosted `/mcp`, a bot-UA markdown homepage
(`issues/bot-homepage-brief-link-2026-09-13.md`), and serving those bodies as
`text/plain` so restricted fetchers accept them (`issues/markdown-as-text-plain-2026-09-15.md`).

But **globalpatientsafety.com — the front door that the GitHub org and CLAUDE.md
present as the "clearing house" for the whole suite — has none of it:**

- `scripts/build_static_site.R` emits exactly `index.html`, `articles.html`, the
  article pages, the standalone pages, and `favicon.ico` (`build_static_site.R:493-498`).
  There is **no `robots.txt` and no `llms.txt`** produced or shipped. An LLM fetcher
  or crawler that lands on the apex domain gets a Bootstrap HTML page and no
  machine-readable pointer to anything.
- The tool cards still describe the apps as interactive-only. `app/logic/tools.R:19-21`
  gives faers.mobi the tagline *"Current FAERS (2018-2024): time-stratified Bayesian
  and frequentist disproportionality…"* — no mention that it now exposes a public
  `GET /signals` REST API, an OpenAPI schema, and an MCP endpoint. A developer or
  agent reading the landing page cannot discover the API that the last month of work
  built.
- The `site_head()` template hard-codes a single generic `<meta name="description">`
  (`build_static_site.R:107-136`) and emits no `<link rel="alternate">`, no
  structured data, and no per-page description — the same discoverability weakness the
  faers.mobi team is actively fixing on their side.

The apex domain is the natural entry point an agent reaches first (it is what
`vaers.globalpatientsafety.com` / `picodag.globalpatientsafety.com` share a parent
with), yet it is the one surface with zero machine affordance.

### Proposed change

Portal-local, no sibling-repo dependency:

1. In `build_static_site.R`, add a `build_llms_txt()` (and a thin `build_robots.txt()`)
   that writes `static_site/llms.txt` listing the suite: the apex site, the article
   index, and each `live`/`beta` tool URL from `TOOLS`, with faers.mobi's API entry
   points (`/api`, `/openapi.json`, `/llms.txt`, `/mcp`) linked through. This is the
   same pattern `issues/llms-txt-2026-09-12.md` shipped for faers.mobi, one level up.
2. Add an optional `api_url` (or `docs_url`) column to the `TOOLS` tribble and render,
   on cards that have one, a small "REST API · OpenAPI · MCP" line so the API is
   discoverable from the card, not only from faers.mobi itself. Update the faers.mobi
   tagline to name the API.
3. Extend `check_site_consistency.R` to assert `static_site/llms.txt` lists every
   `live` tool URL, so the pointer cannot silently drift from `TOOLS`.

### Effort estimate

~1.5–2 h. One new writer function (~30 lines) mirroring the existing `build_*`
functions, one tribble column + a few lines in `tool_card_html()`, and a short
consistency assertion. No template redesign.

### Risk

Low. Additive files (`llms.txt`, `robots.txt`) and an optional column; existing pages
unchanged. Main care point: the `robots.txt` must not `Disallow` the article pages —
keep it Allow-only or omit it. Verify the apex nginx serves extensionless/`.txt`
paths (it already serves the extensionless article URLs).

---

## 2. CI stays green even when the production builder breaks or ships a dead internal link

**Severity: medium — correctness/consistency; small fix, high leverage (it is the guard on the one deployed artifact).**

### Evidence

`.github/workflows/site-checks.yml` runs a single step:
`Rscript --vanilla scripts/check_site_consistency.R`. It **never runs
`scripts/build_static_site.R`** — the actual production builder. Two gaps follow:

- **The builder itself is never exercised in CI.** A change that makes
  `build_static_site.R` `stop()` (a template edit, a new `TOOLS$status` value hitting
  the `switch()` at `build_static_site.R:217-221`, which has no default branch and
  would yield an empty/misformatted card) is caught only at manual deploy time, not on
  PR. The consistency check loads the tribbles with its own base-R parser
  (`check_site_consistency.R:27-62`) and never touches the builder's code path.
- **The builder's own dead-link guard cannot fail the build.**
  `check_internal_links()` (`build_static_site.R:446-489`) scans emitted HTML for
  same-site slugs and, on a hit, only calls `warning()` + `cat("WARNING: …")`
  (`build_static_site.R:479-485`). The script then prints "Done" and exits 0
  (`build_static_site.R:500-502`). A dead cross-link ships silently.
- **Coverage asymmetry.** `check_site_consistency.R` only scans the two *standalone*
  pages for draft-article hrefs (`standalone <- c("aems.html","methods.html")`,
  `check_site_consistency.R:127-145`). The *published article* bodies
  (`christine_cotton.html`, `covid_vaccine.html`, `shingles.html`) are never scanned
  for internal links at all. A dead `href="./glp1_alopecia"` inside `covid_vaccine.html`
  would pass both the consistency check (wrong file set) and the builder (warn-only).

So the exact class of bug `agent-review-2026-07-29` #1 flagged — a body linking a
draft/unbuilt article — can still reach production from a published-article body, and
CI would be green.

### Proposed change

1. Add a CI step that runs `Rscript scripts/build_static_site.R` and fails the job if
   it errors.
2. Make dead links fatal in CI: either promote `check_internal_links()`'s warning to a
   non-zero exit under an env flag (e.g. `GPS_STRICT_LINKS=1 → quit(status = 1)`), or
   add a CI grep that fails when the builder prints `WARNING:`.
3. Optionally broaden `check_site_consistency.R`'s draft-link scan to include the
   published-article HTML files, not just the two standalone pages.

### Effort estimate

~45 min. A few YAML lines in `site-checks.yml` plus a one-line strict-exit branch in
`check_internal_links()`. The build already runs in seconds and needs only
base-R-plus-tibble/dplyr/stringr, which the r-lib setup action provides.

### Risk

Low. Worst case a genuinely-broken build now fails PR CI instead of at deploy — which
is the point. Confirm the CI R image has `tibble`/`dplyr`/`stringr` available (the
builder uses them; the consistency script deliberately does not), or gate the build
step on their install.

---

## 3. The repo's live monitor probes an un-promised path (`GET /api/`, trailing slash) and treats its 500 as an incident — contradicting the product's own declared contract

**Severity: low–medium — correctness of this repo's only actively-running artifact; a false-positive already on record.**

### Evidence

`scripts/monitor_faers_mobi.sh` (cron on the workstation, the one thing this repo
*runs*) defines 27 checks. One is:

```
# scripts/monitor_faers_mobi.sh:63
"api-html-slash|GET|/api/|curl|200|text/html|How to query"
```

It requires `GET /api/` **with a trailing slash** to return `200 text/html`. But the
documented faers.mobi contract only promises the **no-slash** form:

- `issues/linux-implementer-handoff-2026-09-13.md` lists `GET /api` → 200 `text/html`
  and `GET /api.md` / `/API.md` → 200 `text/plain`. It never promises `/api/`.
- `issues/shiny-idle-timeout-2026-09-16.md` explicitly lists **"`/api/` trailing-slash
  500"** under **Out of scope**, i.e. the product owners have declared the trailing-slash
  500 a non-bug.

The result already happened: `issues/monitor-alert-20260915-2236.md` — filed
automatically by this monitor — reports "Failing checks (1 of 27): `api-html-slash`
`GET /api/` status 500 (want 200)", while the other 26 passed. So the monitor opened a
handshake episode for a path the owners consider out of contract. The monitor's own
alert template even invites this correction: *"Fix the cause, not the check: if a check
is wrong, say so here and the owner seat edits the monitor"*
(`monitor_faers_mobi.sh:199`).

### Proposed change

Reconcile the check with the contract — a one-line edit in `monitor_faers_mobi.sh`,
pick one:

- **Drop** the `api-html-slash` line (the no-slash `api-html` check at line 62 already
  covers the promised surface); or
- **Loosen** it to accept a redirect to `/api` (expect `301`/`308`, or treat
  `200`-or-`404` as pass) rather than requiring `200 text/html`; or
- If the intent is genuinely to require `/api/` to work, leave the check and instead
  file it to faers-mobi as an in-scope nginx fix — but that contradicts
  `shiny-idle-timeout-2026-09-16.md`, so it needs Harlan's call first.

Recommend dropping or loosening: the monitor exists to catch real contract breakage,
and a check stricter than the contract manufactures noise and burns a handshake episode.

### Effort estimate

~10 min. One array line (`monitor_faers_mobi.sh:63`), plus a `--dry-run` to confirm
the run drops to the intended 26/26 (or 27/27 if loosened to accept the redirect).

### Risk

Very low. Editing one probe cannot affect faers.mobi; it only changes what the monitor
counts as a failure. The only judgement call is whether `/api/` *should* work at all —
which is exactly the decision this finding surfaces for Harlan rather than deciding
unilaterally.

---

## Summary

| # | Finding | Type | Effort |
|---|---------|------|--------|
| 1 | Apex landing site has no `llms.txt`/`robots.txt` and no API pointer on the tool cards, against a quarter of LLM-first work on the tools | user-facing gap | ~1.5–2 h |
| 2 | CI never runs the builder and cannot fail on a dead internal link; published-article bodies are unscanned | correctness/CI | ~45 min |
| 3 | Monitor requires `GET /api/` (trailing slash) that the product declares out of contract; already filed a false-positive alert | monitor correctness | ~10 min |
