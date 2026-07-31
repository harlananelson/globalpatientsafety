# Pharmacovigilance Suite — Decision Log

Running log of decisions, state-of-the-world findings, and open questions across the safety-apps stack: globalpatientsafety, faers-mobi, aers-mobi, signal-compute, safetysignal, faers-pipeline.

Each entry is dated. Don't delete resolved items — mark them resolved with the answer.

Cross-references: `SEARCH_REDESIGN.md`, `NOVELTY_FILTER_ROADMAP.md`, `/projects/AI/plans/DECISIONS.md`, `/projects/AI/plans/PLAN-ae-signal-platform-v2.md`, `/projects/AI/reviews/top20-novel-verification.md`.

---

## 2026-04-27 — User asks: full-data access + "just detected" splash

User requested two changes to faers-mobi and aers-mobi:

1. **Ask #1 — Full-data access:** users must be able to access all (drug, event) pairs, not just the top 2000.
2. **Ask #2 — "Just detected" splash:** default landing view should prioritize NOVEL / PENDING / UNTRACKED signals first detected in the last 12 months, even when their score is lower than older established signals.

Both asks were already specified in `SEARCH_REDESIGN.md` (Phase 1 = full-data access; Phase 2 = priority-tier splash).

## 2026-04-27 — Path chosen: option 3

Of three options presented (ship both asks now / ship full-data only / gate Emerging tier behind triage), user picked **option 3**: ship both asks but gate the Emerging tier behind AI triage so the splash leads with vetted signals; raw "just-detected, unverified" candidates accessible in a labeled section.

## 2026-04-27 — Manual triage replaced with AskSage

The manual `signal_triage.csv` / `signal_watchlist.csv` curation step is replaced by an AskSage-driven AI classifier. Reshapes the 4-tier splash semantics: triage state comes from the classifier, not from human curation.

## 2026-04-27 — Locked sub-decisions

