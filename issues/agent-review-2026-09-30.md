# Agent review — 2026-09-30

Weekly reflection on the globalpatientsafety.com clearing-house repo (the static
site + its registries, builder, and CI). **Report-only** — no file other than this
one is modified, and nothing is deployed.

## Reconciliation with prior reviews — including three that `main` can't see

The last agent-review *merged into `main`* is `agent-review-2026-07-29`. But three
more ran since and were **never merged** — each sits on its own open branch:
`agent-review-2026-09-09`, `-09-16`, `-09-23`. A fresh checkout (which is what this
agent gets) contains only the July files, so those three are invisible to the
dedup pass the task requires. I only found them by listing remote branches and
reading them out of GitHub. Their still-open proposals, by theme:

| Theme | Raised in | Status (from current `main` tree) |
|---|---|---|
| Social/SEO/LLM discovery metadata (OG/Twitter/canonical, `sitemap.xml`, `robots.txt`, portal `llms.txt`, API pointer on tool cards) | 09-09 #1, 09-16 #1, 09-23 #1 | **Open, unactioned.** `build_static_site.R:107-136` still emits only `<title>`+`description`; no `sitemap.xml`/`robots.txt`/`llms.txt` in the build. Proposed **3×**. |
| Dead-internal-link guard is warn-only and never runs in CI; CI only scans 2 pages for draft links | 09-09 #3, 09-16 #2, 09-23 #2 | **Open, unactioned.** `check_internal_links()` still only `warning()`s (`build_static_site.R:479-485`); `.github/workflows/site-checks.yml` still runs only `check_site_consistency.R`. Proposed **3×**. |
| Stalled weekly-article cadence; 3 approval-pending drafts never rendered | 09-23 #3 (and MSSO gating in 09-09 #2) | **Open.** Still `draft` in `app/logic/articles.R`; no `app/static/<id>.html`. |
| Monitor requires out-of-contract `GET /api/` trailing slash | 09-16 #3 | Open (sibling-facing). |

Per the task's rule I do **not** re-propose the SEO item or the dead-link/CI item —
they are already on record three times over and need a *merge/act* decision, not a
fourth restatement. That recurrence is the subject of **Proposal 2** below. The
July items (Signal-methods card, Rhino dead links, CLAUDE.md drift, Rhino-only CI)
are all resolved and not re-raised.

The three proposals below are either net-new or add materially new evidence.

---

## 1. The live "Signal & Noise" page advertises three finished installments as "In review," and the render step that prior reviews called "~30 min" points at a retired data path

**Builds on 09-23 #3 with two pieces of evidence that review didn't have: the live
user-facing mismatch, and a stale render input that makes "just render them" unsafe.**

### Evidence

- **The live series page makes a promise the repo hasn't kept.** `/methods`
  ("Signal & Noise") is live and top-nav (`app/logic/tools.R`,
  `build_static_site.R:79`). Its installments table
  (`articles/methods.qmd:55-56`) shows **GLP-1 → hair loss (alopecia)** and
  **Carbidopa/levodopa → B6 seizures; AAV gene therapy → liver** as **"In
  review."** Those three pieces are written in full — `articles/glp1-alopecia.qmd`
  (243 lines), `articles/carbidopa-levodopa-b6-seizures.qmd` (293),
  `articles/aav-gene-therapy-liver.qmd` (202) — yet all three are `status =
  "draft"` with no `app/static/<id>.html` (`app/logic/articles.R`). So a visitor is
  told work is "in review" that has actually been finished and sitting idle for
  ~10 weeks. 09-23 #3 cited the cadence freeze; it did not cite this live-page
  mismatch, which is the part users actually see.
