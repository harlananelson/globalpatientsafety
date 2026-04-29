# Agent Handoff Snapshot — 2026-04-28

This document is a state snapshot written by the **SCDCernerProject-side Claude agent** before handing all globalpatientsafety work back to the **globalpatientsafety-side Claude agent**. It exists so the user can diff this agent's understanding of the work-state against what the other agent has actually done while running code.

**Scope of authority:** This snapshot is read-only. The SCD-side agent has not executed code, edited files, or pushed changes for this work in the conversation that produced this document. State below is reconstructed from `DECISION_LOG.md`, the cross-conversation memory store, and `CLAUDE.md`.

**After comparison:** SCD-side agent returns to `/projects/SCDCernerProject/`. All ongoing globalpatientsafety work belongs to the gps-side agent.

---

## Canonical sources of truth (read these first)

1. `DECISION_LOG.md` — running log; latest entries `2026-04-28 — Step 3: substance contingency built; signal-compute launched`.
2. `SEARCH_REDESIGN.md` — Phase 1–8 spec for search/splash redesign.
3. `NOVELTY_FILTER_ROADMAP.md` — Rounds 1–6 for the rule-based novelty filter.
4. `/projects/AI/plans/PLAN-llm-triage.md` — Track B (local-LLM triage) plan.
5. `/projects/AI/plans/DECISIONS.md` — D-001 (apps presentation-only), D-004/D-011 (per-quarter EBGM + EWMA), D-018 (FDA-direct pivot).

If anything below contradicts those files, **the files win**. This snapshot may be stale by the time it is read.

---

## In-flight at handoff time

### Step 3: substance signal-compute running
- **Started:** 2026-04-28 08:05:50.
- **Command:**
  ```
  nix develop --command bash -c '
    Rscript R/compute_quarterly.R \
      --source faers \
      --contingency-root /home/harlan/data/faers-pipeline/contingency-substance \
      --output-root /home/harlan/data/signal-compute/substance
  '
  ```
- **Expected output:** `~/data/signal-compute/substance/signals_faers_v2026-04-28.parquet`.
- **Expected wallclock:** ~5h (regular run was 5h19m). Should land around 13:05 local.
- **Input was already built:** `~/data/faers-pipeline/contingency-substance/source=faers/` — 7,313,182 rows, 95.3% substance-resolution by report volume, 12.8% row compression vs raw contingency.

**Risk:** if the rerun crashes the same way E1 did (`cli_inform("...{:,}")` glue format), the fix at `signal-compute/R/compute_quarterly.R:145,165` is already in place from E1. Should be safe.

### Pending immediately after that compute lands
1. **UI toggle: drug-level vs substance-level** in both `faers-mobi/app/view/signal_timeline.R` and `aers-mobi/app/view/signal_timeline.R`.
   - Add a `radioButtons` (or top-of-page selector): "Drug-level | Substance-level".
   - `signals()` / parquet-path reactive switches based on selector.
   - Track A search, Track D3 class filter, etc. carry over because schemas match (`drug`, `event`, …).
   - **Re-tune `CLASS_EFFECT_THRESHOLD`** for the substance view — substance rollup concentrates class co-flags differently. May want a per-view constant (`CLASS_EFFECT_THRESHOLD_SUB`).
   - Estimated effort: ~30 LOC per app + parse + boot-test.
2. **Local symlink:** point `faers-mobi/data/signals_substance.parquet` at the new substance output once compute finishes.
3. **Deploy:** extend `signal-compute/scripts/deploy_to_vps.sh` again to push the substance parquet alongside the drug-level one (currently only ships the drug-level signals + 5 enrichment files). Or decide: do we ship both, or replace?

---

## Track-by-track status

### Track A — Search redesign (faers-mobi + aers-mobi)
**Status: feature-complete in both apps as of 2026-04-27.**

| ID | Task | Status |
|---|---|---|
| A3 | Replace `head(2000)` cap with full Arrow aggregation | done |
| A3.5 | Defer expensive enrichment to displayed rows | done |
| A4 | Server-side fuzzy search (`agrep` + spelling normalizer) | done |
| A5 | Cache distinct names per session | done |
| A6 | Port to aers-mobi | done |
| A7 | Correct CLAUDE.md "top 2000 shipped" claim | done |