| # | Decision | Locked as |
|---|---|---|
| 1 | AskSage triage execution | Offline batch inside signal-compute (writes `triage_class` + `triage_confidence` columns into the parquet). Apps stay presentation-only per `AI/plans/DECISIONS.md` D-001. |
| 2 | AskSage scope | **Downstream only.** Does NOT subsume the upstream rule-based novelty filters. `NOVELTY_FILTER_ROADMAP.md` Rounds 2–6 still need to be built. The `novel` flag is the input to AskSage; AskSage classifies among `{genuine-novel, known-on-label, indication-confound, product-quality, mechanism-or-expected, unclear}` for pairs that pass the rule-based filter. |
| 3 | "Just detected" window | 4 rolling quarters (= 12 months, matching FAERS quarterly cadence). |
| 4 | aers-mobi parity | Same lift-cap + search + AskSage triage. **No Emerging tier** (data ends 2012; "just detected" doesn't apply). |
| 5 | Build order | Track A first (no AskSage dep) → Track B (build classifier) → Track C (priority-tier splash). |

## 2026-04-27 — Decision-log discipline established

User instructed: maintain this `DECISION_LOG.md` as the running source of truth. Saved as feedback memory so it carries across sessions.

## 2026-04-27 — Track A revised after source inspection

Two findings forced a revision of Track A before any code was written:

1. **Deploy ships the full parquet, not a top-2000 subset.** `signal-compute/scripts/deploy_to_vps.sh:38` `scp`s the entire `signals_faers_v*.parquet` (~305 MB, 2.22M rows, 264,791 unique pairs at `n_methods_flagged ≥ 2`) to `/srv/shiny-server/faers-mobi/data/signals.parquet` with no filter. The `head(2000)` cap is **purely an in-app constraint** at `app/view/signal_timeline.R:417`. The CLAUDE.md framing ("top 2000 shipped to VPS") is incorrect and needs a correction.

2. **Arrow/DuckDB aggregation is essentially free.** Timed on the live parquet: full `WHERE n_methods_flagged>=2 GROUP BY rxnorm_name, outcome_name` returns 264,791 pairs in 0.2 seconds. Precomputing a summary parquet in signal-compute is unnecessary at this scale.

3. **Real bottleneck is per-row label match.** `pair_stats` lines 488–516 run `mapply(.event_in_label_expanded, ...)` over each row to set `novel`/`treats`. That's the 10–20s first-load delay. Lifting the cap to 264k rows of label-matching would be unworkable; the fix is to defer that enrichment to displayed rows only.

**Revised Track A (less work, all in faers-mobi):**

| Task | Status |
|---|---|
| ~~A1: Build summary parquet in signal-compute~~ | **Dropped** — Arrow does it in 0.2s in-app. |
| ~~A2: Ship summary parquet to VPS~~ | **Dropped** — full parquet already ships. |
| A3: Replace `head(2000)` with full Arrow aggregation | In progress |
| A3.5: Defer expensive enrichment (label match, ATC, triage) to displayed rows | In progress |
| A4: Server-side fuzzy search via `agrep` over Arrow | Pending |
| A5: Cache distinct drug + event names per session | Pending |

Net: zero changes to signal-compute. CLAUDE.md needs a one-line correction. Approved by user.

## 2026-04-27 — Schema confirmation

Live parquet at `/home/harlan/data/signal-compute/signals_faers_v2026-04-20.parquet`:
- 28 columns including `rxnorm_name` (BYTE_ARRAY), `outcome_name`, `quarter`, `eb05/eb50/eb95`, `prr/prr_lci/prr_uci/prr_chisq`, `ror/ror_lci/ror_uci`, `ic/ic025/ic975`, `is_signal_{gps,prr,ror,ic,any}`, `n_methods_flagged`, `ewma_eb05`, `ewma_ic025`, `observed`, `expected`, `rr`.
- 2,220,395 total rows; 264,791 unique pairs at `n_methods_flagged ≥ 2`.
- The `compute_quarterly.R` source assigns `df$drug` / `df$event` internally, but `safetysignal::detect_all_methods` preserves the input column names `rxnorm_name` / `outcome_name` in its output. No hidden rename step.

---

## 2026-04-27 — aers is a closed dataset (2004–2012)

User reminder: the aers-mobi backing data is **discontinued**. The legacy AERS dataset covers 2004 through 2012; no new data arrives. Implications:

- "This year's signals" doesn't exist for aers — the latest quarter is ~2012Q4.
- A wallclock-relative filter (`first_signal >= today - 12 months`) returns zero rows on aers in 2026.
- **Reaffirms sub-decision #4** (aers-mobi has no Emerging tier).
- For the equivalent "late-emerging in this dataset" concept on aers, the right framing is relative-recency: signals first flagged in the last 4 quarters of the dataset's range (~2012). That's a different concept ("late-emerging in hindsight") and may not be worth implementing — the splash for aers can simply be priority-tier sorted on Novel / Under review / Established without a recency tier.
- For faers, the same closed-dataset risk exists if the FAERS pipeline ever falls behind. The 12-month window should reference `max(first_signal in dataset)` minus 12 months, not `Sys.Date() - 12 months`, so the splash continues to surface "recently detected" rows even when the data stream is stale. **Action item for Track C:** anchor the 12-month window to the dataset's max quarter, not wallclock.

## 2026-04-27 — A3 + A3.5 refactor landed

Refactor of `faers-mobi/app/view/signal_timeline.R` complete:

- Added `SPLASH_SIZE <- 2000L` constant.
- Added `.enrich_label_match(ps_subset, lbl, mh, diana)` helper that runs the per-row label match (the 10-20s bottleneck).
- Split the old `pair_stats` into:
  - `pair_stats_full()` — full Arrow aggregation (all ~264k pairs after blacklist) with cheap enrichment only (substance, first_approval, Weber adj_eb05, ATC class + class co-flags, triage, watchlist). `lbl` no longer referenced here.
  - `pair_stats()` — calls `pair_stats_full()`, sorts by `adj_eb05` desc, takes `head(SPLASH_SIZE)`, runs `.enrich_label_match()` only on that subset.
- Blacklist check now runs on the ~15k distinct events instead of the 264k pair list (vapply over uniq_events, then `%in%` filter).
- Class co-flags now computed across the full pair universe (was previously top-2000 slice only) — semantically more correct.
- UI copy updated to reflect "all pairs flagged by ≥2 methods, splash shows top 2000 by Adj EB05" framing.
- Behavior unchanged from user's perspective: same 2000 displayed rows, same default sort/filter, same novel column. The architecture is now ready for A4 (search-aware row selection) and A5 (cached distinct names).

`Rscript -e 'parse(...)'` confirms syntactic validity. Not yet tested in-browser.

## 2026-04-27 — Track A refactor runtime-tested

Added `arrow` and `DT` to `globalpatientsafety/flake.nix` so faers-mobi can run from the existing nix dev shell (faers-mobi has no flake.nix of its own; renv::restore failed on this NixOS box because `fs`, `xml2`, and `httpuv` need system libs that aren't available outside nix). With the flake change, `nix develop` provides a usable R toolchain for both apps.

Boot test: `cd faers-mobi && R_PROFILE_USER=/dev/null Rscript -e 'shiny::runApp(...)'` from inside the nix shell. App boots clean, listens on the configured port, returns HTTP 200 with the expected title and the `<h4>Signals by drug and event</h4>` heading from `signal_timeline.R` UI. No load-time errors. The bslib asset-copy warnings are harmless nix-store-readonly noise.

Logic test: re-ran the exact `pair_stats_full()` Arrow aggregation against `data/signals.parquet`:
- **264,791 unique pairs in 0.57s** (matches DuckDB's earlier 0.2s; R's collect adds overhead but still sub-second).
- Quarter range: **2003Q1 → 2024Q4**. The dataset reaches back 22 years, and `latest_signal` maxes out at 2024Q4 — confirming the FAERS pipeline currently lags wallclock by a quarter or two.
- Top 3 by peak_eb05: `sestamibi + Scan myocardial perfusion abnormal` (EB05 ≈ 45,695), `statrol + False negative investigation result`, `ultra-technekow + Scan myocardial perfusion abnormal`. All three are imaging-agent / scan-result indication confounds — the exact failure mode `NOVELTY_FILTER_ROADMAP.md` Round 2 (indication confounder exclusion) is meant to fix. Worth surfacing as a concrete validation case for that round.

Not yet exercised: browser-side DT rendering, `.enrich_label_match()` (needs `fda_labels.parquet` which isn't present locally — function correctly handles `NULL` labels by returning NA novel/treats, so this just means "novel column is NA in the test env"), plot rendering on row click. These need a real browser session.

**Conclusion:** A3 + A3.5 refactor is sound. Safe to layer A4 + A5 on top.

## 2026-04-27 — A4 + A5 landed and runtime-tested

Added to `signal_timeline.R`:
- `textInput` search box + Clear button + status line in the UI (above the DT).
- `all_events()` / `all_drugs()` reactives that pull distinct names once per session from the flagged-pair subset of the parquet.
- `.fuzzy_match_pairs(query, events, drugs)` helper using `agrep` + `.normalize_spelling` — handles British↔American variants, edit-distance typos, and substring matches.
- `pair_stats()` is now search-aware: empty query → top SPLASH_SIZE by adj_eb05 (the splash); non-empty query → matched pairs filtered from `pair_stats_full()`, sorted by adj_eb05, capped at `SEARCH_RESULTS_MAX=2000`.
- Debounced search (`debounce(400)`) so typing doesn't fire on every keystroke.
- `output$search_status` shows match count and tells the user when results are capped.

Runtime test on the production parquet (9,118 distinct events, 5,255 distinct drugs after `n_methods_flagged>=2` filter):

| query | result | time |
|---|---|---|
| `ischemic stroke` (American) | 1 event matched: `Ischaemic stroke` | 0.06s |
| `semaglutide` | 9 drug matches (incl. combo formulations) | 0.06s |
| `ischeamic` (transposed-letter typo) | 27 events incl. `Transient ischaemic attack` | 0.05s |
| `diarrhoea` (British) | 9 events incl. `Diarrhoea` | 0.04s |
| `sertralin` (truncated) | 4 drug matches | 0.05s |

Spelling normalizer + agrep + substring-match all work end-to-end. App boots cleanly with the new shiny imports (`textInput`, `actionButton`, `debounce`, `distinct`).

Not yet tested: live websocket interaction (typing in the box → DT updates). That requires a browser.

**Track A is feature-complete in faers-mobi.** Next: A6 (port to aers-mobi), A7 (CLAUDE.md fix).

## 2026-04-27 — Latest signal in parquet is 2024Q4 (pipeline lag)

The production parquet's `max(quarter) = 2024Q4`, while wallclock is 2026-04-27. So a wallclock-anchored "last 12 months" filter on Track C would today match 2025Q2..2026Q1 — entirely outside the dataset, returning zero rows. **Reinforces the recommendation to anchor the 12-month window to `max(first_signal in dataset)`, not `Sys.Date()`.**

## 2026-04-27 — Master plan (all tracks, including new directions)

User added three new directions in the same conversation:
1. **Tabs for audience-targeted queries** (Track F)
2. **Drug-centric profile beyond signals** — visitors arrive with their own meds and want more than just signals (Track G)
3. **Eventually: user accounts + per-user drug tracking** (Track H)

Single source of truth — everything we know is queued. Each line links back to its task ID.

### Track A — Search redesign (faers-mobi)
| ID | Task | Status |
|---|---|---|
| #3 | A3: Replace head(2000) cap | ✅ done |
| #6 | A3.5: Defer expensive enrichment | ✅ done |
| #5 | A5: Cache distinct names | ✅ done |
| #4 | A4: Server-side fuzzy search | ✅ done |
| #7 | A6: Port Track A to aers-mobi | ✅ done |
| #8 | A7: Correct CLAUDE.md "top 2000 shipped" claim | ✅ done |

### Track B — Local-LLM triage (downstream-only) — pivoted from AskSage 2026-04-27
| ID | Task | Status |
|---|---|---|
| #9 | B1: Define triage label schema | ✅ done (PLAN-llm-triage.md) |
| #10 | B2: Build local-LLM triage prompt (Ollama) | ✅ draft (smoke-tested, refine on 32B) |
| #11 | B3: Validate against top-20 ground truth | fixture defined; full run held for 3090 |
| #12 | B4: Run as offline batch in signal-compute | outlined; build after B3 passes |

**Track B pivot (2026-04-27):** triage runs locally on the GPU (Ollama), not via remote AskSage. Recurring quarterly batch on every new FAERS release → justifies investment in a good local solution. Optional Claude/AskSage API fallback for low-confidence rows only (~5% of pairs), cutting API spend ~95%. **Hardware roadmap:** current RTX 2060 (6 GB) suitable for prompt-engineering + small-model validation; RTX 3090 (24 GB) arriving ~2026-05-04 will fit Qwen 2.5 32B Q4 or Mistral Small 24B. Apps stay presentation-only — triage_class + triage_confidence land in the summary parquet.

### Track C — Priority-tier splash
| ID | Task | Status |
|---|---|---|
| #13 | C1: 4-tier priority sort using AskSage triage | pending |
| #14 | C2: Replace .default_row hardcode | pending |
| #15 | C3: Tier badges + colors in DT | pending |
| #16 | C4: "Just-detected, unverified" side panel | pending |
| #17 | C5: Anchor 12-month window to dataset max quarter | pending |

### Track D — Rule-based novelty filters (NOVELTY_FILTER_ROADMAP.md)
| ID | Task | Status |
|---|---|---|
| #18 | D2: MedDRA hierarchy walk | pending — needs UMLS data prep |
| #19 | D3: Class-effect filter | ✅ shipped (threshold=3, configurable) |
| #20 | D4: Indication confounder exclusion | ✅ effective via deploy script + multiproduct labels |
| #21 | D5: Label cache product-variant selection | ✅ shipped (data + deploy) |

### Track E — Pipeline / data refresh
| ID | Task | Status |
|---|---|---|
| #22 | E1: Re-run signal-compute against current contingency | in progress — relaunched 2026-04-28 01:44 after cli format crash; 143 quarters 1990Q1–2025Q4 |
| #23 | E2: Investigate 2023Q1–2024Q3 gap (blocked on E1) | pending |
| #24 | E3: Re-download FAERS 2025Q2 in faers-pipeline | pending |

**E1 finding (2026-04-27 during rerun):** contingency has **143 quarters from 1990Q1 to 2025Q4**, not the 78 quarters (2003Q1–2024Q4) the prior signals parquet reflected. So the prior signals output was missing not just the recent quarters but all of 1990–2002 too. The current rerun should produce the full 143-quarter signals output. This may also explain the 2023–2024 gap (E2): the prior run had a different / partial quarter list than what's actually on disk.

### Track F — Audience-targeted tabs
| ID | Task | Status |
|---|---|---|
| #25 | F1: Identify audiences + canned queries | open scoping |
| #26 | F2: Implement audience tabs | pending (blocks on F1) |

### Track G — Drug-centric profile
| ID | Task | Status |
|---|---|---|
| #27 | G1: Scope per-drug data layers | open scoping |
| #28 | G2: Drug profile page in faers-mobi | pending (blocks on G1) |
| #29 | G3: Pipeline support for richer per-drug data | pending (blocks on G1) |

### Track H — User accounts + tracking ("eventually")
| ID | Task | Status |
|---|---|---|
| #30 | H1: Scope auth + storage stack | open scoping |
| #31 | H2: Sign-in + drug tracking UI | pending (blocks on H1) |
| #32 | H3: New-signal email notifications | pending (blocks on H2) |

### Cross-cutting open questions

- **F audiences:** which 4–6 audiences/queries to seed first? (clinicians, regulatory, researchers, patients, media — needs user input)
- **G data layers:** which per-drug layers ship first? Full label, DDI, demographics, class effects, alternatives — needs user input
- **G data dependency:** demographics + DDI require pipeline expansion; label coverage requires fixing the ~2/3 of drugs missing from `fda_labels.parquet`
- **H scope:** hosted auth vs custom? SQLite vs Postgres? Auth provider? What triggers a notification (any new signal, tier promotion, only Emerging)? Needs user input before building
- **C5:** anchor the 12-month "Emerging" window to dataset max quarter (recommended, confirmed by 2024Q4 max in current parquet). After E1 rerun the max should jump to 2025Q4.

## 2026-04-27 — A7 (CLAUDE.md correction) shipped

`/projects/globalpatientsafety/CLAUDE.md` "The Top 2000 Limitation" section
replaced with "Splash Cap (in-app), not a deploy filter" — corrects the false
claim that `signals.parquet` shipped to the VPS is filtered to top 2000.
Truth: the full ~265k-pair parquet ships; the 2000 cap is an in-app splash
constraint that search bypasses. Section now explains the post-Track-A
behavior and points readers at `DECISION_LOG.md` for context.

## 2026-04-27 — A6 (port Track A to aers-mobi) shipped

`aers-mobi/app/view/signal_timeline.R` patched to match the faers-mobi Track A
architecture:

- Added `textInput, actionButton, debounce` to shiny imports, `distinct` to dplyr.
- Added `SPLASH_SIZE` and `SEARCH_RESULTS_MAX` constants.
- Added `.fuzzy_match_pairs()` and `.enrich_label_match()` helpers.
- UI rewritten: search box + Clear button + `search_status` line above the DT.
  Copy reflects AERS being a closed dataset (2004–2012); cross-links to
  faers.mobi for ongoing data; calls out that "novel" compares historical
  signals against *current* labels (so labels updated 2013+ in response to
  AERS-era signals will read as "known").
- Added `all_events()`, `all_drugs()`, `search_query` (debounced 400ms),
  `observeEvent(input$clear_search)` reactives.
- Split `pair_stats` into `pair_stats_full()` (full pair universe, cheap
  enrichment only) and `pair_stats()` (search-aware, expensive label match
  on the rendered subset only). `head(2000)` cap dropped from full universe.
- Blacklist filter now runs on distinct events (not full pair list).
- Class co-flags computed across the full pair universe (was top-2000 slice).

**Preserved:** default row remains `vioxx + Myocardial infarction` (the classic
AERS-era case), search placeholder uses AERS-era examples.

Runtime tests:
- Parse: clean.
- Boot: app listens on the configured port, returns 200 with the "Signals by
  drug and event" heading and the search input rendered.
- Logic: full Arrow aggregation against the production AERS parquet
  (`signals_aers_v2026-04-20.parquet`, 210 MB) returns **143,203 pairs in
  0.34s**. Quarter range 1997Q1–2012Q4. 5,711 distinct events, 3,677
  distinct drugs.
- Top-5 by peak_eb05 are mostly anesthesia/imaging-agent / surgical
  scenarios (scandicain → retinal artery, cyclopentolate → iridocyclitis,
  zemuron → neuromuscular block). Same indication-confound failure mode as
  the FAERS top-5 — Track D Round 4 (indication confounder exclusion) will
  fix both.

**Track A is now feature-complete in both apps.** Remaining Track A tasks: ✅ A6, ✅ A7.

## 2026-04-27 — Track B (B1 + B2 + smoke-test) drafted

Wrote `/projects/AI/plans/PLAN-llm-triage.md` covering:

- **B1 (label schema):** 6 mutually exclusive labels with priority order
  (`product-quality > indication-confound > mechanism-or-expected >
  known-on-label > genuine-novel > unclear`). Stored as `triage_class` +
  `triage_confidence` columns in `signals_faers_v<date>.parquet`.
- **B2 (Ollama prompt):** system prompt + user-message template + strict
  JSON output schema. Designed for `format=json` mode in `ollamar` /
  `POST /api/chat`.
- **B3 (validation set):** all 20 pairs from `top20-novel-verification.md`
  mapped to expected `triage_class`. Pass criteria: ≥ 16/20 AND no
  product-quality / indication-confound classified as genuine-novel.
- **B4 (production batch):** outline of `signal-compute/scripts/triage_signals.R`,
  throughput target 30k rows / 4 hours on RTX 2060 / 7B.

**Smoke test on `mistral:latest` (7B) — 2 audit pairs:** confirms plumbing
works (valid JSON both cases, confidence in [0,1], reason ≤ 150 chars).
Reveals two issues:

1. Format compliance — model adds "1. " prefix to the class label.
   Fixable by prompt strengthening + post-hoc strip of `^\d+\.\s*`.
2. Priority-rule reasoning — case 15 (daprodustat + Nephrogenic anaemia,
   expected `indication-confound`) was misclassified `known-on-label`
   with confidence 0.95 + a fabricated justification. The 7B class
   doesn't reliably apply the indication-vs-AE distinction.
   Likely needs the 32B-class model arriving with the 3090 (~2026-05-04).

**Conclusion:** schema + plumbing are sound. Prompt iteration on 7B can
shore up format compliance. Production B4 should hold for the 3090 + 32B
model — already the master plan's build order.

Master plan status updates: B1 ✅, B2 ✅ (draft, will refine on 32B), B3
fixture defined (run pending model upgrade), B4 outlined.

## 2026-04-28 — E1 crashed at output write; cli format bug; relaunched

E1 (signal-compute rerun, started 2026-04-27 20:20) ran all 143 quarters of
`safetysignal::detect_all_methods` to completion in-memory, then died at
01:41 (~5h21m runtime) at `cli_inform("Total rows: {nrow(long):,}")` —
glue's `:,` thousands-separator format is unsupported by the cli version
in the nix dev env. Crash was in the post-compute logging step, before
EWMA smoothing and parquet write. **All compute work was lost.**

Two-line fix in `signal-compute/R/compute_quarterly.R` (lines 145, 165):

```diff
-cli_inform("Total rows: {nrow(long):,}")
+cli_inform("Total rows: {format(nrow(long), big.mark = ',')}")
-cli_alert_success("Wrote {nrow(long):,} rows to {.path {out_path}}")
+cli_alert_success("Wrote {format(nrow(long), big.mark = ',')} rows to {.path {out_path}}")
```

Parse-checked. Background relaunch kicked off 01:44; will produce
`signals_faers_v2026-04-28.parquet` (~318 MB, 143 quarters 1990Q1..2025Q4).

Track D work proceeds against the existing `signals_faers_v2026-04-20.parquet`
(2024Q4 max) since D-track changes live in `signal_timeline.R`, not the
signals parquet.

## 2026-04-28 — Track D pre-flight: data-file inventory + audit-case verification

Before code changes, inventoried what data files actually exist locally
and which audit cases the existing matchers catch with the right cache.

### Data files

| App expects | Canonical source | Has `indications_and_usage`? |
|---|---|---|
| `data/fda_labels.parquet` | `~/data/faers-pipeline/output/fda_labels.parquet` (12 cols) | ❌ no |
| `data/fda_labels.parquet` | `~/data/faers-pipeline/output/fda_labels_augmented.parquet` (13 cols) | ✅ 32.8% (656/2000) |
| `data/fda_labels.parquet` | `~/data/faers-pipeline/output/fda_labels_multiproduct.parquet` (14 cols, +`multiproduct_fetched_at`) | ✅ 33.1% (663/2000) |
| `data/meddra_hierarchy.parquet` | `~/data/diana/meddra_hierarchy.parquet` (4 cols: pt, cui, synonyms, definition) | n/a — **NO hlt/hlgt/soc columns** (D2 still needs this work) |
| `data/atc_classes.parquet` | `~/data/diana/atc_classes.parquet` (5 cols, atc_class2/3/4) | n/a — sufficient for D3 |
| `data/diana_dictionary.parquet` | `~/data/diana/diana_dictionary.parquet` | n/a |
| `data/first_approval.parquet` | `~/data/diana/first_approval.parquet` | n/a |

**D5 (label cache product-variant) has shipped at the data layer** —
`fda_labels_multiproduct.parquet` is the latest cache, with
`indications_and_usage` and a multiproduct-aware fetch. Apps just need to
point at it (or a symlink).

Symlinked all five files into both `faers-mobi/data/` and `aers-mobi/data/`
locally so the app stack runs end-to-end on the dev box.

### Audit-case verification (the multiproduct cache + existing matcher)

Faithfully replicated `pair_stats`'s `treats` and `novel` computation
against the multiproduct label cache for two representative audit cases:

| Audit pair | direct match (0.7) | synonym walk (0.6) | result |
|---|---|---|---|
| daprodustat + Nephrogenic anaemia | FALSE | TRUE via "anemia of renal disease" → matches "anemia due to chronic kidney disease" indication | `novel=FALSE, treats=TRUE` ✅ |
| blinatumomab + Acute lymphocytic leukaemia recurrent | TRUE (lymphoblastic→lymphocytic + relapsed→recurrent normalization makes 4/4 words match) | n/a | `novel=FALSE, treats=TRUE` ✅ |
| alkindi sprinkle + Adrenocortical insufficiency acute | FALSE | FALSE — but **wrong label cached** (topical itch hydrocortisone, not oral Alkindi) | `novel=TRUE` (false-novel; multiproduct fetch didn't catch this product) |

**Conclusion:** the existing `.event_in_label_expanded` synonym walk +
multiproduct label cache **already correctly classifies daprodustat and
blinatumomab as known-on-label** (via indication match). The default DT
filter `Novel = "novel"` will hide them automatically.

D4 ("indication confounder exclusion") is therefore not a code change in
the apps — it's a **deploy-script change** to ensure the VPS has
`fda_labels_multiproduct.parquet` (mounted as `fda_labels.parquet`) and
the meddra_hierarchy / atc_classes / diana_dictionary / first_approval
files. The current `signal-compute/scripts/deploy_to_vps.sh` only ships
3 files: signals, drug_dictionary, event_dictionary. It does NOT ship the
five enrichment files.

### Updated next-step plan

1. **D4 (deploy):** extend `deploy_to_vps.sh` to scp the multiproduct
   label cache + meddra_hierarchy + atc_classes + diana_dictionary +
   first_approval. Verify on VPS.
2. **D3 (class-effect filter):** code change in `signal_timeline.R` —
   surface `class_co_flags >= N` as a default filter (hide class-effect
   rows from default novel view, keep visible with a checkbox). Pure
   in-app, no new data needed.
3. **D2 (MedDRA hierarchy match PT → HLT/HLGT/SOC):** still needs offline
   data prep — extend `meddra_hierarchy.parquet` builder to fetch parent
   terms via UMLS API. Larger scope; defer to after D3 + D4 ship.

## 2026-04-28 — D4 (deploy script) shipped

`signal-compute/scripts/deploy_to_vps.sh` extended to copy 5 additional
files alongside the existing 3 (signals + drug_dict + event_dict):

- `fda_labels_multiproduct.parquet` → VPS as `fda_labels.parquet`
- `meddra_hierarchy.parquet`
- `atc_classes.parquet`
- `diana_dictionary.parquet`
- `first_approval.parquet`

Sources are `~/data/faers-pipeline/output/` and `~/data/diana/`.
Pre-flight check now `[[ -f $f ]]` over all 7 inputs. Bash syntax-checked.
**Not auto-deployed** — requires user to run the script (production
shared-state action; auth via existing root@5.78.69.136 ssh key).

Equivalent script for aers-mobi doesn't exist yet — aers historical
data ends 2012Q3 so the existing parquet is the final snapshot. When
ready, point an `aers-mobi` deploy at the same enrichment files.

## 2026-04-28 — D3 (class-effect filter) shipped in both apps

Added `CLASS_EFFECT_THRESHOLD <- 3L` constant to both
`faers-mobi/app/view/signal_timeline.R` and the equivalent in aers-mobi.
DT default-filter on Class co-flags column (column index 11) set to
`"0 ... 2"` (i.e. <= CLASS_EFFECT_THRESHOLD - 1L), which hides pairs
with ≥3 class co-flags from the default novel view. Filter is clearable
by the user to show class effects.

UI copy in both apps updated to explain the new behavior (≥3 suggests
class effect; clear the column filter to see them).

**Empirical impact (faers, top-2000 splash):** 367 / 2000 (18.4%) of
splash rows would be hidden by the threshold. Distribution of full pair
universe (264,791 pairs) by class_co_flags:

| class_co_flags | count |
|---|---|
| 1 (drug-specific) | 99,872 (37.7%) |
| 2 | 46,052 (17.4%) |
| 3 | 30,153 (11.4%) |
| 4–5 | 35,280 (13.3%) |
| 6–10 | 34,044 (12.9%) |
| >10 | 19,390 (7.3%) |

Threshold of 3 picked as a default; user can tune `CLASS_EFFECT_THRESHOLD`
upward (less filtering) or downward (more aggressive). 2 would hide ~63%
of pairs (probably too aggressive); 5 would hide ~33% (less aggressive).

faers-mobi boot-test: HTML response contains the updated D3 copy
("≥3 suggests class effect; clear the Class co-flags column filter to
see them"). Parse-clean both apps.

## 2026-04-28 — D-track status update

| ID | Round | Task | Status |
|---|---|---|---|
| #18 | 3 | D2: MedDRA hierarchy walk PT → HLT/HLGT/SOC | pending — needs offline UMLS data prep |
| #19 | 4 | D3: Class-effect filter | ✅ shipped (default threshold 3) |
| #20 | 5 | D4: Indication confounder exclusion | ✅ effectively shipped — code path already correct, fix was deploy-script + multiproduct cache (D5 data) |
| #21 | 6 | D5: Label cache product-variant selection | ✅ shipped at data layer (`fda_labels_multiproduct.parquet`); deploys via updated `deploy_to_vps.sh` |

## 2026-04-28 — E1 finished successfully

E1 rerun completed at 07:02:54 (5h19m wallclock). Output:
`/home/harlan/data/signal-compute/signals_faers_v2026-04-28.parquet` —
**1.79 GB**, 19,463,483 rows, **117 of 143 quarters** (early sparse
quarters returned NULL from `detect_all_methods` and were skipped, as
designed). Quarter range 1990Q1..2025Q4. 2,267,851 unique drug-event
pairs. EWMA + bind_rows + write all worked end-to-end after the cli
format fix.

**Schema regression discovered:** new parquet has columns `drug`/`event`
where the old parquet had `rxnorm_name`/`outcome_name`. Root cause:
`safetysignal::detect_all_methods` preserves the input column names
that compute_quarterly.R passes in (which are `drug`/`event` at line
86-87 — a rename FROM the contingency parquet's `rxnorm_name`/`outcome_name`).
Earlier DECISION_LOG entry assumed the safetysignal call would echo
`rxnorm_name`/`outcome_name`; that assumption was wrong.

User push-back on the column naming surfaced a deeper issue: the column
called `rxnorm_name` was NEVER actually RxNorm-normalized. Profiling the
new parquet's `drug` column: 45,013 distinct strings, only 34.5% resolve
to a DiAna substance (15,522 / 45,013), and those 15.5k compress to 3,049
substances — **5.1× compression** if substance-level normalization were
done pre-signal-calc. Top substances by raw-name fan-out:

| Substance | # raw names |
|---|---|
| ethanol | 145 |
| insulin | 135 |
| ethinylestradiol;levonorgestrel | 93 |
| ibuprofen | 86 (advil, motrin, advil liqui-gels…) |
| paracetamol | 85 (tylenol, calonal…) |

User's plan: do three sequential steps — (1) schema migration to `drug`/`event`
in apps now, (2) crosswalk + search-with-dropdown UX layer, (3) pre-signal-calc
substance-level normalization (pipeline rewrite). All three approved 2026-04-28.

## 2026-04-28 — Step 1: schema migration shipped

Migrated both apps from `rxnorm_name`/`outcome_name` to `drug`/`event`:

- `faers-mobi/app/view/signal_timeline.R` — 27 references replaced via
  bulk replace_all. Boot-tested against fresh
  `signals_faers_v2026-04-28.parquet` (1.79 GB). Track A aggregation
  returns **1,408,403 pairs in 1.83s** (vs 264k pairs in 0.57s previously
  — 5.3× more pairs at consistent per-pair latency).
- `aers-mobi/app/view/signal_timeline.R` — bulk replace_all blocked by
  harness; completed via 14 targeted Edits. Boot-tested green.
- AERS contingency does not exist on this box (closed dataset, won't
  regenerate), so AERS rerun isn't possible. Instead renamed columns
  in-place in `signals_aers_v2026-04-20.parquet`:
  `rxnorm_name → drug`, `outcome_name → event`. Original backed up to
  `signals_aers_v2026-04-20.original-schema.parquet`. ~1.1s rewrite,
  same 210 MB file size.
- `compute_quarterly.R` did NOT need a code change — its internal
  `df$drug <- df$rxnorm_name` rename (line 86) means the upstream
  contingency schema is unchanged; the output schema is naturally
  `drug`/`event`.
- Local symlink `faers-mobi/data/signals.parquet` updated to point at
  the fresh 2026-04-28 parquet. AERS symlink unchanged (same path).

**Top-5 by peak_eb05 in the new dataset (still indication-confound /
imaging-agent dominated, awaiting Track D2):**

| drug | event | peak_eb05 | quarters |
|---|---|---|---|
| ultra-technekow | Scan myocardial perfusion abnormal | 37,558 | 1 |
| statrol | False negative investigation result | 29,389 | 1 |
| oxytocin sodium chloride | Postpartum haemorrhage (?) | 25,548 | 2 |
| sestamibi | Scan myocardial perfusion abnormal | 25,423 | 1 |
| meningococcal b recomb | Meningococcal infection (?) | 22,841 | 9 |

The 1-quarter pairs are likely contingency-table artifacts; the 9-quarter
meningococcal pair is the kind of repeatedly-flagged signal worth
investigating. After 3090 + Track B triage, these will get classified.

## 2026-04-28 — Step 2: multi-vocab search + brand-substance crosswalk shipped

`.fuzzy_match_pairs()` extended in both apps to take four vocabularies
instead of two:

- `events` — fuzzy via agrep + spelling normalization (typo-tolerant).
- `drugs` (raw drug names) — fuzzy via agrep.
- `substance_to_drugs` (named list of substance → [raw drug names]) —
  exact substring only. Fuzzy on canonical short names produces too
  many false positives ("statin" → "Androstan derivatives", "ozempic"
  → "clorazepic acid"). Restricting to substring is the right tradeoff.
- `atc_to_drugs` (named list of ATC4 class → [raw drug names]) — exact
  substring only, same reason.

**Brand → substance crosswalk:** when a raw drug name matches the query
("vioxx", "advil", "tylenol"), the app reverse-resolves it through DiAna
to find the substance ("rofecoxib", "ibuprofen", "paracetamol") and
expands to every other raw drug name resolving to that substance. So
typing "vioxx" surfaces all 1 brand + however many other rofecoxib
formulations are in the parquet.

**Empirical test on the new 1.4M-pair dataset:**

| query | drug-name | substance | ATC | total drugs | notes |
|---|---|---|---|---|---|
| advil | 78 | 14 (ibuprofen + 13 combos) | 0 | 238 | brand → substance crosswalk works |
| vioxx | 7 | 1 (rofecoxib) | 0 | 8 | clean |
| ozempic | 2 | 2 (semaglutide + clorazepic acid noise) | 0 | 10 | small agrep noise on short query |
| lipitor | 95 | 19 (atorvastatin + some noise) | 0 | 410 | |
| tylenol | 435 | 9 (paracetamol + combos) | 0 | 566 | |
| ibuprofen | 149 | 12 (combos) | 0 | 217 | |

The remaining noise (e.g. ozempic→clorazepic) is from agrep matching on
SHORT queries against drug-name lists — a known limitation. Substance
and ATC matching is now precise.

UI changes:
- `search_status` UI line now shows categorized breakdown: `"X pairs for
  'advil' — matched 78 drug names, 14 substances (224 drugs)"`.
- Placeholder updated: `"Search any brand, generic, substance, ATC class,
  or event (e.g. advil → ibuprofen + 86 brands)"`.
- New reactives `substance_to_drugs()` and `atc_to_drugs()` build the
  named lists from `all_drugs() + diana_dict() + atc_classes()` —
  computed once per session.
- `search_match()` reactive caches the per-query match so `pair_stats`
  and `search_status` don't double-compute.

aers-mobi got the same changes via targeted edits (3 reactive additions,
.fuzzy_match_pairs replaced, pair_stats + search_status updated, placeholder
text). Parse-clean both apps; faers-mobi boot-test green with new
placeholder rendering.

**What this does NOT do (yet):** the search returns more rows by
resolving brand-to-substance, but the table still shows EACH raw
drug-event pair as a separate row. So typing "advil" and getting 238
ibuprofen-related drugs means up to 238 × N event rows. Step 3 adds
roll-up at signal-compute time so the user sees a single ibuprofen row.

## 2026-04-28 — Step 3: substance-level contingency built; signal-compute launched

### Discovery: contingency `rxcui` is 100% populated

Inspected `/home/harlan/data/faers-pipeline/contingency/source=faers/year=2024/quarter=4`:
all 60,380 rows have an `rxcui` (RxNorm Concept Unique Identifier). The
column is at brand/product level (e.g. "lastacaft", "xeomin"), not
ingredient level — so DiAna remains the right tool for substance
normalization.

### Substance contingency build (fast, < 7 min)

Wrote `signal-compute/scripts/build_substance_contingency.R`:

- Reads `~/data/faers-pipeline/contingency/source=faers` (143 partitions).
- Looks up substance for each row via DiAna; resolved rows replace
  `rxnorm_name` with the substance and clear `rxcui` (no longer 1:1
  after aggregation).
- Aggregates by `(rxnorm_name [now substance], outcome_name, quarter)`
  summing `observed`. Unresolved rows pass through unchanged.
- Writes to `~/data/faers-pipeline/contingency-substance/source=faers/`
  in the same hive partitioning.

**Run results:**

| metric | value |
|---|---|
| Input rows | 8,382,427 |
| Output rows | 7,313,182 (12.8% row compression) |
| Rows resolved (substance lookup hit) | 7,985,208 (95.3%) |
| Wallclock | ~7 min |

The resolution rate of **95.3% by report volume** is much higher than
the 34.5% rate seen on distinct drug NAMES — the unresolved drugs are
mostly the long tail of rare/odd strings (formulation noise, vendor
suffixes) with very few reports each. Most actual report volume hits
well-known drugs that all resolve cleanly to substances.

### Substance signal-compute launched

```
nix develop --command bash -c '
  Rscript R/compute_quarterly.R \
    --source faers \
    --contingency-root /home/harlan/data/faers-pipeline/contingency-substance \
    --output-root /home/harlan/data/signal-compute/substance
'
```

- Started 2026-04-28 08:05:50.
- Output will be `signals_faers_v2026-04-28.parquet` in the substance
  output dir (segregated from the regular faers output).
- Expected ~5h based on the regular run.
- First few quarters running ~1,700–4,200 pairs each (vs ~2,000–4,300
  for the regular compute) — fewer pairs as expected after substance
  rollup.

### Pending app-side work (after substance parquet lands)

Substance signals will need a UI toggle so users can switch between
drug-level (raw FAERS reported names — current default) and
substance-level (DiAna-rolled-up active ingredients) views:

- Add `RADIO` or top-of-page selector: "Drug-level | Substance-level".
- `signals()` reactive picks the parquet path based on the selector.
- The rest of the pipeline (Track A search, D3 class filter, etc.)
  carries over unchanged because both parquets have the same schema
  (drug, event, …).
- Substance-level view should re-tune `CLASS_EFFECT_THRESHOLD` because
  rolled-up substance signals will have different class-co-flag
  distributions (more concentrated within substances since multiple
  brand-level rows now collapse to one).

Estimated UI work: ~30 lines per app, parse-check + boot-test —
afternoon-of-effort.

## 2026-04-28 — Substance signal-compute complete

Substance signal-compute finished 2026-04-28 12:02:12, 3h56m wallclock
(faster than predicted ~5h). Output: `~/data/signal-compute/substance/signals_faers_v2026-04-28.parquet`,
1.45 GB, 16,046,017 rows, 117 quarters 1990Q1–2025Q4, 1,595,664 unique
drug-event pairs (vs 2,267,851 at drug level — ~30% fewer pairs after
rollup). Schema matches drug-level (`drug`, `event`, …) so the apps can
read it with the same code.

### Consolidation verification

For drugs with DiAna mappings, consolidation is exactly as predicted:

| Substance | Brand rows (drug parquet) | Substance rows (substance parquet) |
|---|---|---|
| ibuprofen | 86 | 1 |
| paracetamol | 85 | 1 |
| insulin | 135 | 1 |
| ethanol | 145 | 1 |
| metformin | 68 | 1 |

The single ibuprofen row has clean rolled-up signals: `Kounis syndrome`
peak EB05 = 255 across 18 quarters with 77 reports — a real
ibuprofen-specific signal that's now consolidated across all brands.

### Mixed-granularity outcome (intentional)

| Tier | # distinct drugs | % of distinct drugs |
|---|---|---|
| Clean substance row (DiAna-resolved) | 3,055 | 9.4% |
| Unresolved raw drug name (pass-through) | 29,460 | 90.6% |

The 9.4% / 90.6% split looks bad on counts but the 95.3% report-volume
resolution dominates; most actual signal data IS consolidated. The 29,460
unresolved long-tail strings (`"advil enfants et nourrissons ibuprofen
suspension"`, etc.) carry few reports each.

### Decision: ship option 1 (mixed granularity, as-built)

User picked option 1 of three options surfaced:
1. **Ship as-is.** Mixed granularity preserved; design matches spec.
2. Drop unresolved on substance view (cleaner; loses 4.7% volume).
3. Substring-fallback rollup (try `grepl(substance, drugname)` for
   unresolved rows; risk false positives).

Why: option 1 is the cheapest behavior change and matches the spec
agreed upstream. Option 3 is on the future-plans list.

## Future plans (queued, not in flight)

- **Substring-fallback substance rollup (option 3 from above).** When
  building substance contingency, for unresolved rows attempt a
  `grepl("\\b<substance>\\b", drugname)` containment check before
  passing through. Cuts the long-tail mixed-granularity problem (would
  fold `"advil enfants et nourrissons ibuprofen suspension"` into
  `ibuprofen`). Risk: false positives (`"hydrocortisone topical for
  tickling"` matches both substances). Mitigations: (a) require
  word-boundary `\\b` so partial matches don't fire, (b) require all
  matched substance tokens to appear, (c) hand-validate against the
  top-20 audit before committing. Defer until UI toggle ships and we
  can A/B the granularity in practice.

## 2026-04-28 — Step 3 UI toggle shipped (faers-mobi)

`faers-mobi/app/view/signal_timeline.R`:

- Added `SIGNALS_DRUG_PATH` (`data/signals.parquet`) and
  `SIGNALS_SUBSTANCE_PATH` (`data/signals_substance.parquet`) constants;
  `SIGNALS_PATH` retained as compatibility default.
- New `radioButtons(ns("signals_mode"), …)` at the top of the table
  block, choices `drug` / `substance`, default `drug`. Inline radio with
  a help line explaining what each mode does and the long-tail caveat.
- `signals()` reactive now picks the path based on `input$signals_mode`,
  with a graceful fallback to drug-level if the substance file is
  missing (the substance parquet may not be deployed to the VPS yet).
- Imports: added `radioButtons` to the shiny imports list.
- Local symlink: `faers-mobi/data/signals_substance.parquet` →
  `~/data/signal-compute/substance/signals_faers_v2026-04-28.parquet`.

aers-mobi NOT changed: AERS contingency doesn't exist on this box, so
no AERS substance parquet can be built. aers-mobi stays on drug-level
only (which is also semantically correct — the dataset is closed and
substance rollup is never re-run for it).

### Boot + logic verification

- Parse-clean. Boot serves with toggle UI rendered; both radio choices
  visible in HTML.
- Track A aggregation against drug parquet: 1,408,403 pairs in 3.06s.
  Top peak: `ultra-technekow + Scan myocardial perfusion abnormal`.
- Track A aggregation against substance parquet: 788,927 pairs in 1.79s.
  Top peak: `sodium pertechnetate (99m tc) + Scan myocardial perfusion
  abnormal` — the consolidated substance behind `ultra-technekow` and
  related imaging-agent brands.
- The substance view's top row is the active ingredient, not the brand
  — exactly the outcome the substance compute was meant to produce.

### Track-summary table

| Step | Status |
|---|---|
| 1: Schema migration `rxnorm_name`/`outcome_name` → `drug`/`event` | ✅ shipped |
| 2: Multi-vocab search + brand→substance crosswalk | ✅ shipped |
| 3: Substance-level signal compute + UI toggle | ✅ shipped (faers-mobi) |

The user's three-step plan from 2026-04-28 is complete.

## 2026-04-28 — Three SCD-handoff opens addressed

### Item 3: agrep min-query-length guard shipped (both apps)

`.fuzzy_match_pairs` now declines to run agrep when the normalized query
is shorter than `AGREP_MIN_LEN <- 5L` chars. Exact substring still fires
at any length. Suppresses noise where short queries pulled edit-distance
matches against long lists.

Empirical recheck on the 2026-04-28 drug parquet:

| query (chars) | exact | fuzzy | total |
|---|---|---|---|
| `ozempic` (7) | 1 | 2 | 2 |
| `vioxx` (5) | 7 | 7 | 7 |
| `advil` (5) | 42 | 78 | 78 |
| `advl` (4) | 0 | 0 | 0 (guard fires; was 0 anyway) |
| `semaglutide` (11) | 9 | 18 | 18 |

The 5-char floor preserves typo support for "advil"/"vioxx"/"sertra" while
killing 4-char short-query noise. ozempic still hits clorazepic via
agrep at 7 chars — a deeper fix (length-ratio guard, tighter
max.distance) is queued under future plans, not blocking today.

### Item 2: CLASS_EFFECT_THRESHOLD_SUB constant + per-mode dispatch

Added `CLASS_EFFECT_THRESHOLD_SUB <- 3L` constant in faers-mobi;
`searchCols` expression in the DT now picks between
`CLASS_EFFECT_THRESHOLD` and `_SUB` based on `input$signals_mode`. Both
default to 3.

Empirical class_co_flags distribution profiling (2026-04-28 parquets):

| mode | drug-specific (=1) | ≥3 | ≥5 | ≥10 |
|---|---|---|---|---|
| drug | 35.0% (840/2000) | 42.8% (855/2000) | 27.0% | 10.1% |
| substance | 47.6% (952/2000) | 39.0% (779/2000) | 28.1% | 17.2% |

Distributions similar enough that one threshold (3) covers both modes
today. Constants kept separate so re-tuning is a one-line change. Side
note: threshold=3 now hides 43% of drug-level splash on the new 1.4M-pair
parquet vs 18% on the older 264k-pair parquet — may want to bump both to
5 in a follow-up. Flagged below.

### Item 1: deploy script ships substance parquet too

`signal-compute/scripts/deploy_to_vps.sh` now optionally scps the latest
`substance/signals_faers_v*.parquet` to the VPS as
`signals_substance.parquet`.

- New `SUBSTANCE_GLOB` pointing at `~/data/signal-compute/substance/`.
- Substance file is **optional** (warning, not abort, if missing) so the
  script remains usable for boxes that haven't run the substance compute.
- Echo lines updated to show drug + substance separately.
- Bash `-n` syntax-checked.

The deploy is **not auto-run**. User triggers
`./scripts/deploy_to_vps.sh faers-mobi` whenever they're ready. After a
deploy: the VPS will have both `signals.parquet` and
`signals_substance.parquet` in `/srv/shiny-server/faers-mobi/data/`, and
the toggle UI will work.

## 2026-04-28 — `window_data` cross-product partition-filter bug

User question "does FAERS have data where latest report is in 2025?"
surfaced a **silent data-loss bug** in `signal-compute/R/compute_quarterly.R`.

### Symptom

Signals parquet has only 117 of 143 dispatched quarters. Pattern:
1990Q1..2017Q4 all present (continuous), then only `2018Q4 / 2020Q4 /
2021Q4 / 2025Q3 / 2025Q4`. Most of 2018–2024 missing — including
2018Q1–Q3, all of 2019, 2020Q1–Q3, 2021Q1–Q3, all of 2022, 2023, 2024,
plus 2025Q1, Q2.

### Root cause

`window_data()` filtered the contingency dataset via
`year %in% years_filter, quarter %in% qs_filter` — a **cross-product
match on partition keys**. For windows spanning a year boundary (e.g.,
2018Q1's window = `c("2017Q2","2017Q3","2017Q4","2018Q1")`):

- `years_filter` deduped → `c(2017, 2018)`
- `qs_filter` deduped → `c("1","2","3","4")` (all four)
- Cross-product matched **8 partitions** (all of 2017 + all of 2018),
  not the intended 4. Empirical: 606,079 rows vs intended ~311,188.

Q4-of-year windows accidentally produced the right answer because all
4 labels of a Q4-anchored window are in one calendar year (years_filter
is one value, so the cross-product collapses to that year's 4 quarters).
That's why only Q4-of-year quarters survived in the 2018+ range.

The over-fetched windows then triggered `detect_all_methods` to fail or
return NULL silently (caught by tryCatch at line ~131 of compute_quarterly.R).
26 quarters were dropped without a log line. The "There were 50 or more
warnings" notice in E1's log was the only surface signal.

### Fix shipped 2026-04-28

`window_data()` now filters partitions by year only, then post-collect
filters on the constructed `YYYYQN` label:

```diff
-  years_filter <- as.integer(substr(qtr_labels, 1, 4))
-  qs_filter    <- substr(qtr_labels, 6, 6)
-  df <- ds |>
-    filter(.data$year %in% years_filter, .data$quarter %in% qs_filter) |>
-    collect()
-  if (nrow(df) > 0) df$quarter <- paste0(df$year, "Q", df$quarter)
+  years_in_window <- unique(as.integer(substr(qtr_labels, 1, 4)))
+  df <- ds |> filter(.data$year %in% years_in_window) |> collect()
+  if (nrow(df) > 0) {
+    df$quarter <- paste0(df$year, "Q", df$quarter)
+    df <- df[df$quarter %in% qtr_labels, , drop = FALSE]
+  }
```

Reads at most 2× partitions on year-boundary windows (cheap on Arrow);
filters correctly. Verified empirically:

| Window | Before fix | After fix | Notes |
|---|---|---|---|
| 2018Q1 (2017Q2..2018Q1) | 606,079 rows | 311,188 rows | **bug fixed** |
| 2018Q4 (2018Q1..2018Q4) | 479,395 rows | 479,395 rows | unchanged (window was already inside 1 year) |
| 2025Q4 (2024Q4..2025Q4) | n/a | 60,382 rows | small because 2025Q1/Q3/Q4 contingency tiny |

### Implications for previously shipped parquets

- `signals_faers_v2026-04-28.parquet` (drug-level, 1.79 GB) is
  **partially incorrect**: missing 26 quarters AND 2018Q4 / 2020Q4 /
  2021Q4 stats are computed against ~2× over-fetched windows, so peak
  EB05 / EWMA values for those three quarters are mis-scaled.
- `substance/signals_faers_v2026-04-28.parquet` has the same problem
  — same compute_quarterly.R, same bug.
- The substance contingency itself (`build_substance_contingency.R`)
  is fine. Bug is only in `compute_quarterly.R`.
- The deploy script wasn't run yet, so no production impact. Local
  symlinks point at the buggy parquets; will re-point once reruns finish.

### Reruns kicked off in parallel 2026-04-28 16:30

- **Drug-level rerun:** `Rscript R/compute_quarterly.R --source faers`,
  background task `bsfrfwumj`. Output will overwrite
  `signals_faers_v2026-04-28.parquet` in
  `~/data/signal-compute/`.
- **Substance-level rerun:** same script, with
  `--contingency-root .../contingency-substance` and
  `--output-root .../signal-compute/substance`, background task
  `bmdps5a9g`. Output will overwrite the substance parquet.
- ETA both ~5h (~21:30 local) running in parallel — ~12-14 GB RAM, 200% CPU.
  Box has handled the single-job baseline (~6 GB) fine, parallel should fit.
- Once finished: re-symlink, re-test, deploy.

## 2026-04-29 — safetysignal int32 overflow fix + Opus→Sonnet handoff

### safetysignal patch shipped

Root-cause of the 13 still-missing quarters (2019, 2022Q4, 2023, 2024)
was an int32 overflow at `safetysignal/R/detect-all.R:76` — the same
class of bug already fixed at `observed-expected.R:54`. `n_drug *
n_event` exceeds `.Machine$integer.max` (~2.1e9) on cumulative FAERS
data once enough years have accumulated; `dplyr::mutate` then propagates
NAs and the calling pipeline silently drops the affected quarter via
its tryCatch.

Patch: cast both sides + denominator to double:

```diff
-  expected = (.data$n_drug * .data$n_event) / n_total,
-  rr = .data$observed / .data$expected
+  expected = (as.double(.data$n_drug) * as.double(.data$n_event)) / as.double(n_total),
+  rr = as.double(.data$observed) / .data$expected
```

Committed as `1f54d4e` on `safetysignal/main`, pushed. Reinstalled into
`/home/harlan/R/x86_64-pc-linux-gnu-library/4.5/`. Verified on the
2018Q2..2019Q1 window: 502,439 pairs, 349,313 flagged in 3.5s (was
NULL pre-patch). The signal-compute nix dev shell loads safetysignal
from this same user library, confirmed via `system.file()`.

### VPS deploys (drug + substance + aers pre-patch)

- `faers-mobi`: drug + substance parquets pushed via
  `deploy_to_vps.sh faers-mobi`; new app code pulled via
  `cd /srv/shiny-server/faers-mobi && git pull` + restart. setNames
  unqualified-call hotfix shipped (`stats::setNames`).
- `aers-mobi`: schema-renamed `signals_aers_v2026-04-20.parquet` (drug/
  event), multiproduct labels, meddra_hierarchy, atc_classes,
  diana_dictionary, first_approval all scp'd; new app code pulled;
  restart. AERS data won't change again (closed dataset).

Both sites verified live (200 + new HTML strings present, shiny logs
clean post-restart).

### Opus → Sonnet handoff

User asked whether Sonnet 4.6 can finish the rest. Yes — the remaining
work is execution + monitoring, not design. Sonnet should pick up here.

**In-flight at handoff (started 2026-04-29 05:55):**

- Drug rerun: PID 4145666, command
  `Rscript R/compute_quarterly.R --source faers` from
  `/projects/signal-compute/`.
- Substance rerun: PID 4146181, same script with
  `--contingency-root .../contingency-substance --output-root
  .../signal-compute/substance`.
- Both expected to finish ~10:55–11:55 local (5–6h). Watcher (background
  task) fires when both exit. Output overwrites
  `signals_faers_v2026-04-29.parquet` in their respective dirs.

**Expected outcome (if patch works correctly):**

- 130 → ~143 quarters covered (recovers all of 2019, 2022Q4, all of
  2023, all of 2024). Some early sparse-contingency quarters may still
  return NULL by design — verify via
  `ds %>% distinct(quarter)` after both finish.
- Total rows likely ~25M+ (was 18.5M with 130 quarters).
- File size 3.0–3.5 GB (drug) and 2.5–2.8 GB (substance).

**Sonnet to-do when reruns finish:**

1. Verify quarter coverage with `distinct(quarter)` — should show no
   gap between 1990Q1 and 2025Q4 except 2025Q2 (which lacks
   contingency).
2. Update local symlinks: `faers-mobi/data/signals.parquet` →
   new drug parquet path; `signals_substance.parquet` → new substance.
3. Boot-test faers-mobi locally if you want, but app code didn't
   change so this is optional.
4. `cd /projects/signal-compute && ./scripts/deploy_to_vps.sh
   faers-mobi` to push fresh parquets to the VPS. The script already
   handles both files.
5. Verify VPS via `curl -s https://faers.mobi/` and check shiny logs
   on VPS for any new errors.
6. Append a "reruns landed" entry to DECISION_LOG.

If anything looks off (NULL where data was expected, schema drift,
deploy errors), surface to user before proceeding.

---

## 2026-04-29 — Reruns landed, full 143-quarter coverage deployed

### Status: COMPLETE

Both int32-fixed signal-compute reruns finished successfully:

- **Drug signals:** `signals_faers_v2026-04-29.parquet` — 3.2G, 24,070,569 rows, **143 quarters**, 1990Q1–2025Q4
- **Substance signals:** `substance/signals_faers_v2026-04-29.parquet` — 2.6G, 19,787,424 rows, **143 quarters**

All 13 previously missing quarters (2019Q1-Q4, 2022Q4, 2023Q1-Q4, 2024Q1-Q4) recovered by the `as.double()` int32-overflow fix in `safetysignal/R/detect-all.R` commit `1f54d4e`.

Local symlinks in `faers-mobi/data/` updated to v2026-04-29. Deployed to VPS at 23:39-23:41 UTC. VPS returns HTTP 200.

Note: a partial intermediate deploy ran at 07:16 Apr 29 with v2026-04-28 (130 quarters). That has been overwritten on VPS by this deploy.

---

## Open questions (remaining)

- **F1, G1, H1:** scoping decisions deferred — surfaced in master plan above.
- **Track B inference:** B3 validation + B4 batch built; inference runs blocked on RTX 3090 availability (~2026-05-04). When GPU lands: `Rscript tests/triage/b3_build_fixture.R` then `Rscript tests/triage/b3_validate.R --model qwen2.5:7b-instruct-q4_K_M` (need >=16/20 pass). If pass, run `Rscript scripts/triage_signals.R --resume`.

---

## 2026-04-30 — Items 1–4 complete

### Item 1: CLASS_EFFECT_THRESHOLD retune — DONE
Both constants bumped 3→5 in faers-mobi and aers-mobi. Reduces splash suppression from 43% hidden to ~27%, closer to pre-24M-row baseline.

### Item 2: agrep length-ratio guard — DONE
In `.fuzzy_match_pairs` (both apps): after agrep, discard hits where candidate name is >2.5x query length + 3 chars. Prevents shared-suffix false positives ("ozempic" → "clorazepic acid"). Short queries still get exact substring; this only tightens the fuzzy branch.

### Item 3: C5 Emerging window — DONE
Added `.subtract_quarters()` helper. `pair_stats_full` now computes `is_emerging = first_signal >= (max(latest_signal) - 4 quarters)` using the dataset's own max quarter instead of `Sys.Date()`. Added `Emerging` column (amber) to DT. aers-mobi gets no Emerging column (data ends 2012, confirmed by earlier boot-test).

### Item 4: Track B (LLM triage) — pre-GPU work DONE
- `signal-compute/tests/triage/b3_ground_truth.csv` — 20-pair truth table
- `signal-compute/tests/triage/b3_build_fixture.R` — builds parquet fixture from live data
- `signal-compute/tests/triage/b3_validate.R` — runs Ollama + checks pass criteria (≥16/20, no pq/ic→genuine-novel)
- `signal-compute/scripts/triage_signals.R` — B4 batch: reads signals parquet, enriches, classifies via Ollama, writes sidecar parquet; supports `--resume`
- Inference blocked on RTX 3090. Run B3 first once GPU arrives to validate prompt quality before B4 production run.


---

## 2026-05-03 — Issue triage: ajax-error + signal-disconnection

### ajax-error (aers-mobi DataTables Ajax error) — FIXED

ROOT CAUSE: `local({})` block inside `datatable(options=list(searchCols=...))` read `input$search_query` directly, bypassing the 400ms debounce. This added the raw input as a reactive dependency of `renderDataTable`, triggering a full re-render on every keystroke. With ~995k pairs in aers-mobi's substance view, server-side Ajax requests outlive the re-render cadence → in-flight conflicts → "DataTables Ajax error (tn/7)".

FIX: replaced `input$search_query %||% ""` with `search_query() %||% ""` (debounced reactive) inside the `searchCols` local block in both aers-mobi and faers-mobi. Branch: `fix/datatables-ajax-class-effect-filter` in aers-mobi. Same 1-line patch applied to faers-mobi on main.

TEST: `aers-mobi/tests/testthat/test-class-effect-filter.R` asserts that searchCols uses `search_query()` not `input$search_query`.

### signal-disconnection (MedDRA/ATC/DiAna version bridge) — OPEN, step 1 next

Open question from the issue resolved: **no MSSO license needed**. The `meddra_hierarchy.parquet` is UMLS-sourced (PT → CUI via UMLS REST API), and UMLS tracks CUI history across releases. Bridge work for step 4 (MedDRA event-side) can be built via UMLS history API without MSSO.

Steps 1–2 still gating. Step 1 = add version stamps to signals parquet (meddra_version, diana_version, atc_version at compute time). No external data dependencies — pure pipeline metadata. Ready to implement when prioritized.

## 2026-05-16 — pico-dag review-fix loop (4-model AskSage)

Ran multi-model review-fix loop on `/home/harlan/projects/pico-dag` to address user-reported issues with the DAG explorer: bare CUI labels, `isa`/`inverse_isa` jargon, Atrial Tumor (C0741300) procedures-tab/graph desync, star-pattern clutter, missing CSV grouping factor, sparse lab/procedure recall.

**Models:** claude-47-opus, gpt-5, gemini-2.5-pro, grok-4-20-reasoning.

**Commits:** baseline `3e158c9`, round-2 `bd14aa6`, round-4 `5936cc0`. Converged after 4 logical passes.

**What landed:** `umls_preferred_name` bulk resolver with mrconso fallback; `RELA_DISPLAY` table + `display_rela()`; `reclassify_by_sty` post-walk pass using MRSTY semantic type (38 types across 5 categories); `mrsty_typed_fallback` tier-4 densifier; `cluster_id` (igraph::components) on exported nodes.csv and edges.csv; `combine_dags::bind_distinct` keyed on `(from_cui, related_cui, rela)` (fixes click-to-extend edge loss); IN-list chunking at 500; namespaced GraphML keys; dead `umls_client.R` deleted; fix for `parent_drug_name` crash in `download_pull_request`.

**Open P0s surfaced, not auto-applied:** visNetwork `visClusterByGroup` UI toggle (cluster_id is in exports but not yet in the viz); `medrt_get_relations` synchronous RxNav latency on first walk (~10-30s); MRSTY-first vs rela-first as the primary classifier (currently rela-first with MRSTY corrector); Incognito-by-default for PHI; per-session DuckDB connection; telemetry coverage of the rendered graph.

**Reviews preserved** under `pico-dag/reviews/{round-2,round-3,round-5-convergence.md}` + `pico-dag/reviews/SUMMARY.md` for audit.

## 2026-05-16 — pico-dag P0 follow-ups (commit 77566f6)

User picked four of the six P0 items surfaced after the review-fix loop:

- **#1 viz clustering toggle (DO)** — visClusterByGroup with `checkboxInput("cluster_stars")` default OFF. .compute_cluster_ids moved to network_viz.R (shared with dag_export.R). Off-root components render as diamond cluster nodes when toggled on.
- **#2 medrt latency (UNDERSTAND FIRST)** — explained inline: NLM strips drug-disease relations from public RRF; medrt_rxnav.R hits NLM RxNav with 4 HTTP calls per CUI; first walk on unseen seed is 10-30s. Three resolution options offered, awaiting decision.
- **#3 mrsty-first classifier (WAIT)** — held per user request.
- **#4 Incognito default ON (DO)** — flipped value=FALSE → TRUE. Help text rewritten to opt-in framing. Clinical-research context warrants opt-in not opt-out.
- **#5 per-session DuckDB (FIX)** — umls_db_connect detects shiny::getDefaultReactiveDomain() and stores connection in session$userData with onSessionEnded teardown. Scripts/console keep using process-global.
- **#6 render telemetry (FIX)** — new summarize_dag_render() replays the same node/edge assembly + cap logic build_dag_network uses; dag_build event extended with n_rendered_nodes, n_rendered_edges, n_clipped_by_cap, cluster_count, n_unnamed_nodes, n_components_off_root, has_etiology.

Open: how to resolve medrt latency (prefetch only seed, async via future/mirai, or just progress-message wait). Awaiting user direction.

## 2026-05-29 — UMLS duckdb localized to this workstation

The UMLS Metathesaurus was **not** on this workstation — only the API key
(`UMLS_API_KEY`), the build scripts (`pico-dag/scripts/{download_umls.sh,build_umls_db.R}`),
and docs. The actual data lives on the VPS (`root@5.78.69.136`, the Hetzner host serving
globalpatientsafety.com + picodag) at `/srv/umls/umls.duckdb` (3.9 GB, built 2026-05-09).

- **Verified VPS db** — 14 tables, fully populated: mrconso 9,460,633 · mrrel 17,297,278 ·
  mrrel_bidir 34,594,556 · mrhier 10,998,526 · mrsty 3,876,927 · concept_preferred 1,381,424 ·
  concept_definition 297,836 · mrdef 479,504 · mrhier_cui_edges 586,199 · mrsat_loinc 6,002 ·
  mrdoc 3,673 · mrrank 947 · rela_inverse 1,040 · rel_inverse 12. The raw RRFs in
  `/srv/umls/rrf/` were partially cleaned post-build (only MRHIER/MRDEF/MRRANK remain), but
  MRCONSO/MRREL/MRSTY are all loaded into the duckdb — so the missing RRFs are moot.
- **Copied to** `~/data/umls/umls.duckdb` (scp from VPS). Verified locally: 14 tables,
  row counts match the VPS exactly. Opens read-only via duckdb/DBI from the global R library
  (not in this project's renv).
- **Wired up `/srv/umls`** — `build_umls_db.R` and the pico-dag local backend expect
  `/srv/umls/umls.duckdb`. Symlinked there (needs sudo, run by user):
  `sudo mkdir -p /srv/umls && sudo ln -sfn ~/data/umls/umls.duckdb /srv/umls/umls.duckdb`.

## 2026-05-30 — pico-dag VPS divergence is this project's review-fix work (not an "SCD agent" artifact)

Read the two pico-dag snapshots (`snapshots/2026-05-30-vps-code-divergence.md` + `…-claude-assessment.md`). They flagged ~1,200 uncommitted lines on the prod VPS and hypothesized an "SCD agent improvement" existing in exactly one place (urgent, unique).

**Finding (verified read-only in the local pico-dag repo):** the diverging files are *this project's* 2026-05-16 review-fix-loop work, already committed and pushed to `origin/main`. The three "COLLIDES" untracked files on the VPS (`dag_export.R`, `medrt_rxnav.R`, `telemetry.R`) were *created* by that loop and are now tracked upstream; the VPS at `d8f095b` predates them, so a file-copy deploy left them untracked. `d8f095b` is an ancestor of my baseline `3e158c9`; the 18 commits `d8f095b..origin/main` are my loop (`3e158c9 bd14aa6 5936cc0 8ceec96 77566f6`) + Harlan's 2026-05-29 fixes. `umls_client.R` (still modified on VPS) was deleted as dead code by the loop and is correctly untracked upstream — confirming the VPS tree is *behind*, not forked.

**Revised reading:** deploy-hygiene problem (code reached prod by scp/hand-edit onto a stale checkout instead of `git pull`), not a lost-masterpiece problem. Preserve-first is still right, but urgency downgraded. Cannot rule out a prod-only delta without one diff (`ssh root@5.78.69.136 'git diff --stat origin/main'`). Wrote the analysis to `pico-dag/snapshots/2026-05-30-vps-divergence-globalpatientsafety-agent-note.md`.

### 2026-05-30 (follow-up) — SCD agent reviewed; three snapshots now agree

The SCD agent read the globalpatientsafety note and updated the two pico-dag snapshots: added a "⚠️ CORRECTION" header to the primary (`2026-05-30-vps-code-divergence.md`) and a correction header + "Code & document locations" section to the claude-assessment note. All three now concur: VPS is ~18 commits *behind* `origin/main` via deploy-by-copy onto a stale checkout, not a forked unique artifact; **confirming diff is the agreed next step**; preserve-first before any reset.

Re-verified the SCD agent's two additions against the live repo — both correct, one sharper than mine:
- `git merge-base --is-ancestor d8f095b origin/main` → **true** (clean ancestor — stronger than my "ancestor of my baseline 3e158c9").
- The `umls_client` change is a **functional rename**, not a bare deletion: baseline `3e158c9` added `umls_client_duckdb.R` (tracked upstream), round-4 `5936cc0` deleted old `umls_client.R`. Justifies excluding `umls_client*` from the confirming diff (stale-vs-renamed add/delete noise). Aligned my note's table row + diff command to match.

Agreed confirming diff (read-only, run by globalpatientsafety agent): `ssh root@5.78.69.136 'cd /srv/shiny-server/pico-dag && git fetch -q origin && git diff --stat origin/main -- ":!.Renviron" ":!app/R/umls_client*"'`. Empty → capture-then-fast-forward; non-empty → genuine prod-only residual to preserve.

### 2026-05-30 (resolved) — confirming diff run; no prod-only delta, VPS is just stale

Ran the agreed read-only confirming diff on the VPS (`ssh root@5.78.69.136`, `git fetch` + `git diff --stat origin/main`; nothing changed). VPS HEAD still `d8f095b`. Result: **24 files, 117 insertions / 10,446 deletions.** The 10,446 deletions are origin/main content absent from the behind-by-18 checkout (reviews/, .asksage-archive.txt, scripts/, and the untracked dag_export/medrt_rxnav/telemetry read as missing by git diff). Inspected all 117 insertions line-by-line across code_lists.R, dag_walker.R, network_viz.R, app.R — **every line is an older form of code already in origin/main** (pre-rewrite purrr::map code-list generators, earlier bfs_walk/walk_concept_dag signatures, DOMAIN_COLORS/visGroups, telemetry field lists, privacy help text). **No novel functionality, no prod-only residual.**

**Conclusion:** VPS is a stale copy of already-committed/pushed work; the "1,200 uncommitted lines / unique artifact" reading is closed as not applicable. Recommended path (for the user to run on the VPS): (1) preserve branch `git checkout -b vps-snapshot-2026-05-30 && git add -A && git commit` (also captures the untracked collide files); (2) `git checkout main && git reset --hard origin/main`; (3) `systemctl restart shiny-server` + smoke-test; (4) fix workflow to deploy via `git pull`, never file-copy onto prod. Result recorded in the globalpatientsafety companion note's "Confirming-diff RESULT" section.

### 2026-05-30 (executed) — VPS preserved + fast-forwarded to origin/main

Ran steps 1–2 on the VPS (`root@5.78.69.136:/srv/shiny-server/pico-dag`):
- **Step 1 — preserve:** branch `vps-snapshot-2026-05-30` @ `3afe8cd` captures the full stale tree (incl. the untracked collide files and `.Renviron`). Local-only, **never pushed** (contains `.Renviron`). Needed a repo-local git identity (`deploy@globalpatientsafety.com`, not --global) to commit.
- **Step 2 — fast-forward:** `main` reset --hard from `d8f095b` → `origin/main` HEAD `560740d` (18 commits). `.Renviron` (untracked, secrets) was backed up to `/root/Renviron.vps-backup-2026-05-30` first because `git add -A` had committed it onto the snapshot branch (so a branch switch would have deleted it); restored after reset — back as `-rw------- shiny:shiny`, untracked.
- **Verified:** `git diff --stat origin/main` (excl `.Renviron`) is empty (tree identical to upstream); `dag_export.R`/`medrt_rxnav.R`/`telemetry.R`/`umls_client_duckdb.R` now tracked+present; stale `umls_client.R` removed; preserve branch intact.

**Not done (left for user):** step 3 `systemctl restart shiny-server` + smoke-test `picodag.globalpatientsafety.com`; step 4 fix deploy workflow to use `git pull`. `vps-snapshot-2026-05-30` and `/root/Renviron.vps-backup-2026-05-30` can be deleted once the restart is confirmed healthy.

### 2026-05-30 (deployed) — shiny-server restarted, smoke-test passed

Step 3 done. `systemctl restart shiny-server` on the VPS → service `active (running)` since 10:15:46 UTC. Smoke-test: `https://picodag.globalpatientsafety.com/` returns **HTTP 200** (35 KB, shiny page). Fresh app log `pico-dag-shiny-20260530-101605` shows a clean R startup (tidyverse attached, "Listening on 127.0.0.1:33913", no errors/Terminated) — i.e. a real session launched on `origin/main` code (`560740d`).

pico-dag VPS is now fully deployed at `origin/main` and healthy. Remaining: step 4 (switch deploy workflow to `git pull`); optional cleanup of `vps-snapshot-2026-05-30` branch + `/root/Renviron.vps-backup-2026-05-30` now that the restart is confirmed healthy.

### 2026-05-30 (step 4 done) — git-pull-only deploy script + prod-edit ban

Root-cause fix for the divergence, committed to pico-dag `origin/main` (HEAD now `f1c7643`):
- **`scripts/deploy.sh`** — canonical deploy (git fetch → guard → `git pull --ff-only` → restart → HTTP 200 smoke-test). Guard refuses to deploy only on real hazards: modified/deleted *tracked* files, or untracked files that collide with a path `origin/main` tracks; harmless runtime untracked files (app_cache/, logs, .salt, .Renviron) don't block. (Fixed two iterations: too-blunt "any dirty" guard, then a `set -e` propagation bug in the `git cat-file -e` collision check.)
- **`CLAUDE.md`** — Deployment section: flow is commit → push → `scripts/deploy.sh`; **never edit/scp/rsync onto the prod clone**; deploy.sh aborts on a dirty prod tree by design.
- **`.gitignore`** — added `app/app_cache/`, `.Renviron`, `app/logs/.salt`.

Validated end-to-end: deploy.sh fast-forwarded VPS `560740d → f1c7643`, restart OK, smoke-test HTTP 200.

**Manual cleanup due ~2026-06-06** (no automated routine — a cloud routine can't SSH the VPS): once prod is confirmed healthy, on the VPS run `cd /srv/shiny-server/pico-dag && git branch -D vps-snapshot-2026-05-30 && rm -f /root/Renviron.vps-backup-2026-05-30`. These are the only recovery artifacts left from the divergence cleanup; the snapshot branch holds `.Renviron` so it was never pushed.

## 2026-06-13 — Cotton deploy note corrected; article registered

**Finding:** the prior `articles/DEPLOY-christine-cotton.md` blocker was wrong. It
claimed the publication mechanism lived on the VPS and required inspecting the live box
(and that the site was Shiny, needing `touch restart.txt`, rendered on the box). In
fact publication is fully in-repo and static:
- `app/logic/articles.R` (`ARTICLES` tribble, `featured = TRUE` flag) = source of truth.
- `app/static/<id>.html` = rendered Quarto input.
- `scripts/build_static_site.R` builds `static_site/`; deploy is
  `rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/`.
- The `articles/shingles.md` stub misled the prior note — the live shingles article is
  `app/static/shingles.html`, not that stub.

**Real blockers (both repo-local to fix, not "inspect the box"):** (1) no local
`quarto`/`rmarkdown` (only `knitr`) to render the qmd → `app/static/christine_cotton.html`;
(2) SSH for the final rsync (`ssh-copy-id` the existing GitHub key — do NOT regenerate it).

**Action taken:** registered the article in `app/logic/articles.R` as id
`christine_cotton`, `featured = TRUE`; flipped `shingles` to `featured = FALSE`.
Rewrote `DEPLOY-christine-cotton.md` to the corrected mechanism + step list.

## 2026-06-13 — Cotton article rendered + site built locally (only SSH/rsync remains)

Added `pkgs.quarto` + `pkgs.rPackages.gt` to `flake.nix`, then rendered
`articles/christine-cotton-vaers.qmd` → `app/static/christine_cotton.html` and ran
`scripts/build_static_site.R`. Verified: Cotton is the ★ featured card on the landing
page, 16 gt tables intact, all inline EB05 numbers present, `/articles` lists all three.

**Two non-obvious env vars are required to render in the nix shell** (now documented in
the deploy doc):
- `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE` — the project's renv `.Rprofile` shadows the
  nix R library, so `library(gt)`/arrow/dplyr are invisible until the autoloader is off.
- `QUARTO_R="$(command -v Rscript)"` — without it quarto runs `/usr/bin/Rscript` (system
  R), which dies on a GLIBC mismatch under the shell's `LD_LIBRARY_PATH`.
Harmless `jog.lua: Don't know how to traverse TableBody` errors print per gt table; output
is correct regardless. Pre-existing harmless sprintf warning in `build_static_site.R`'s
`NAV_INJECTION()` (arg passed to a template with no `%s`) — not fixed (out of scope).

Only remaining blocker: SSH access for `rsync static_site/ root@5.78.69.136:...`.

## 2026-06-13 — Cotton article: embed-resources fix + gitignores

The first render referenced an external `christine-cotton-vaers_files/libs/` dir (12
refs, 84 KB) — would deploy with broken CSS/JS, since `build_static_site.R` ships only
the single `<id>.html`. The working articles (shingles, covid_vaccine) are self-contained.
Fix (the real one, matching the working pattern): added `embed-resources: true` to the
qmd `format.html`. Must render **from inside `articles/`** (not repo root) or the embed
post-process fails with `NotFound … quarto-html/quarto.js` (libs dir resolves relative to
cwd). Result: `app/static/christine_cotton.html` is now 1.56 MB, 0 `_files/` refs, 16 gt
tables, all EB05 numbers present.

Gitignored: `static_site/` (build output, root `.gitignore`); `*_files/` and `*.html`
in `articles/.gitignore` (render artifacts — the canonical HTML lives in `app/static/`).

## 2026-06-13 — Grok review of Cotton article + fixes applied

Ran asksage-review (grok-4-20-reasoning; `xai-grok` is retired) on the rendered article.
Grok rated it competent on method but reading as "memorial advocacy" with legal/reputational
risk. Verified two concrete methodology claims against the source and confirmed both:
- **Threshold inconsistency:** cardiac/thrombotic/stroke used EB05 ≥ 2.0 but menstrual used
  ≥ 1.5 with no justification (outcome-dependent thresholding).
- **Procedural codes in clinical tables:** `cardiac|heart` / `coagulat` filters swept in
  MedDRA Investigations/procedure PTs (Magnetic resonance imaging heart, Cardiac stress/
  function test, Catheterisation cardiac, Cardiac imaging procedure, Coagulation test).

Fixes applied to `articles/christine-cotton-vaers.qmd`:
- Single pre-specified rule `EB_THRESHOLD <- 2.0` + `proc_exclude` regex, applied uniformly
  to all four categories; procedural/investigation PTs excluded from clinical-event tables.
- Attribution/voice pass: headings → "Cotton's Claims About the Trial",
  "VAERS Disproportionality in the Categories Cotton Flagged", "What This Can and Cannot Say";
  reattributed her benefit-risk thesis to her (Pfizer disputes, no regulator adopted, post
  takes no position); removed site-voice endorsements ("She was looking in the right direction").
- Added scope statement: this is an honest application of one method to VAERS (US passive
  surveillance), NOT a benefit-risk verdict; other surveillance systems are independent and
  out of scope (per user — they are independent of this study).
- Added conflict-of-interest disclosure (faers.mobi / GPS DB is the publisher's own tool).

**Did NOT apply** Grok's fix #3 (add a "broader evidence base / other studies upheld benefit-
risk" section): per user, those studies are independent of this analysis and out of scope; the
article's purpose is to honestly apply a methodology, not to adjudicate truth. **Could not apply**
Grok's "report case counts": the deployed parquet has only 4 columns (drug, event, eb05,
n_methods_flagged) — no observed/count column — so counts would need a richer redeploy.

Re-rendered self-contained (1.56 MB, 0 _files refs, 16 gt tables, inline EB05 numbers resolve),
rebuilt static site, Cotton still featured. Grok review saved at
`articles/reviews/christine_cotton-review-grok.md`.

## 2026-06-14 — MedDRA SOC mapping ("D2") was never built; SSH key root cause

**"Thought it was fixed" — it wasn't.** Searched the whole machine: all three
`meddra_hierarchy.parquet` files (`~/data/diana/`, `faers-mobi/data/`, `aers-mobi/data/`)
are the same 4-column file (`pt, cui, synonyms, definition`) — no SOC. `fetch_meddra_hierarchy.R`
only fetches CUI + synonyms via UMLS REST for the novelty check; it was never written to fetch
the SOC hierarchy. The PT→HLT/HLGT/SOC walk is the open "D2" task (AGENT_HANDOFF_2026-04-28,
DECISION_LOG entries above), always logged pending. `SEARCH_REDESIGN.md:370` wrongly stated the
app "already loads meddra_hierarchy.parquet which maps PT → … → SOC" — corrected 2026-06-14 with
an inline status note (that false line is almost certainly the source of the "it was fixed" memory).

**What it takes to finish D2 (authoritative, no LLM):** build PT→{HLT,HLGT,SOC} for all outcome
PTs from a complete MedDRA hierarchy — either a full UMLS `MRHIER` extract (the local `umls.duckdb`
covers only ~9,295/26,823 MDR PT CUIs ≈ 35%; needs a complete re-extract) or licensed MedDRA
`mdhier.asc`. UMLS license already covers MedDRA-in-Metathesaurus for non-commercial use, so the
full UMLS extract is the fastest authoritative path; no MSSO wait required. The dual-model LLM
classification (qwen3:14b + gemma4:12b-q8, validated NOISE precision 0.987/0.990) is the bridge
until D2 lands.

**SSH-to-VPS root cause (why deploy broke).** `~/.ssh/id_ed25519` was regenerated **2026-06-09**
(file mtime). The new key was added to GitHub (push works this session) but **never added to the
VPS** (`root@5.78.69.136`) authorized_keys — the box still trusts the pre-Jun-9 key, which no
longer exists locally. `known_hosts` has 0 entries for the IP (also reset). Fix = add the current
pubkey to the VPS (needs VPS root password, so user must run it): `ssh-copy-id -i
~/.ssh/id_ed25519.pub root@5.78.69.136`, or paste the pubkey via the Hetzner console. Do NOT
regenerate the key again — it is now the working GitHub key.

## 2026-07-02 — "Claude Tag"-style autonomous agent loops (3 loops)

Modeled the Claude Tag pattern (a persistent agent triggered by mentions,
schedules, and ambient signals) as three self-running loops for this site,
since Claude Tag itself is Slack-bound + Enterprise/Team only.

1. **Telemetry loop (local cron).** `crontab`: Mondays 08:23 local →
   `scripts/telemetry/weekly_telemetry_review.sh`. Pulls nginx + shiny-server
   logs from the VPS (root@5.78.69.136) via `scripts/telemetry/pull_vps_logs.sh`,
   pre-aggregates them (`logs/telemetry/summary-*.txt`), then a headless
   `call-claude.sh --thorough` writes `logs/telemetry/report-<date>.md`
   against `prompts/telemetry_review_prompt.md`. Raw logs contain visitor IPs
   → gitignored (`logs/telemetry/raw/`, `summary-*`, `cron-*`). Report is
   report-only; no site changes.
2. **Reflection routine (cloud).** claude.ai routine `gps-weekly-reflection`
   (id trig_01HjzJN6HePBUyoTvoprEGDX), Opus 4.8, Wed 13:03 UTC. Reviews the
   repo, opens a PR adding `issues/agent-review-<date>.md` (top-3 improvements,
   evidence-cited). Report-only via PR; no deploy.
3. **Research routine (cloud).** routine `gps-weekly-research`
   (id trig_014RfF59TcvLqtA51Pw5i6fq), Opus 4.8, Fri 13:07 UTC, PubMed MCP +
   WebSearch/WebFetch. Opens a PR adding `articles/proposals/<date>-ideas.md`
   (3-5 sourced article ideas). Propose-only; no full articles, no deploy.

**Design decision: autonomy stops at the PR boundary.** All three produce
reports/PRs; a human merge + the existing multi-model review remain the release
valve. No loop self-deploys to the live public-health site.

**VPS access (resolved 2026-07-03).** This Linux workstation had **no** key on
the VPS — the VPS was provisioned and is deployed to from a **Mac**, whose key
is authorized; this box's `id_ed25519` (created Jun 9, after the April deploy)
was never added. Fixed by adding this box's public key
(`ssh-ed25519 ...harlananelson@gmail.com`) to the VPS's
`/root/.ssh/authorized_keys` (Harlan did it via a working session after a
Hetzner root-password reset). Verified: key-based `ssh root@5.78.69.136`
succeeds from this box; `pull_vps_logs.sh` ran end-to-end and produced
`logs/telemetry/summary-2026-07-03.txt`. Log paths confirmed as
`/var/log/nginx/access.log*` + `/var/log/shiny-server/*.log`. All three loops
now operational.

## 2026-07-05 — FAERS pipeline: "missing 2025Q2" is really whole-2025 dropout + non-reproducible mixed-run state

Investigated FAERS/VAERS data cleaning+updating. Initial hypothesis (2025Q2 = a
localized parse failure) was WRONG. Fable grounded-review (call-claude -m
claude-fable-5, on faers-pipeline) overturned it; every claim verified against code+data:

- **Contingency partitions on EVENT date, not filing quarter** (`contingency.R:206`
  `date_to_quarter(event_dt)`). On-disk FAERS rows/quarter: 2023 ~130-209K, 2024
  174K→60K (decaying), **2025 Q1=6, Q2=0(absent), Q3=1, Q4=9**. The raw 2025Q2 zip
  parses fine (52,366 reports with 2025Q2 event dates) — the data exists but never
  reaches contingency. So it's a whole-2025 dropout, not a Q2 parse bug.
- **On-disk tree is a patchwork of ≥2 runs** (a modern-scope run w/ 2024 data + a
  legacy 2004-2012 backfill). Independent confirmation: `arrow::open_dataset()` FAILS
  — `quarter` partition has incompatible types across partitions (string vs int32).
  Writer (`contingency.R:224-235`) never deletes stale partitions → runs interleave.
  **Pipeline is not reproducible run-to-run.**
- **Silent failure baked in:** `error="continue"` (`_targets.R:50`) skips errored
  per-quarter branches while reporting success.
- **Latent corruption bug:** dedup `slice_max(caseversion)` (`_targets.R:141`) on a
  CHARACTER column (`cols(.default="c")`, `parse_faers_raw.R:60`) → lexicographic
  `"9">"10"`, keeps wrong report version across the modern era.
- Doc drift: README references `R/download.R` (actual: `download_fda.R`/`download_vaers.R`).

**Revised plan (supersedes "re-parse 2025Q2"):** (1) state hygiene — per-source
targets store, pinned quarter window, cleaning writer, `error="stop"`, fix character
caseversion dedup; (2) one clean full-history run + per-quarter row-count verify;
(3) recompute+redeploy signals with a row-count gate vs current deploy; (4) noise-PT
filter = FLAG not DROP (Investigations-SOC "noise" often earliest drug-toxicity signal;
deterministic SOC backbone, LLM labels human-reviewed suggestions only, never filter at
signal-detection layer).

**Tooling note:** Grok (call-grok) could NOT complete this review — 6 attempts, all
configs; trivial prompts return but substantive ones come back empty (CLI-level
failure, not auth). Use asksage-review for a Grok-4 cross-check instead.

## 2026-07-05 — Noise-PT rescue: MedDRA-derived data kept out of the PUBLIC repo

Rescued the stranded June-2026 VAERS noise-PT classification (was uncommitted CSVs in
`articles/reviews/`, generating script lost). Decision: the repo is **public** and
`vaers_pt_soc_map.parquet` + the `deterministic_soc` labels encode the **MedDRA PT→SOC
hierarchy (licensed IP)**, so the DATA must NOT be committed — same convention as
`~/data/diana/meddra_hierarchy.parquet` (symlinked, never committed).

- Durable backup + provenance README → `~/data/faers-pipeline/noise-pts/`.
- `.gitignore` guards the 6 `articles/reviews/` files (5 data + the personal MSSO email).
- Committed doc-only pointer: `docs/noise-pt-classification.md` (methodology, schemas,
  FLAG-not-DROP integration plan). Branch `noise-pt-rescue` → merged to main.
- Data-quality note: CSV comma-quoting bug hits ~20-30 rows in EACH of the 3 CSVs (not 4);
  qwen preds have 40 `?` rows.
- **Open:** integration (an `is_low_information_pt` flag in the signal table) is a
  follow-up, gated on the MedDRA licensing question (does the UMLS license cover MedDRA?
  — being verified).

## 2026-07-05 — Pipeline repro fixes implemented (branch) + MedDRA email v2 drafted

- **faers-pipeline** branch `pipeline-repro-fixes` (pushed): `error="stop"`, integer
  `caseversion` dedup, per-source targets stores (`_targets.yaml` + `scripts/run_pipeline.R`),
  explicit `scripts/clean_contingency_source.R`, and `docs/pipeline-repro-fixes.md`.
  Found PRE-EXISTING uncommitted work there = in-progress **legacy-AERS 2004-2012 backfill**
  (`download_fda.R`, `parse_faers_raw.R`) — the source of the interleaved on-disk state;
  left it untouched, my fixes complement it. **Pipeline NOT run** (clean rebuild is
  destructive + long; do it after the legacy parser is committed/stable). OPEN decision:
  event-date vs filing-quarter partitioning.
- **MedDRA email v2** drafted at `articles/reviews/meddra-email-2026-07-05-draft.txt`
  (gitignored — personal). Honest about the monetization trajectory: asks MSSO for the
  non-commercial category NOW, what public display is permitted, and the path/cost to a
  future Commercial subscription. Framed to avoid claiming non-commercial while planning to
  monetize (see [[meddra-umls-licensing]]: UMLS covers internal use, NOT publishing).

## 2026-07-05 — FAERS clean rebuild verified; filing-quarter fix works; merged

Ran clean FDA rebuild 2018Q1-2025Q4 (isolated _targets-fda store; old contingency
moved to source=faers.pre-rebuild-2026-07-05, recoverable). Result: **2025 sparseness
FIXED** — 2025 Q1/Q2/Q3/Q4 = 318,967 / 327,016 / 384,245 / 386,782 rows (were 6/0/1/9
under event-date partitioning). Whole 2018-2025 series consistent (~300-390K/quarter),
10.1M rows / 31 quarters. Merged `pipeline-repro-fixes` (+ legacy-AERS commit) to
faers-pipeline main (7097554).

**Two follow-ups before recomputing/deploying signals:**
1. **2018Q1 absent** — series starts 2018Q2 (31 quarters, expected 32). One-quarter
   edge to diagnose (parse or filing_quarter tag for that branch).
2. **many-to-many join warning** (3 targets) — the drug-dictionary join in
   build_quarterly_contingency_fda detected many-to-many (dict_dedup should be
   1-row-per-drug_raw). Could inflate `observed` counts; investigate before signals.

Scope note: rebuild is modern-only (2018-2025). Deep history (legacy AERS 2004-2012Q3,
present raw) + the 2013-2017 raw gap are deferred; live app signals NOT yet recomputed/
redeployed (separate gated step).

## 2026-07-07 — FAERS 2018Q1 recovered; contingency now complete 32/32 quarters

2018Q1 was missing not from a bad download but a parser bug: FDA ships 2018Q1 as a
corrected re-release named `DEMO18Q1_new.txt`; the strict `...Q1.txt` regex missed it and
`parse_faers_table` returned 0 rows (a 3rd silent-drop path, uncaught by error="stop"
because it warned rather than errored). Fix (faers-pipeline c483130): regex allows optional
`_<alnum>` suffix (prefers suffixed file if both present); no-file-match is now a hard
`cli_abort`. Full re-run 2018Q1-2025Q4 verified: **32/32 quarters, 2018Q1=298,574 rows,
10.42M total**, 2025 fix intact.

STILL OPEN before recompute/deploy signals: the many-to-many drug-dictionary join warning
(may inflate `observed`); deep history (legacy AERS 2004-2012 + 2013-2017 raw gap).

## 2026-07-07 — Many-to-many join warning: diagnosed BENIGN (resolved)

The contingency_v1/_final warning is the intended drug×event enumeration within a report
(drug_f ⋈ reac_f on primaryid; a report has many drugs AND many reactions), NOT the
drug-dictionary join (that has explicit many-to-one). `distinct(primaryid, rxcui,
outcome_name)` before `count()` makes each report contribute exactly 1 per pair — verified
empirically (2025Q2 busiest report 249916714: 196 pairs, max per-report contribution to any
pair = 1). NO count inflation; `observed` values are correct report counts. Annotated the
join `relationship="many-to-many"` to document intent + silence the warning
(faers-pipeline f084ff6). No output change, no re-run. Open items now: recompute/deploy
signals; deep history (legacy AERS + 2013-2017 gap).

## 2026-07-07 — Work queue (in order)

1. **(in progress)** Recompute signals from clean 32-quarter contingency (compute_quarterly.R,
   CPU, running) → verify → `deploy_to_vps.sh` to faers.mobi. Note: new signals cover
   2018-2025 (clean); replaces the older mixed-history deploy — live-app time axis shrinks.
2. **CI fix** — Rhino Test red on EVERY push since ~2026-04-24 (pre-existing, unrelated to
   this session). Causes: (a) CI renv restore not installing `rhino` (renv.lock DOES pin it),
   (b) `.rhino/` dir absent → Cypress step fails on missing `.rhino/package-lock.json`. Does
   NOT block deploy.
3. **Parallelize safetysignal** — compute uses 1 of 16 cores, zero parallelism. Do option 2
   first: parallelize the per-drug-event-pair loop inside safetysignal (method-PRESERVING,
   same numbers, `furrr`/`mclapply`/data.table), benchmark. Cross-quarter parallelism is
   blocked by the cumulative prior (sequential dep); only unlocked by switching to
   `per_window`, which CHANGES the statistics — user's methodological call, not automatic.

## 2026-07-08 — Signals recomputed + redeployed (consistent 2018-2025 vintage) ✓

Queue item 1 DONE. Recomputed drug + substance signals from the clean 32-quarter
contingency, regenerated dicts, deployed all together.
- Drug: signals_faers_v2026-07-08.parquet (25.4M rows, 32 qtrs, 2025 populated).
- Substance: substance/signals_faers_v2026-07-08.parquet (19.1M rows, 32 qtrs).
- Dicts regenerated surgically from cached Jul-7 targets (fda_reac_all 46.0M rows,
  drug_dictionary 499,605) — the pipeline's dict targets carried a stale Jul-5
  timestamp; rewrote via write_*_parquet on tar_read'd objects (no 30-min rebuild).
- deploy_to_vps.sh → faers.mobi; VPS signals.parquet == local (3,606,302,954 bytes),
  both sites HTTP 200 after shiny-server restart.

**BUG FOUND (worked around, needs permanent fix):** build_substance_contingency.R has
the SAME non-cleaning-writer bug as the main pipeline — it left April's 1990-2017
substance partitions on disk (would have polluted substance signals with stale pre-2018
data). Worked around by mv-ing the stale tree aside before rebuild. Permanent fix: add a
clean-before-write (or explicit clean step) to build_substance_contingency.R. Stale tree
backed up at contingency-substance/source=faers.pre-rebuild-2026-07-08.

**Note:** live app time axis is now 2018-2025 (was deeper mixed history). Deep history
(legacy AERS 2004-2012 + 2013-2017 raw gap) remains a deferred item.

## Work queue (updated)
1. ~~Recompute + redeploy signals~~ ✓ DONE
2. CI fix (Rhino Test red since ~2026-04-24)
3. Parallelize safetysignal (per-pair, method-preserving; benchmark before per_window)
4. Fix build_substance_contingency.R non-cleaning writer (new; found during deploy)
5. [conditional] GPU disproportionality engine — see signal-compute/docs/gpu-disproportionality-design.md

## 2026-07-09 — build_substance_contingency.R non-cleaning writer FIXED ✓

Queue item 4 done. Added clean-before-write to build_substance_contingency.R
(signal-compute): wipes the destination `source=<name>` subtree before the
per-quarter rebuild so stale partitions from a prior wider-history build can't
survive. Verified idempotent: clean-rebuild logs "32 existing partition(s)"
cleaned, outputs 32 (not 144). Stale backup contingency-substance/
source=faers.pre-rebuild-2026-07-08 can be deleted once confirmed unneeded.
Queue now: 2 (CI fix), 3 (safetysignal parallelization), 5 (conditional GPU).

## 2026-07-09 — CI fixed: Rhino Test green ✓ (queue item 2)

Root cause: renv.lock drifted behind Posit PPM `latest` (16 pkgs), so
renv::restore() 404'd on the first and installed nothing -> every rhino::* step
failed. Fixed by making the lockfile coherent (bumped 16 to the 2026-07-08
frozen-snapshot versions) and pinning CI restore to jammy/2026-07-08 (durable).
Then: fixed the stale boilerplate test (checked output$message from before the
portal redesign -> smoke test); styler + box-import hygiene; .lintr relaxations
for content line-length + UPPERCASE constants + FOUR false-positive/contradictory
linters (box_mod_fun_exists, unused_declared_object [flagged USED objects like
VACCINE_COLOURS/thromb/cardiac], box_universal_import [conflicts with
func_import_count(8) for Shiny UI], box_pkg_fun_exists [flags exported dplyr fns
+ can't resolve local safetysignal]).

Notes for later:
- Local nix box.linters version < CI's (rhino 1.12.0) caused one extra iteration.
- signal_engine.R / signal_table.R are LEGACY, unused by the portal, and import
  `safetysignal` which isn't in renv.lock — candidates for removal.
- renv::status() reports out-of-sync (16 bumped pkgs had Hashes dropped) — cosmetic.

Queue: 3 (parallelize safetysignal), 5 (conditional GPU). Item 4 (substance
writer) done. Items 1,2 done.

## 2026-07-09 — safetysignal parallelized (queue item 3) ✓

Parallelized posterior_percentile()'s per-pair uniroot solve (the compute
bottleneck, 3 calls/window) with parallel::mclapply — method-PRESERVING
(deterministic, identical output). Controlled by options(safetysignal.cores=N),
default detectCores()-1, serial on non-unix / below 2000 pairs.
Verified: parity test added + passing; benchmark 7.21s->1.11s = 6.5x on 15 cores
(50k pairs, 0 NA drift). Full safetysignal test suite passes. safetysignal
main = 2bc703c. Deployed signals UNCHANGED (speed-only).

**Deployment note:** signal-compute must pick up the new safetysignal (flake
input / reinstall) for the pipeline to get the speedup. per_window prior strategy
(the statistics-changing cross-quarter parallelism) intentionally NOT done —
user's methodological call.

Queue: only item 5 (conditional GPU) remains — gated on whether 6.5x CPU is
enough. See signal-compute/docs/gpu-disproportionality-design.md.

## 2026-07-09 — safetysignal parallel version installed live; GPU PoC started

- **safetysignal reinstalled** into the user library (R CMD INSTALL from source);
  installed pkg now has `.ss_cores` -> pipeline uses the parallel version on next
  compute. (It loads from ~/R/.../4.5/, NOT nix/local-source, so a source reinstall
  is required to roll out safetysignal changes — remember this.)
- **GPU PoC (item 5) begun** in ~/projects/gpu-disprop-poc/: generated a 50k-pair
  ground-truth (parity_params.parquet: posterior params + safetysignal eb05), and
  wrote eb05_gpu_poc.py — a JAX float64 batched bisection over gammainc computing
  the mixture-posterior 5th-percentile (EB05). Installing jax[cuda12] (driver
  590.48/CUDA13.1). Next: run -> prove parity vs safetysignal + benchmark GPU vs the
  7.21s serial / 1.11s CPU-parallel baseline. Still a PoC, not a committed package.

## 2026-07-09 — GPU PoC: numerics VALIDATED; CUDA env is the only blocker (item 5)

Ran the GPU eb05 proof-of-concept. Result: a JAX float64 batched bisection over
gammainc reproduces safetysignal's EB05 (5th-pct of the 2-component Gamma mixture
posterior) to **max abs 2.5e-9 / max rel 6.4e-7** over 50k pairs. The hardest
question for the whole GPU idea — does batched bisection reproduce the exact
statistic? — is answered YES. Core algorithm de-risked.

**Blocker (infra, not numerics):** pip `jax[cuda12]` on this Nix-Python box imports
but falls back to CPU (`cuInit error 303` — libcuda/driver not exposed to the pip
jaxlib). GPU access needs Nix↔driver integration (nix flake with jax+CUDA, or
nixGL). PoC preserved: signal-compute/poc/ (eb05_gpu_poc.py, gen_reference.R,
README) + design note signal-compute/docs/gpu-disproportionality-design.md.

**Decision:** the full GPU engine (build the JAX package + CUDA env + parity suite)
remains a deliberate multi-week investment, gated on whether the LIVE 6.5x CPU
parallelization is insufficient. Numerics + kernel + design are ready when wanted.

## PLAN COMPLETE (items 1-4 done; item 5 PoC done, full build gated)

## 2026-07-10 — Loose ends closed

- Removed dead modules app/logic/signal_engine.R + app/view/signal_table.R
  (unreferenced by the portal, no tests). Their uninstalled `safetysignal`
  import was the ONLY box_pkg_fun_exists trigger, so re-enabled that linter in
  .lintr (one fewer suppression). CI green (dc6cca7).
- safetysignal flake "bump": N/A. signal-compute's flake provides bare pkgs.R +
  R_LIBS_USER (user library), not nix-pinned R packages. The parallel
  safetysignal is already installed in the user lib (R CMD INSTALL 2026-07-09),
  so the pipeline already uses it. No nix change to make.

## 2026-07-10 — CUDA-on-Nix environment SET UP (nixGL); GPU EB05 39x

The GPU env blocker is solved. Root problem: nix-on-Ubuntu — pip jaxlib needs the
host driver's libcuda, but adding /usr/lib to LD_LIBRARY_PATH pulls system glibc
and breaks every nix binary (nix glibc 2.42 vs Ubuntu's). Fix: **nixGL**
(`nix run --impure github:nix-community/nixGL#nixGLNvidia`, NIXPKGS_ALLOW_UNFREE=1)
bridges the host driver to nix userland without the glibc clash. Reproducible via
`signal-compute/poc/run-gpu.sh` (creates pip venv from requirements.txt, runs under
nixGL) — verified from a CLEAN venv end-to-end.

Result (50k pairs): jax.devices() -> CudaDevice(id=0); EB05 parity vs safetysignal
2.5e-9; **183 ms GPU vs 7210 ms serial (39x) vs 1110 ms 15-core CPU (6x)**.

GPU-engine gates now BOTH cleared (numerics + env). Remaining = straight engineering
(generalize kernel to eb50/eb95 + prior fit + PRR/ROR/IC, parquet I/O, parity/golden
suite). Env facts: driver 590.48/CUDA13.1, float64 required, card shared w/ Ollama
(MEM_FRACTION=0.4). See signal-compute/poc/ + docs/gpu-disproportionality-design.md.

## 2026-07-11 — Full GPU disproportionality engine built + validated (item 5)

Built ~/projects/gpudisprop: a GPU reimplementation of the signal-compute +
safetysignal compute step, same signals_*.parquet schema. Modules: prior (NumPy EM,
exact R parity), oe (polars marginals/2x2), gpu (JAX float64: posterior weight,
EB05/50/95 batched-bisection over gammainc, PRR/ROR/IC), detect (multi-method +
flags), pipeline (windowing, cumulative/per_window prior, incremental EWMA, streaming
parquet). Git: local repo (NOT pushed — new-repo/publish is user's strategic call
given the monetization angle).

**Validated vs safetysignal (two suites, both pass):**
- per-method: prior EM to 1e-15, EB to 2.5e-9, PRR/ROR/IC machine precision, all
  flags 0 mismatches (3266 pairs).
- end-to-end vs signal-compute: 7948=7948 rows, worst rel 8e-8, all flags exact.

**Perf (real FAERS, ~800k pairs/qtr):** GPU detect ~22-33s/qtr (optimized:
compile-once padding + shared EB bracket, 300->189 gammainc evals). ~12x serial /
~2x the 15-core CPU parallel at full-detect level (gammainc-bound; less than the
isolated kernel's 39x/6x). Pipeline made memory-bounded (per-qtr temp write +
incremental EWMA + streaming sink; was OOMing the 25M-row concat). Full 32-qtr
end-to-end wall-clock NOT completed in-session — long GPU background tasks kept
getting auto-killed by the dev harness (~15-30min); run in a plain shell.

Headroom: GPU the prior EM; faster quantile than bisection. Correctness is done;
remaining is perf polish. GPU-engine (item 5) COMPLETE as an MVP.

## 2026-07-12 — gpudisprop pushed (private) + GPU perf: --fp32 knob (4.3x)

- Private GitHub repo created + pushed: github.com/harlananelson/gpudisprop.
- GPU perf ("the GPU issue"): diagnosed the ~28s/qtr detect as float64 gammainc on
  the RTX 3090 (fp64 ~1/64 of fp32 throughput). Tried safeguarded-Newton quantile —
  reverted (didn't converge eb05 in the far-left tail; bottleneck is precision not
  iters). Delivered a **--fp32 knob**: EB kernel 5.8s->1.4s (4.3x) at 1M pairs;
  float32 keeps eb05 to ~1e-6 vs safetysignal with signal flags EXACTLY unchanged
  (only eb50 point-estimate drifts to ~1e-3). float64 stays the exact default.
  Committed 0f16213. Remaining lever: GPU the prior EM (cumulative grows to 23s).

## 2026-07-12 — GPU prior EM: 48x faster, machine-precision exact (gpudisprop)

Wired gpudisprop/prior_gpu.fit_prior_gpu as the pipeline default: E-step densities +
log-sum-exp + weighted sufficient stats over millions of rr on GPU, scalar 5-param
Gamma-shape Newton on host. Reduction-bound (not gammainc-bound) so fp64 is fine:
8.1s->0.2s (48x) on 3M rr, params matching safetysignal to ~1e-14. Removes the
cumulative-prior bottleneck (was ~23s/qtr). e2e parity unchanged (worst_rel 8e-8,
flags exact). Commit 807f1e9.

GPU-engine perf now: per-quarter = GPU prior ~0.2s + GPU detect ~28s float64 /
~6-10s --fp32. The gammainc-bound detect (fp64 on the 3090) is the only remaining
cost; --fp32 (eb05 ~1e-6, flags exact) is the lever there. Prior is fully solved.

## 2026-07-12 — GPU engine full-run benchmark (float64 vs fp32) — item 5 complete

Ran the full 32-quarter FAERS compute end-to-end (detached nohup, survives the
harness kill) in both precisions with the GPU prior:
- **float64: ~18 min (1076s); float32: ~6.4 min (382s) = 2.8x.**
- Both = 25,361,490 rows, 16,204,198 flagged (63.9%) — EXACTLY the deployed
  signal-compute output (signals_faers_v2026-07-08). End-to-end real-data validation.
- float32 vs float64: is_signal_any IDENTICAL (0/25.4M), 3/25.4M GPS-flag diffs; but
  eb05 drifts up to 7.5e-3 (0.75%) on extreme posteriors (worse than fixture 1e-6),
  ic huge relative only where ic~=0. Guidance: fp32 for the signal SET; float64 to
  ship eb05 VALUES. README + gpudisprop repo updated (4c951fb).

GPU engine (item 5) fully done: built, validated to machine precision, perf-tuned
(GPU prior 48x exact; fp32 detect 2.8x full-run with identical signal set). Repo:
github.com/harlananelson/gpudisprop (private). Scratch f32 output left at
~/data/signal-compute/signals_faers_gpu_f32.parquet (2.3GB, deletable).

## 2026-07-12 — Verified: FAERS/VAERS → AEMS does NOT break the pipeline

Research-routine PR #3 (Research ideas: 2026-07-10), idea #5, claimed FDA "retired
FAERS/VAERS" via AEMS — flagged as a load-bearing claim needing verification. Checked
primary/secondary sources:
- AEMS launched 2026-03-11; consolidates FAERS/VAERS/animal-AERS FRONT-ENDS into one
  real-time public dashboard. Rationale: cost ($37M/yr → $120M/5yr saved), fragmentation,
  real-time vs quarterly, AI dashboard.
- **Pipeline-critical finding: bulk quarterly data-extract files STILL published** under the
  AEMS-branded page (fis.fda.gov/extensions/FPD-QDE-FAERS/), still `faers`-named ASCII+XML,
  2004–Q1 2026, **Q1 2026 posted 2026-04-28**, free/no login. openFDA API intact. VAERS
  website + reporting infrastructure unchanged.
- Conclusion: AEMS is a rebrand/consolidation of the front-end, NOT a discontinuation of the
  bulk downloads faers-pipeline consumes. Access stays PUBLIC (arguably more so). No pipeline
  crisis. Idea #5 downgraded from "emergency" to low-urgency "state of our data source"
  explainer. Only genuine open question: real-time report credibility/verification (FDA silent).
- Reviewed ideas #1–4: rank #1 (carbidopa/levodopa B6 seizures — freshest, cleanest) > #3
  (GLP-1 alopecia — reproduce published claim, watch weight-loss telogen-effluvium + volume
  confound) > #2 (AAV liver-failure class check — original but hard, Zolgensma steroid
  confound, tiny N) > #4 (Trop-2 ADC — boxed-warning toxicities are expected, only head-to-head
  is novel; drop the tangential CD3xCD20 citation). PRs left unmerged (kept as PRs per user).

Sources: fda.gov/news-events/press-announcements/fda-launches-new-adverse-event-look-tool;
fis.fda.gov/extensions/FPD-QDE-FAERS/FPD-QDE-FAERS.html;
cidrap.umn.edu/public-health/fda-announces-aems-new-adverse-event-database-replace-vaers;
insider.thefdagroup.com/p/fda-adverse-event-monitoring-system-aems

## 2026-07-12 — Drafted carbidopa/levodopa B6-seizure article; started weekly article queue

- **Article drafted:** `articles/carbidopa-levodopa-b6-seizures.qmd`, modeled on the Cotton
  .qmd (inline R helpers so prose can't drift; EB05≥2.0 + ≥2-of-4 rule; can/cannot-show +
  limitations callouts). Real FAERS numbers (signals_faers_v2026-07-08, through 2025Q4).
- **Key finding (verified against data):** the *seizure* outcome FDA warned about is NOT
  disproportional (carbidopa levodopa 2025Q4: 23 obs vs 32.9 exp, EB05 0.5, 0/4 methods) —
  expected for a rare outcome FDA found only 14 times. But the *mechanism*, Vitamin B6
  deficiency, is a strong, stable signal (carbidopa levodopa: 11 obs vs 0.08 exp, EB05 71.3,
  IC025 6.11, all 4 methods), sustained 12+ consecutive quarters, predating the Mar-2026
  warning. Thesis: causal coherence via the upstream mechanism, not the downstream rare outcome.
- **Analytical convention (deliberate, differs from Cotton):** use LATEST-quarter snapshot +
  trajectory, NOT max-EB05-across-quarters. On the 32-quarter panel, max-across-quarters
  cherry-picks noise for rare-event drugs (e.g. B6 deficiency hit EB05 3190 on 3 reports in one
  2019 quarter). Observed counts shown beside every EB05. Drug-string fragmentation handled by
  per-formulation tables + a reference generic, not invalid EB05 pooling (a proper pooled
  recompute via gpudisprop is a noted rigor follow-up; would strengthen, not weaken, the signal).
- **Render status:** R logic verified against the parquet; NOT rendered here (quarto absent on
  this box; project renv not restored). Render/deploy via build_static_site.R = user's flow.
- **Queue started:** `articles/proposals/ARTICLE_QUEUE.md`. Order: GLP-1 alopecia → AAV liver
  class → AEMS explainer → Trop-2 ADC, plus the 2026-07-03 batch as backlog.
- **Weekly cadence:** user wants one article/week on a fixed day. Day + automate-vs-interactive
  pending user decision (asked). Publishing stays manual (PR boundary).

## 2026-07-12 — Weekly cadence: provisional default set (user stepped away)

Asked user for (a) publish day and (b) automate-vs-interactive; no response in-session.
Proceeded with best-judgment provisional default, easily changed later:
- **Mondays, drafted interactively** with Claude. No new cloud routine created — deliberately
  NOT auto-spawning one (token cost + a cloud agent can't verify numbers against the local
  FAERS parquet, which is what made the carbidopa/levodopa draft trustworthy). Interactive was
  the recommended option.
- Recorded in ARTICLE_QUEUE.md header. Open to: different day, or an auto-draft→PR / auto-reminder
  routine, once the user confirms. Publishing stays manual regardless (PR boundary).

## 2026-07-14 — Drafted GLP-1 alopecia article (week 2); base-R figures for portability

- **Article drafted:** `articles/glp1-alopecia.qmd`. Reproduces the published "only semaglutide
  & tirzepatide flag for alopecia" claim quarter-by-quarter. Real FAERS (through 2025Q4).
- **Finding (verified):** the claim is a moving target. Ozempic (semaglutide) alopecia signal
  was above threshold through 2024 (peak EB05 2.53, 2024Q3, 4 methods) then decayed sub-threshold
  by 2025 (1.18, 2 methods) — notoriety-wave fade. Zepbound (tirzepatide) quadrupled across 2025
  (1.09→4.28, 4 methods) as weight-loss use exploded; Mounjaro just crossed (2.18). Others null.
  Brand/indication split does NOT give a clean weight-loss story (Zepbound>Mounjaro fits, but
  Ozempic>Wegovy inverts — Ozempic heavily off-label for weight loss, so brand≠indication in
  FAERS). Thesis: single-snapshot disproportionality claims are non-stationary; confound
  unresolvable from spontaneous reports.
- **Portability fix:** neither gt nor ggplot2 is in the portal renv.lock; build_static_site.R does
  NOT render .qmd (expects pre-rendered app/static/<id>.html + ARTICLES tribble entry). Rendering
  is a separate manual quarto step in the user's env. Converted BOTH articles' trajectory figures
  from ggplot2 → base R graphics (zero extra deps; verified via pdf device — png segfaults on this
  headless box, an env issue not a code bug). Cotton uses gt only; base R matches that portability.
- **Registered** both articles in app/logic/articles.R as status="draft" (won't publish until
  rendered + flipped to published). ids: glp1_alopecia, carbidopa_levodopa_b6.
- Queue updated: next = AAV liver class → AEMS explainer → Trop-2 ADC.
- **Next from user:** "add an AEMS tab to my page for analysis with that data" — pending scoping.

## 2026-07-14 — Added AEMS analysis tab to the portal (static page)

User: "add an AEMS tab to my page for analysis with that data." Chose (via AskUserQuestion):
static analysis page + AEMS quarterly extract (the FAERS-continuation bulk files we already use).

- **New page:** `articles/aems-analysis.qmd` → renders to `app/static/aems.html` (id `aems`).
  Live inline R from the signals parquet. Content: what AEMS is (sourced) + live dataset snapshot
  (2025Q4: 881,751 pairs, 4.8M reports, 265,108 consensus signals) + method-agreement table +
  an annotated "why the raw top-signals leaderboard misleads" table (endari→SCD crisis =
  indication, gold bond→mesothelioma = litigation, nirsevimab→RSV = indication/route,
  heparin→HIT = definitional) + links to the two new articles as analysis-done-right + route to
  faers.mobi + caveats. Verified all computations/lookups against the parquet.
- **Deliberately NOT a raw signal leaderboard:** the top-EB05 pairs are dominated by
  confounding-by-indication, litigation clusters, route effects, and eponymous known reactions —
  showing them as "biggest signals" would imply false causation. Turned that into the page's lesson.
- **Wiring** (`scripts/build_static_site.R`): added "AEMS" to the top nav; added a generic
  STANDALONE_PAGES tribble + build_standalone_pages() (nav pages that aren't articles / not in the
  articles grid). Validated: build runs, produces index/articles with the new tab; warns aems.html
  missing until rendered (expected).
- **Render targets** for the three new pages (user renders .qmd → app/static/<id>.html):
  glp1-alopecia.qmd→glp1_alopecia.html, carbidopa-levodopa-b6-seizures.qmd→carbidopa_levodopa_b6.html,
  aems-analysis.qmd→aems.html. static_site/ is gitignored (regenerated at deploy).
- **Noted pre-existing bug:** NAV_INJECTION() sprintf passes args to a template with no %s →
  harmless "one argument not used" warning on every page. Left as-is (out of scope).

## 2026-07-21 — AAV liver article (week 4) + reMarkable Paper Pro PDF pipeline

**Article:** `articles/aav-gene-therapy-liver.qmd`. Elevidys boxed-warning (Nov 2025) read
against the whole gene-therapy class. Verified finding: the hepatic signal is a **delivery-route
class effect**, not product-specific. Every IV-infused AAV flags (Elevidys 369 hep reports/AST
EB05 46 4m; Zolgensma 4124/AST EB05 65 4m; Hemgenix 74/ALT EB05 58 4m; Roctavian 28/ALT EB05
148 4m); the two liver-sparing products show ZERO hepatic reports (Luxturna, subretinal local,
1434 total; Casgevy, ex-vivo cells, 77 total) — built-in negative controls. Like carbidopa, the
fatal endpoint (acute hepatic failure, 2 obs) is faint while the injury spectrum (transaminases)
is loud. Headline pair per product uses observed>=5 to avoid n=1 EB05 extremes. Registered
draft `aav_gene_therapy_liver`.

**reMarkable Paper Pro PDF pipeline (NEW):** rendered all 4 FAERS articles to 179.6 x 239.6 mm
PDFs (the Paper Pro 4:3 canvas; no standard paper size matches) and uploaded to a new
`/globalpatientsafety` folder on the reMarkable cloud. Pipeline = `scripts/render_remarkable.sh`
(run inside `nix develop`). Three real gotchas solved + documented in the script:
  1. Quarto defaults to SYSTEM R (/usr/lib/R, no rmarkdown) → force `QUARTO_R="$(which R)"` (nix R).
  2. Project renv `.Rprofile` hides the nix packages → render a COPY from /tmp (data paths absolute).
  3. No paper preset is 4:3 → render `--to typst -M keep-typ:true`, sed-patch the .typ page
     directive (`paper:"us-letter"` → `width/height`), recompile with `quarto typst compile`.
Also fixed **flake.nix**: added `knitr` + `rmarkdown` to rWithPkgs — the flake claimed to support
article rendering but lacked the packages Quarto's R engine needs (render failed without them).
gt tables AND base-R plots both render correctly in typst. rmapi authenticated via existing
~/.config/rmapi/rmapi.conf; run via `nix run nixpkgs#rmapi`. Folder + 4 PDFs confirmed on device.
Queue now: AEMS reproducibility explainer (next) → Trop-2 ADC.

## 2026-07-13 — Cadence locked: Monday; reMarkable PDF is the pre-publish approval gate

- **Publish day locked: MONDAY**, weekly, drafted interactively (data-verification stays in loop).
- **reMarkable send reframed as the APPROVAL GATE, not a post-publish extra:** each article is
  rendered to a Paper Pro PDF and sent to the device `/globalpatientsafety` folder *before*
  deploy, so Harlan reads + approves on the reMarkable ahead of time. Site render/deploy happens
  only after approval. Workflow steps + ARTICLE_QUEUE.md + memory updated accordingly.
- The 4 PDFs already on the device (carbidopa, GLP-1, AAV, AEMS) are the current approval copies
  awaiting Harlan's read. No auto cloud routine created (interactive by design).

## 2026-07-13 — Hold today; first publish Monday 2026-07-20 (~1 week review/article)

Harlan confirmed all 4 PDFs are on the reMarkable (incl. "Inside the AEMS Data"). He wants ~one
week to review each, so we do NOT publish today. First publish = Monday 2026-07-20, then ~one
approved article per Monday. The 4 delivered drafts are the review backlog; **no new drafting
until it clears.** Publishing gated on his per-article approval (read on device first).

## 2026-07-13 — Sharyl Attkisson health-topic monitor (new cloud routine)

User wants to monitor when Attkisson covers health issues this site can reanalyze.
- **Source found:** her site + /feed/ are Cloudflare-blocked (403), but the podcast RSS
  `https://anchor.fm/s/dab6618/podcast/rss` (The Sharyl Attkisson Podcast, 327 eps) is open and
  fetchable. Feed carries titles+descriptions only — NO transcripts (full transcripts would need
  Whisper on the audio; not set up). Second show: Full Measure After Hours (not yet wired).
- **Reality check:** most of her health content is health *politics* (CDC schedule, AAP lawsuit,
  Morens indictment, monkeypox, EMF) — not analyzable. Analyzable = names a specific drug/vaccine
  + adverse event present in FAERS/VAERS. First-pass scan: ivermectin is the strongest live match
  (12,466 FAERS reports; neurotoxicity EB05 20/4m; a "product use in unapproved indication"
  cluster capturing the off-label COVID era — a genuine candidate article). COVID-vax/myocarditis
  = done (Cotton), extendable. MMR/autism = weak/heavily-caveated only.
- **Built:** `articles/proposals/attkisson-monitor.md` (source, filter, first-pass scan, dedupe
  log) + cloud routine `gps-attkisson-monitor` (trig_01ByknQFAxBMkAxMy63dPw7U, Sat 14:00 UTC,
  sonnet-5). Weekly: reads the feed, flags analyzable NEW episodes, opens PR "Attkisson monitor:
  YYYY-MM-DD" with candidate analyses; dedupes via last-scanned episode #. Propose-only (PR
  boundary). Chose recommended defaults (feed-based topic detection + article-queue PR); user was
  away for the depth/output question, easily changed.

## 2026-07-13 — Attkisson monitor upgraded to Substack full-text feed (primary)

Her Substack `sharylattkisson.substack.com` exposes an open **full-text RSS** (`/feed`,
content:encoded = whole article body, all posts free) + an undocumented JSON API
(`/api/v1/archive`, `/api/v1/posts/<slug>`). Neither is Cloudflare-blocked. This SOLVES the
"no transcripts" gap — full article text means the monitor scans the whole body for a
drug/vaccine+event, not just titles. Confirmed richer signal: "Follow the Money" names statins,
hydroxychloroquine, remdesivir (FAERS); the CDC-schedule post names DTaP/MMR/HPV/RSV/COVID + febrile
seizures/pertussis/encephalopathy (VAERS). Switched routine `gps-attkisson-monitor` to Substack
RSS primary + podcast RSS secondary (dedupe same story across both), scanning full body. Updated
attkisson-monitor.md (source + dedupe watermarks: Substack slug + podcast ep #).

## 2026-07-13 — Cross-GLP-1 NAION survivability; methodology-first editorial direction

- **Analysis run + verified:** NAION (optic ischaemic neuropathy) across the GLP-1 class, FAERS
  2025Q4. Cross-section: signal "survives" (semaglutide EB05 39/289 reports; liraglutide 20,
  tirzepatide 8, dulaglutide 5 — all 4/4; exenatide none). BUT emergence timing refutes a class
  effect: every non-semaglutide agent ignites only AFTER the July-2024 JAMA Ophth semaglutide-NAION
  study (all ~zero pre-2024Q3), on tiny N — a notoriety-bias signature. Verdict: real
  semaglutide-anchored signal; class "survival" is largely reporting-attention contamination.
- **Saved** as `articles/proposals/naion-glp1-survivability.md`; **queued at #2** (absorbs the
  earlier single-drug Ozempic-NAION idea).
- **Editorial direction locked (user's framing):** he is a statistician, NOT an MD, so the site's
  distinctive lane is **pharmacovigilance METHODOLOGY / how-to-use-FDA-data gotchas**, anchored by a
  drug example but not clinical causation claims. Added an "Editorial direction" section to
  ARTICLE_QUEUE.md with a running gotcha catalogue (candidate "Reading FDA Adverse-Event Data"
  series) + memory `methodology-first-editorial`. NAION/GLP-1 is the flagship methodology piece.

## 2026-07-13 — Signal & Noise: named series + /methods page + UI-triage design

- **Series named "Signal & Noise"** (Reading FDA Adverse-Event Data). Built `/methods` static
  landing page (`articles/methods.qmd` → `app/static/methods.html`), wired into top nav +
  STANDALONE_PAGES. Also rendered the AEMS page to `app/static/aems.html` (user asked to ensure it
  exists) — both build into static_site. Deploy still gated on user.
- **UI-triage design proposal** (`articles/proposals/signal-triage-ui.md`): precompute the Signal &
  Noise gotcha-checks for every flagged pair and surface as faers.mobi badges/filters/report-card.
  Indicators: sudden-onset/notoriety, class survivability+synchrony, non-clinical-PT (SOC), on-label
  vs novel (fda_labels.parquet), small-N/unstable, protopathic risk → per-pair triage score + badges
  + a filter panel ("hide non-clinical / novel only / exclude sudden-onset / class-consistent / min
  N"). GPU justification (user's point): the trajectory + class-survivability passes over ~265k pairs
  are the heavy part gpudisprop makes a batch precompute (new signals.parquet columns). Spans
  gpudisprop (kernels) + signal-compute (orchestrate/join labels+class+SOC) + faers-mobi (render).
  Caveats: MedDRA-licensed PT→SOC map stays internal (ship derived flag only); notoriety detection is
  a "check timing" heuristic not a verdict; multi-repo feature — first slice = onset + non-clinical
  badges + min-N/novel filters.

## 2026-07-13 — Triage prototype validated; MedDRA letter located (gates the non-clinical badge)

- **Prototype built + run:** `signal-compute/proto_signal_noise_triage.R` (committed a031d20).
  Computes onset_q / step_score / onset_recent / nonclinical / small_n → triage badge per pair.
  On Ozempic it AUTO-REPRODUCES the manual clustering: cyclic vomiting → SUDDEN-STEP (coding
  artifact), NAION → RECENT-ONSET (notoriety ramp), product/device terms → NON-CLINICAL, real GI/
  metabolic → solid. Fixes learned: require obs>=10 & eb05>=3 for meaningful onset (naive first-flag
  mis-dated NAION to 2020); notoriety is both STEPS and RAMPS (need step_score AND onset_recent).
- **MedDRA letter:** `articles/reviews/meddra-email-2026-07-05-draft.txt` (to mssohelp@meddra.org,
  2026-07-05) + earlier `meddra-subscription-email.txt`. Its feature #3 (SOC-based "low-information-
  term filter") IS the non-clinical badge — so publishing that badge is gated on the MedDRA
  subscription. Proto uses VAERS `in_noise` + keyword fallback as interim internal approximation.
  Recorded the dependency in signal-triage-ui.md.

## 2026-07-13 — Triage run across all pairs: quantified leaderboard cleanup

Ran the triage prototype over ALL 265,108 flagged pairs (FAERS 2025Q4). Badge distribution:
small-N 87.8% (232,752), non-clinical 8.2% (21,761), recent-onset 4.5% (11,974), sudden-step 1.3%
(3,421), SOLID only 3.9% (10,461); any-caution 90.3%. Headline: of the top-200 by EB05 (naive
leaderboard) only 3 (2%) are SOLID — 170 small-N, 35 recent-onset, 10 non-clinical, 7 sudden → the
default "sort by strongest" is ~98% noise. Triage turns 265k pairs into a ~10k high-value shortlist
and MEASURES the AEMS "raw leaderboard lies" lesson. Recorded in signal-triage-ui.md. Small-N badge
= "interpret with trajectory," not "wrong" (rare pairs dominate, as expected).

## 2026-07-13 — Class-survivability column built + validated

`signal-compute/proto_class_survivability.R` (committed 112ae66). Per (drug,event): class_n_flag +
class_verdict (ISOLATED / WEAK / INDEPENDENT / SYNCHRONOUS). Agent-level, curated class map (ATC =
production). Validation bug caught + fixed: discriminator is EARLIEST-ONSET RECENCY, not onset
spread (NAION onsets 2024Q3–2025Q4 all recent → SYNCHRONOUS; pancreatitis from 2018 → INDEPENDENT).
GLP-1 result: ISOLATED 828 / WEAK 235 / INDEPENDENT 101 / SYNCHRONOUS 12 — NAION in the 12
(earliest 2024Q3) with skin laxity, GI hypomotility, malnutrition. Automates the manual NAION
verdict; reduces 1,176 flagged events to 12 needing a timing check. Badge = "check timing" (not a
verdict). Perf fix: distinct-drug regex join, not per-agent 25M-row scans (first version timed out
at 2min with statin/DOAC classes added). Recorded in signal-triage-ui.md.

## 2026-07-14 — On-label vs novel column built; all 3 triage columns done

`signal-compute/proto_onlabel_novel.R` (committed 7910fee). Matches flagged (drug,event) against
FDA label safety text (fda_labels.parquet, 2000 drugs). Agent-level join; NA when no label (no
false-novel from missing labels). Wording gotcha caught: full-PT substring under-matched
(gastroparesis, medullary thyroid CANCER, gallbladder injury read novel) → fixed with head-noun +
cancer<->carcinoma + synonym normalization; NAION stays NOVEL. Residual lab-term false-novels
(HbA1c vs "hypoglycemia") = the documented "string is first pass, concept matching is production"
caveat. Semaglutide: 46 on-label / 121 novel; NAION=novel. ALL THREE triage columns now prototyped
+ validated (non-clinical/onset, class-survivability, on-label/novel) — they compose: highest-value
= novel ∧ ¬non-clinical ∧ recent-onset ∧ ¬small-N (NAION clears every gate). Remaining: ATC map +
GPU batch scale-out, then faers.mobi render. Non-clinical public badge still gated on MSSO reply.

## 2026-07-16 — Triage scale-out specced as tickets

Wrote `articles/proposals/triage-scaleout-tickets.md`: the production scale-out of the 3 validated
triage prototypes, as concrete tickets across signal-compute (hub: cheap columns + joins + parquet
write), gpudisprop (GPU class-survivability kernel — the one expensive pass), faers-mobi (badges/
filters/report-card), + an ATC drug→class map (breadth) and the column contract (interface). Phased:
Phase 1 (T1–T6+T12: trajectory/nonclinical/on-label columns + badges + filters + validation harness)
delivers ~90% of value with NO ATC/GPU dependency — turns the 98%-noise leaderboard into a
filterable ~10k-solid-pair view. Phase 2 (T7 ATC map → T8 GPU class-survivability → T9/T10) is the
notoriety chip. Phase 3: report-card + concept-level on-label. Cross-cutting: MedDRA gates the public
non-clinical badge (ship derived boolean only); badges advisory ("check", not "artifact"). Recommend
Phase 1 first, then let real usage decide if the ATC+GPU lift is worth it.

## 2026-07-30 — PR backlog evaluation: 8 open, 1 merged; #9 subsumes #2–#8

Reviewed all nine PRs on `harlananelson/globalpatientsafety`.

**State.** Only PR #1 (research ideas, 2026-07-03) was ever merged. PRs #2–#8 are the
weekly autonomous routines' report-only output (4 agent reviews, 3 research-idea sets),
each adding exactly one markdown file. PR #9 (2026-07-30) is the only PR that touches
production code: it archives #2–#8's seven files **byte-identically** (verified by diffing
each PR head against `pr/9`) and implements the fixes the reviews repeatedly flagged.
All PRs are mergeable and green except #2, whose FAILURE is the stale renv/rhino CI
problem already fixed on `main` (CI green since 2026-07-13).

**The loop is not closing.** The same three findings — `christine_cotton` featured but
unreachable, "Signal methods" card stuck on `coming_soon` while `/methods` ships, CLAUDE.md
documenting the retired Rhino app as production — recur across all four agent reviews
(#2, #4, #6, #8) because nothing was merged between them. `main` itself has been idle
since 2026-07-16 while eight PRs accumulated.

**Findings verified against the repo, not just the PR text.** `app/logic/articles.R` has
three `draft` articles (`aav_gene_therapy_liver`, `glp1_alopecia`, `carbidopa_levodopa_b6`)
with no HTML in `app/static/`, and `app/static/aems.html:3578-3579` linked two of them —
real 404s on a live page. `christine_cotton` is `published, featured=TRUE` with
`app/static/christine_cotton.html` present but no `app/view/article_christine_cotton.R`.
`app/static/methods.html` exists while `tools.R` called it `coming_soon`. All confirmed.

**Reservation on PR #9.** Roughly half its code changes (`article_christine_cotton.R`,
`main.R`, `articles.R`, `portal.R`) repair the Shiny app that the same PR's CLAUDE.md
rewrite declares retired and non-production — fixing dead code rather than archiving it.
Also `scripts/check_site_consistency.R` hardcodes `standalone <- c("aems.html",
"methods.html")` and the literal tool name `"Signal methods"`, duplicating the
`STANDALONE_PAGES` tribble the same PR adds to `build_static_site.R` — a second source of
truth that will drift. The de-linking of the two draft articles in `articles/aems-analysis.qmd`
is hand-mirrored into the generated `app/static/aems.html`; correct now, but the fix lives
in a build artifact.

**Open question.** Is the Rhino `app/` retired for good? If yes, the durable fix is to
archive `app/view/`, `app/main.R`, and the `rhino-test.yml` `main` job rather than keep
repairing them — which would also stop the agent reviews from re-reporting dead-app bugs
every fortnight.

**Recommended action.** Merge #9, then close #2–#8 as superseded (their content is already
in #9; leaving them open re-conflicts and keeps re-seeding the same findings).

## 2026-07-30 — Resolved: #9 merged, #2–#8 closed as superseded

PR #9 merged as `4df81d13` (merge commit, matching the #1 precedent). PRs #2–#8 closed
with a superseded comment pointing at #9. No open PRs remain. The `fix/claude-pr-implementations`
branch was **not** deleted — a Grok worktree at `/home/harlan/projects/grok/projects/globalpatientsafety`
still has it checked out.

**Provenance (user).** PR #9 was authored by Grok; #2–#8 were the Claude weekly routines.
So the working division was Claude routines finding the drift and Grok closing it. Worth
noting because #9's title says "Claude weekly PR findings" — the findings are Claude's,
the implementation is Grok's.

Reservations from the evaluation entry above stand as follow-up work: the retired Rhino
`app/` is now repaired rather than archived, and `scripts/check_site_consistency.R`
hardcodes `standalone`/`"Signal methods"` in duplicate of `STANDALONE_PAGES`.

## 2026-07-30 — Retired Rhino app archived to `archive/rhino-app/`

Acting on the open question in the evaluation entry above: the Shiny portal is retired
for good, so it is archived rather than repaired. Four consecutive agent reviews
(#2, #4, #6, #8) spent their findings on a surface that serves no traffic; PR #9 fixed
those symptoms in place, which left the cause — a dead app that still looked live.

**Moved to `archive/rhino-app/`:** `app/main.R`, `app/view/*`, `app/js/`, `app/styles/`,
`app.R`, `rhino.yml`, `config.yml`, `dependencies.R`, `tests/` (testthat + Cypress).
A README there records why, what stayed behind, and how to restore it.

**Deliberately left in the live tree:** `app/logic/{articles,tools}.R` and
`app/static/*.html`. These live under `app/` but are static-site *input* —
`build_static_site.R` reads them by path and stubs `box::use()`, so they were never
Shiny-dependent. Moving them would break the production build.

**Other changes.** `.github/workflows/rhino-test.yml` → `site-checks.yml` with the
`main` (rhino lint/test/Cypress) job dropped; only the base-R consistency check remains.
`.renvignore` now infers dependencies from `scripts/build_static_site.R` +
`check_site_consistency.R` instead of the archived `dependencies.R` shim — judgment call,
flagged here because it changes what a future `renv::snapshot()` would capture.
CLAUDE.md and the `articles.R` header comment no longer point contributors at view modules.

**Verified.** `check_site_consistency.R` passes (12 OK, exit 0). The static builder could
**not** be run end-to-end here: this checkout has no renv library installed
(`there is no package called 'tibble'`). Confirmed pre-existing by reproducing the identical
failure at `4b51991`, the pre-archive commit — not caused by the archive. Run
`renv::restore()` before the next deploy to exercise the builder for real.

**Not done (open).** `scripts/check_site_consistency.R` still hardcodes
`standalone <- c("aems.html", "methods.html")` and the literal `"Signal methods"` tool
name, duplicating `STANDALONE_PAGES` in the builder. `.lintr` and `.rscignore` still carry
rhino/rsconnect settings; harmless, left alone. The seven closed-PR branches
(`agent-review-*`, `research-ideas-*`) still exist on the remote.

## 2026-07-30 — renv restored, builder verified; production is ~2 months stale

**Restore.** Targeted rather than full: `renv::restore(packages = c("tibble","dplyr","stringr"))`
then `"box"` — 18 packages, dominated by a 7.9-minute `stringi` source build (no binaries for
this box's R 4.6.1 under nix). Deliberately did NOT restore the whole 83-package lock, since
most of it (rhino, treesitter, treesitter.r and their trees) exists only for the now-archived
Shiny app. Consequence: every renv-aware command prints "One or more packages recorded in the
lockfile are not installed." That message is expected, not a fault.

`renv/activate.R` self-updated 1.2.2 → 1.2.3 during bootstrap, which brings it into agreement
with the `renv` version already pinned in `renv.lock`. Committed as a fix, not drift.

**Builder verified.** `Rscript scripts/build_static_site.R` exits 0, writes all 8 outputs, and
its own `internal-link check: OK` passes. `check_site_consistency.R` also passes. The build is
confirmed working post-archive.

**Defect found — the `box` stub in `load_tribble()` does not work.** `build_static_site.R:47`
sets `e$box <- list(use = function(...) invisible(NULL))` intending to neutralize the registries'
`box::use()` call, but `::` resolves the real namespace regardless of what is bound in the eval
env, so the builder hard-requires the `box` package. It only ever worked because restoring the
full lock installed `box` transitively via rhino. `check_site_consistency.R` does this correctly —
it strips `box::use(...)` textually and needs base R only.

**Trap this creates.** `.renvignore` now infers dependencies from `build_static_site.R` +
`check_site_consistency.R`. `box` appears in neither as a parseable call (only in a comment and
that env assignment), so a future `renv::snapshot()` would **drop `box` from the lock and break
the next restore**. Two ways out, needs a decision: (a) keep `box` in the lock explicitly, or
(b) make the builder box-free by stripping `box::use` the way the consistency script already does.
Option (b) is the coherent end-state — it removes the builder's last tie to the archived stack.

**Cosmetic bug.** `NAV_INJECTION()` (`build_static_site.R:348-362`) passes `esc(article_id)` to a
`sprintf` format string containing no placeholders, and ignores its `title` argument entirely →
5 "one argument not used by format" warnings per build. Output is correct. Not fixed.

**The real finding — the deployed site is far behind the repo.** Audited live over HTTPS:

| Route | Live | Fresh build |
|-------|------|-------------|
| `/methods` | **404** | built |
| `/aems` | **404** | built |
| `/christine_cotton` | **404** | built |
| `/`, `/articles`, `/shingles`, `/covid_vaccine` | 200 | built |

The live articles index lists only `covid_vaccine` and `shingles`; `christine_cotton` — published
and `featured = TRUE` since 2026-06-13 — appears nowhere on the live site, and the live homepage's
featured card points at `/shingles`. The live homepage shows 3 Live / 2 Coming soon badges; the
fresh build shows 4 Live / 1. So production predates PR #9 *and* predates the christine_cotton
publication.

This reframes the four agent reviews. Their findings were real, but the user-visible impact was
not what they described: the dead `/carbidopa_levodopa_b6` and `/glp1_alopecia` links they flagged
on "the live AEMS page" cannot 404 for any visitor, because `/aems` itself was never deployed.
The actual live defect is a **missing featured article**, which no review caught — every review
read the repo and inferred the deployed state instead of checking it.

**Not done.** No deploy. `rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/`
is outward-facing and publishes three pages that have never been public; it needs explicit approval.

## 2026-07-30 — Deployed: production caught up after ~2.5 months

`rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/`, run with
explicit user approval. Checked the webroot first: it held exactly five builder-produced files
last modified **2026-05-14**, nothing hand-placed, so `--delete` had nothing foreign to remove
(dry run confirmed: 8 writes, 0 deletions). Re-`chown`ed to `www-data:www-data` afterwards to
match the prior convention, since rsync-as-root would otherwise have left root-owned files.

Verified live over HTTPS:

| Route | Before | After |
|-------|--------|-------|
| `/methods` | 404 | **200** |
| `/aems` | 404 | **200** |
| `/christine_cotton` | 404 | **200** |
| `/`, `/articles`, `/shingles`, `/covid_vaccine`, `/favicon.ico` | 200 | 200 |
| `/carbidopa_levodopa_b6`, `/glp1_alopecia` | 404 | 404 (correct — still drafts, and now unlinked) |

The homepage featured card now resolves to `/christine_cotton` instead of `/shingles`; tool badges
went 3 Live / 2 Coming soon → 4 Live / 1. Live `index.html` and `aems.html` are md5-identical to
the local build, and no live page links a draft article.

So PR #9's fixes and the christine_cotton publication are finally public. Note the ordering this
exposed: the fixes were merged 2026-07-30 but only became real on deploy — the repo was never the
thing users saw. **Whoever writes the next agent review should check the deployed site, not just
the source**, or it will keep describing bugs no visitor can hit while missing ones they can.

## 2026-07-31 — Fixed: builder no longer depends on `box`

`load_tribble()` in `scripts/build_static_site.R` now strips the registries'
`box::use(tibble[tribble])` header textually before eval, matching what
`check_site_consistency.R` already did, instead of binding a fake `box` in the eval
environment. The old stub could never work: `::` resolves the real namespace regardless
of local bindings, so the production builder silently depended on the `box` package,
which was only present because the archived rhino tree pulled it in.

Added a guard: if any `box::` call survives stripping (a form the regex can't handle,
e.g. one containing nested parens), the loader now **fails loudly** naming the file,
rather than falling back to loading the archived stack. Verified it fires by
temporarily injecting `box::name(f(1))` into `tools.R`.

**Verification.** Renamed `box` out of the renv library and rebuilt: exit 0, all 8 pages
written, `internal-link check: OK`. Then confirmed `"box" %in% loadedNamespaces()` is
**FALSE** after a full build — necessary because `box` also exists in the nix store, so
hiding the renv copy alone would not have proved anything. Output is md5-identical to
what is currently live for `index.html`, `aems.html` and `articles.html`, so this is a
pure dependency fix with zero content change; no redeploy needed.

This closes the `renv::snapshot()` trap logged 2026-07-30: `box` is no longer needed, so
a snapshot dropping it from the lock is now harmless rather than build-breaking.

**Still open.** `NAV_INJECTION()` (`build_static_site.R:363`) passes an argument to a
`sprintf` format string with no placeholders and ignores its `title` parameter → 5
warnings per build. `check_site_consistency.R` still hardcodes `standalone` and
`"Signal methods"` in duplicate of `STANDALONE_PAGES`.

## 2026-07-31 — Fixed: NAV_INJECTION sprintf warnings

`NAV_INJECTION` was a function of `(article_id, title)` whose entire body was a `sprintf()`
over a format string containing **no placeholders**: `title` was ignored outright, and
`esc(article_id)` was handed to a format with nowhere to put it, so every article page
emitted "one argument not used by format" — 5 warnings per build.

The bar is identical on every page (back link, "All articles", copy-link button); it carries
no per-article content. So it is now a plain character constant rather than a function, and
both call sites (`build_article_pages`, `build_standalone_pages`) use it directly. Neither
argument was ever reachable in the output, so nothing was lost.

**Verified.** Build exits 0 with **zero** warnings of any kind (was 5). All 8 output files are
**byte-identical** to the pre-fix build, and the sticky bar still appears exactly once per
article page (checked on the distinctive `position:sticky; z-index:1000` style — a naive grep
for the link text shows 2 hits on `covid_vaccine.html`, but the second is a citation inside the
article body, not a double injection). `check_site_consistency.R` passes. No redeploy needed:
live content is unchanged.

**Still open.** `check_site_consistency.R` hardcodes `standalone <- c("aems.html","methods.html")`
and the literal `"Signal methods"` tool name, duplicating `STANDALONE_PAGES` in the builder.