- **The render inputs are stale.** All three drafts resolve their FAERS parquet
  from the same candidate list (e.g. `aav-gene-therapy-liver.qmd:28-33`):
  `params$data_path = /srv/shiny-server/gps-patient/data/signals_faers.parquet`,
  then `/home/harlan/projects/gps-patient/data/signals_faers.parquet`, then
  `/home/harlan/data/signal-compute/signals_faers_v2026-07-08.parquet`, and
  `stop()` if none exists. The first two point at a **`gps-patient` app that
  appears nowhere in the current architecture** (CLAUDE.md's data table lists
  `faers-mobi/data/signals.parquet` and `~/data/signal-compute/signals_faers_v<date>.parquet`,
  not `gps-patient`), and the third is a **single hardcoded 2026-07-08 snapshot**
  that signal-compute rotates by date (the CLAUDE.md debugging example already
  references a different `v2024-12-31` file). So the "~30-minute render" every prior
  review assumed may itself fail on a missing path — the drafts are further from
  shippable than 09-23 #3 implied.

### Proposed change

This does not bypass the owner's reMarkable approval gate (`DECISION_LOG.md:1807-1819`).
Two report-only asks:

1. **Before promising a quick publish, refresh the drafts' `data_path`** to a parquet
   that actually exists on the render host (a current `signal-compute` output, per
   CLAUDE.md), or pass `-P data_path:` at render time — then a post-approval render +
   `status`→`published` flip + rebuild actually works. (Editing the three `.qmd`
   render paths is a real code change, out of scope for this report-only PR — flagged
   for the implementer.)
2. **Reconcile the live page with reality now, independent of approval:** either
   publish ≥1 of the three (glp1_alopecia is the natural next after AEMS), or soften
   `articles/methods.qmd:55-56` from "In review" to "Planned" so the live site stops
   advertising indefinitely-pending pieces.

### Effort estimate

Path refresh + render is ~30-60 min *once a valid parquet is confirmed present* (the
unconfirmed dependency is the whole point). The copy-softening fallback is a 2-line
table edit. The binding cost remains the owner's approval read.

### Risk

Low. Approval gate untouched; the parquet dependency is named rather than assumed.
Fallback (2) has no data dependency.

---

## 2. Weekly agent-reviews are never merged, so each week's agent re-derives the same proposals blind — the SEO and dead-link items have now been filed 3× each

**Net-new. This is a process defect in the review routine itself, and it is why this
very run initially duplicated two of three findings.**

### Evidence

- Four review branches exist beyond the merged July set:
  `agent-review-2026-09-09`, `-09-16`, `-09-23`, `-09-30` (this one). Only the July
  reviews are on `main`; the 09-xx files exist **only on their unmerged branches**
  (confirmed via `git ls-remote --heads origin 'agent-review-*'` and by fetching the
  files from GitHub — they are absent from the working tree's `issues/`).
- The task instructs each run to "read existing `issues/agent-review-*.md` files …
  do NOT re-propose items already proposed there." But a fresh checkout only has
  `main`, so a run that trusts its checkout dedups against July alone and re-proposes
  the September items. Concretely, **the SEO/metadata item was filed in 09-09 #1,
  09-16 #1, and 09-23 #1**, and **the dead-link/CI-guard item in 09-09 #3, 09-16 #2,
  and 09-23 #2** — three identical proposals each, because none of the earlier ones
  was visible to the next agent.
- This isn't unique to the review routine: the `research-ideas-2026-09-25` commit on
  branch `research-ideas-2026-09-25` says the same thing in its own words — *"Last
  week's proposal file lives on an unmerged branch, so it was invisible to the dedup
  pass against main."* So the blind-spot has already been observed once and left
  unfixed. This run hit it a third time (I had to read three branches out-of-band to
  avoid shipping duplicates).

### Proposed change

Pick a single source of truth the next agent can actually see. Options, cheapest
first:

1. **Merge the review PRs** (they are report-only Markdown; there is no reason to
   leave them as permanently-open branches). Then a checkout's `issues/` carries the
   full history and the dedup rule works as written.
2. If reviews are meant to stay as open PRs for the owner to triage, **change the
   routine's step 2** to reconcile against open `agent-review-*` **branches/PRs**
   (via the GitHub API), not just the working tree — and say so in the stored prompt.
3. At minimum, maintain a running `issues/REVIEW_LEDGER.md` **on `main`** recording
   each week's proposals and their disposition (open/done/won't-do), so recurrence is
   visible without spelunking branches.