Step 1 (schema migration `rxnorm_name`/`outcome_name` → `drug`/`event`) and Step 2 (multi-vocab search + brand-substance crosswalk) shipped on top, both apps.

### Track B — Local-LLM triage (Ollama)
**Status: schema + plumbing sound; production held for 3090.**

- B1 (label schema, 6 mutually exclusive labels) — done, see `PLAN-llm-triage.md`.
- B2 (Ollama prompt, JSON schema) — drafted; smoke-tested on `mistral:latest` (7B). Two known issues: (1) format compliance ("1." prefix, fixable in prompt + post-strip); (2) priority-rule reasoning fails for indication-confound cases on 7B class.
- B3 (validate against top-20 ground truth) — fixture defined; full run held for 3090 + 32B model (~2026-05-04).
- B4 (production batch in signal-compute) — outlined, not built.

**Hardware milestone:** RTX 3090 arriving ~2026-05-04. Until then, Track B work that requires the 32B model is blocked.

**Optional fallback:** Claude/AskSage API for low-confidence rows only (~5% of pairs). Not built.

### Track C — Priority-tier splash
**Status: pending — depends on Track B for `triage_class` column.**

| ID | Task | Status |
|---|---|---|
| C1 | 4-tier priority sort using triage class | pending |
| C2 | Replace `.default_row` hardcode | pending |
| C3 | Tier badges + colors in DT | pending |
| C4 | "Just-detected, unverified" side panel | pending |
| C5 | Anchor 12-month window to `max(first_signal in dataset) − 4 quarters`, not `Sys.Date() − 12 months` | pending — open question; recommendation already in DECISION_LOG |

C5 is the only Track C item that can ship without Track B. Recommend doing it now while context is fresh.

### Track D — Rule-based novelty filters
**Status: D3, D4, D5 shipped 2026-04-28. D2 remains.**

| ID | Round | Task | Status |
|---|---|---|---|
| D2 | 3 | MedDRA hierarchy walk PT → HLT/HLGT/SOC | pending — needs offline UMLS data prep |
| D3 | 4 | Class-effect filter (`CLASS_EFFECT_THRESHOLD = 3`) | done in both apps |
| D4 | 5 | Indication confounder exclusion | effective via deploy script + multiproduct cache (no app code change needed) |
| D5 | 6 | Label cache product-variant selection (`fda_labels_multiproduct.parquet`) | done at data layer |

**D2 is the largest remaining filter task.** Requires extending `meddra_hierarchy.parquet` builder (currently 4 cols: pt, cui, synonyms, definition; **no hlt/hlgt/soc columns**) via UMLS API. Defer until after substance work + Track B settle.

### Track E — Pipeline / data refresh
**Status: E1 done. E2, E3 pending.**

- E1 (signal-compute rerun) — completed 2026-04-28 07:02:54. Output `signals_faers_v2026-04-28.parquet` (1.79 GB, 19.46M rows, 117/143 quarters with content, 1990Q1..2025Q4, 2,267,851 unique pairs). Schema is now `drug`/`event` (not `rxnorm_name`/`outcome_name`).
- E2 (investigate 2023Q1–2024Q3 gap) — pending. **May be moot** now that E1 produced full 1990Q1–2025Q4 coverage; verify against new parquet before spending time on it.
- E3 (re-download FAERS 2025Q2 in faers-pipeline) — pending.

### Tracks F/G/H — Open scoping (no code, need user input)

- **F1:** which 4–6 audiences/canned queries to seed first? (clinicians, regulatory, researchers, patients, media)
- **G1:** which per-drug data layers ship first? (label, DDI, demographics, class effects, alternatives)
- **H1:** auth stack (hosted vs custom; SQLite vs Postgres; what triggers a notification)

These should not be started without explicit user direction. If the gps-side agent has begun any of them autonomously, that is a deviation worth flagging.

---

## Operational items

### Deploy script
`signal-compute/scripts/deploy_to_vps.sh` was extended on 2026-04-28 to ship 8 files (was 3): signals + drug_dictionary + event_dictionary + `fda_labels_multiproduct.parquet` (mounted as `fda_labels.parquet`) + `meddra_hierarchy.parquet` + `atc_classes.parquet` + `diana_dictionary.parquet` + `first_approval.parquet`.

**Has this been run?** Per DECISION_LOG, **no — requires user execution.** Auth via existing `root@5.78.69.136` ssh key.