Recommend (1) for the backlog and (3) as the durable guard.

### Effort estimate

(1) minutes per PR (review + merge, CI is green Markdown). (3) ~20 min to seed the
ledger from the four existing reviews. (2) is a one-time prompt edit plus a few API
calls per run.

### Risk

Low. These are documentation/process changes. The one caveat: merging old review
files does not action their proposals — it only makes them visible; the owner still
decides what to implement. Without *some* fix here, expect a fourth SEO proposal and
a fourth dead-link proposal next week.

---

## 3. Two published articles' sources live at the repo root under mismatched names, beside a stray 4.8 MB rendered HTML — ambiguous source-of-truth and clone bloat

**Net-new — not raised in any prior review (07-08…09-23).**

### Evidence

CLAUDE.md documents one article path: Quarto `articles/*.qmd` → `app/static/<id>.html`,
`id` matching the HTML stem ("Adding a published article"). Every source obeys this
**except** the two oldest published articles:

- Published id `covid_vaccine` (`app/logic/articles.R`) → `app/static/covid_vaccine.html`,
  but its source is `./covid_vaccine_vaers_analysis.qmd` at the **repo root** (19 KB),
  not `articles/covid_vaccine.qmd`. No covid source exists under `articles/`.
- Published id `shingles` → `app/static/shingles.html`, but its source is
  `./shingles_vaccine_analysis.qmd` at the root (17.9 KB). `articles/shingles.md`
  exists but is only a **prompt stub** ("Breaking topic… Prompt: …"), not the source.
- `./covid_vaccine_vaers_analysis.html` (**4.8 MB**) is committed at the repo root and
  is **not** the file the builder ships (the builder reads `app/static/covid_vaccine.html`).
  It's a stray full render living in git history forever.

Net effect: anyone asked to update the COVID or shingles article must guess which of
three files is canonical, and every `git clone` pays 4.8 MB for an artifact nothing
reads.

### Proposed change

Normalise to the documented layout: `git mv covid_vaccine_vaers_analysis.qmd
articles/covid_vaccine.qmd`, `git mv shingles_vaccine_analysis.qmd articles/shingles.qmd`
(id-matched), fold the `articles/shingles.md` stub into the qmd or drop it, and
`git rm` the root `covid_vaccine_vaers_analysis.html` (the shipped `app/static/` copy
is untouched). Optionally extend `check_site_consistency.R` to assert every published
id has a matching `articles/<id>.qmd`, so this can't drift again.

### Effort estimate

~30-60 min: the moves/deletes, a rebuild to confirm `static_site/` is byte-identical
(the builder never reads the root files), and a `git grep` that nothing references the
old paths before removing them.

### Risk

Low, **zero production/deploy impact** — the builder reads `app/static/`, which this
proposal doesn't touch. Pure source hygiene.

---

## Summary

| # | Proposal | Type | Effort | Net-new? |
|---|---|---|---|---|
| 1 | Reconcile the live "In review" methods page + fix the drafts' stale render `data_path` before the next publish push | Stalled roadmap / user-facing / correctness | ~30-60 min + approval | New evidence on top of 09-23 #3 |
| 2 | Stop re-deriving the same review each week: merge/triage the unmerged `agent-review-*` branches or keep a ledger on `main` | Process / correctness of the review routine | minutes–20 min | Fully net-new |
| 3 | Normalise root-level article sources; drop the 4.8 MB stray HTML | Consistency / hygiene | ~30-60 min | Fully net-new |

**Not re-proposed** (already open across 09-09/09-16/09-23, awaiting a merge/act
decision, see the reconciliation table): social/SEO/LLM discovery metadata; making
the dead-internal-link guard fatal and running it in CI. Both remain worth doing —
they've simply been said, and the bottleneck is action, not analysis.