If the gps-side agent ran it, the VPS now has the multiproduct label cache + enrichment files — meaning the deployed novel/treats classification matches local results.

### Local symlinks (dev box)
- `faers-mobi/data/fda_labels.parquet` → `~/data/faers-pipeline/output/fda_labels_multiproduct.parquet`
- `faers-mobi/data/meddra_hierarchy.parquet` → `~/data/diana/meddra_hierarchy.parquet`
- `faers-mobi/data/atc_classes.parquet` → `~/data/diana/atc_classes.parquet`
- `faers-mobi/data/diana_dictionary.parquet` → `~/data/diana/diana_dictionary.parquet`
- `faers-mobi/data/first_approval.parquet` → `~/data/diana/first_approval.parquet`
- `faers-mobi/data/signals.parquet` → `~/data/signal-compute/signals_faers_v2026-04-28.parquet` (drug-level)
- aers-mobi has the same enrichment symlinks; signals are an in-place renamed parquet (`rxnorm_name`/`outcome_name` → `drug`/`event`), original backed up to `signals_aers_v2026-04-20.original-schema.parquet`.

### Schema regression that surfaced 2026-04-28
The new compute output's columns are `drug`/`event`, not `rxnorm_name`/`outcome_name`. Both apps were migrated in-place (faers-mobi via 27-ref bulk replace; aers-mobi via 14 targeted edits). Earlier assumption that `safetysignal::detect_all_methods` would echo `rxnorm_name`/`outcome_name` was wrong — it preserves whatever input names `compute_quarterly.R` passes (which are already renamed at lines 86–87).

Related discovery: the column called `rxnorm_name` was **never RxNorm-normalized**. Only 34.5% of distinct drug names resolve to a DiAna substance; 5.1× compression possible at substance level. This is what motivated Step 3 (substance contingency rebuild).

### Files modified during 2026-04-27/28 work
Approximate scope, for diff-checking:
- `faers-mobi/app/view/signal_timeline.R` — Track A refactor + Step 1 schema migration + Step 2 multi-vocab search + D3 class-effect filter constant + UI copy.
- `aers-mobi/app/view/signal_timeline.R` — same as above, ported.
- `globalpatientsafety/CLAUDE.md` — A7 correction ("Splash Cap (in-app), not a deploy filter").
- `globalpatientsafety/flake.nix` — added `arrow` and `DT` so faers-mobi runs from gps's nix shell.
- `signal-compute/R/compute_quarterly.R` — cli format fix at lines 145, 165.
- `signal-compute/scripts/deploy_to_vps.sh` — added 5 enrichment-file copies.
- `signal-compute/scripts/build_substance_contingency.R` — new file.
- AERS parquet (`signals_aers_v2026-04-20.parquet`) — in-place column rename.

---

## Recommended ordering for the gps-side agent

If the substance compute lands successfully and there are no surprises:

1. **Verify substance compute output** (row count, quarter range, drug fan-out collapsed as expected).
2. **Build UI toggle** drug-level vs substance-level in both apps. Re-tune `CLASS_EFFECT_THRESHOLD` for substance view.
3. **C5** anchor the 12-month emerging window to dataset max quarter (cheap, ready, doesn't depend on Track B).
4. **Run deploy script** if not already run, so VPS matches local enrichment + apps.
5. **E2 verification** — confirm whether 2023Q1–2024Q3 gap is now resolved by the new parquet (may close as moot).
6. **Hold for 3090 (~2026-05-04)** before resuming Track B (B3 → B4) and then Track C (C1–C4).
7. **D2** later — needs offline UMLS data prep, not blocking.
8. **F/G/H scoping** — only if user explicitly directs.

---

## Open questions worth flagging

- **C5 default:** confirm anchoring strategy (`max(first_signal) − 4 quarters` recommended).
- **Substance vs drug deploy:** ship both parquets, or substance-only after toggle lands?
- **`CLASS_EFFECT_THRESHOLD_SUB`:** should the substance view get its own threshold, or is one constant fine?
- **Step 2 agrep noise on short queries:** `ozempic → clorazepic` etc. Acceptable as-is, or worth a min-query-length guard before agrep fires?
- **F/G/H scoping:** awaiting user input — no code work yet.

---

*End of snapshot. Authored by the SCD-side agent at user request. After this point, all globalpatientsafety work belongs to the gps-side agent.*
