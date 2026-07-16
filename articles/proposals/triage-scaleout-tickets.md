# Signal & Noise triage — scale-out tickets

Turns the three validated prototypes (`signal-compute/proto_signal_noise_triage.R`,
`proto_class_survivability.R`, `proto_onlabel_novel.R`) into a production batch that computes the
triage columns for **every pair, every quarter, GPU-accelerated, written into `signals.parquet`**,
then renders them in faers.mobi. Concept is proven (see `signal-triage-ui.md`); this is engineering.

Spans three repos + two data assets:
- **signal-compute** — orchestration + the cheap columns + joins + parquet write (the hub).
- **gpudisprop** — GPU kernel for the one expensive pass (class-survivability).
- **faers-mobi** — render badges / filters / report-card.
- data: an **ATC drug→class map** (new) and the **PT→SOC / fda_labels** maps (exist).

## The column contract (interface between repos)

New columns added to each (drug, event, quarter) row of `signals.parquet`:

| column | type | meaning |
|---|---|---|
| `onset_q` | str | first quarter obs≥10 & eb05≥3 (meaningful onset) |
| `step_score` | int | max single-quarter observed jump (to level ≥20) — coding/step artifact |
| `onset_recent` | bool | onset within last 6 quarters |
| `nonclinical` | bool | device/error/procedure/administrative PT (SOC-derived; interim keyword) |
| `small_n` | bool | latest observed < 15 |
| `atc_class` | str | drug's therapeutic class (ATC level 3/4) |
| `class_n_flag` | int | # agents in the class flagging this event (latest quarter) |
| `class_verdict` | enum | ISOLATED / WEAK / INDEPENDENT / SYNCHRONOUS |
| `on_label` | bool/NA | event named in the drug's FDA label safety text (NA = no label) |
| `novel_flag` | bool | flagged ∧ on_label==FALSE |
| `triage_badge` | str | composite roll-up for the UI |

faers.mobi depends only on this contract; everything upstream can change freely.

---

## Phase 1 — first slice (highest value, no ATC/GPU dependency)

**T1 · signal-compute · Trajectory columns** — port `proto_signal_noise_triage.R` to a pipeline
function computing `onset_q`, `step_score`, `onset_recent`, `small_n` for ALL pairs (the CPU run
already handled 265k pairs — cheap). *Accept:* columns present for every pair; NAION `onset_recent=TRUE`,
cyclic-vomiting `step_score≥5`. *Effort: S.*

**T2 · signal-compute · Non-clinical column (interim)** — `nonclinical` from the VAERS `in_noise`
map ∪ the keyword list. *Accept:* product/device/procedure PTs flagged; gastroparesis/pancreatitis
not. **Blocked (public):** the SOC-based version + shipping the badge publicly is gated on the MSSO
subscription (letter: `articles/reviews/meddra-email-2026-07-05-draft.txt`). Internal compute OK now.
*Effort: S.*

**T3 · signal-compute · On-label/novel column** — port `proto_onlabel_novel.R`; agent-level label
join; `on_label` NA when no label. *Accept:* NAION novel; gastroparesis/gallbladder/medullary-thyroid
on-label. *Effort: S–M.* Follow-up T3b (concept matching, below).

**T4 · signal-compute · Composite `triage_badge` + parquet write** — roll the booleans into one
badge string; extend the signals.parquet schema; keep `deploy_to_vps.sh` shipping the new columns.
*Accept:* schema documented; faers.mobi can read columns; existing app unaffected if it ignores them.
*Effort: S.*

**T5 · faers-mobi · Render badges** — show the triage badge per signal row (icons/chips). *Accept:*
badges visible; no live compute (reads precomputed columns). *Effort: S–M.* Dep: T4.

**T6 · faers-mobi · Triage filter panel** — checkboxes: hide non-clinical · novel only · exclude
sudden-onset · min observed N. *Accept:* filters reshape the table; "sort by EB05" no longer floats
garbage to the top. *Effort: M.* Dep: T4.

Phase-1 outcome: the 98%-noise leaderboard becomes filterable to the ~10k solid pairs — the core
"help users get better results" win — without ATC or GPU.

---

## Phase 2 — class-survivability (needs ATC + GPU)

**T7 · data · FAERS drug-string → ATC map** — the breadth enabler. Normalize dirty FAERS drug
strings → RxNorm/ATC → class (ATC level 4). Curate high-traffic classes first (the prototype's
curated map is the seed); measure coverage (% of flagged-pair volume mapped). *Accept:* ≥80% of
flagged-pair *report volume* mapped to a class; unmapped → `atc_class=NA` (class columns NA, not
wrong). *Effort: L.* This is the fiddly one.

**T8 · gpudisprop · GPU class-survivability kernel** — the O(pairs × class-size × quarters) gather
the CPU prototype dodged by doing one class at a time. For every pair: collect co-class agents'
per-quarter signals, compute `class_n_flag` + earliest-onset recency → `class_verdict`. *Accept:*
matches the CPU prototype on GLP-1 (NAION SYNCHRONOUS, pancreatitis INDEPENDENT); runs full DB in
minutes. *Effort: L.* Dep: T7.

**T9 · signal-compute · Join class columns + recompute `triage_badge`** — wire T8 output into the
parquet; add `class_verdict` to the badge (SYNCHRONOUS → the notoriety chip). *Effort: S.* Dep: T8.

**T10 · faers-mobi · Class-consistent / notoriety filter + chip** — surface `class_verdict`; add
"class-consistent only" / "hide notoriety-suspect" filters. *Effort: S.* Dep: T9.

---

## Phase 3 — depth & polish

**T11 · faers-mobi · Per-pair "Signal & Noise report card"** — click a pair → EB05/observed
trajectory (vs class co-members), the automated verdicts, and a link to the matching Signal & Noise
`/methods` article. Closes the tool→teaching→tool loop. *Effort: M–L.* Dep: T4, T9.

**T3b · signal-compute · Concept-level on-label matching** — replace string matching with UMLS/MedDRA
concept mapping to kill lab-term false-novels (PT "blood glucose decreased" vs label "hypoglycemia").
*Effort: M.* MedDRA-gated for anything published.

**T12 · signal-compute · Validation harness** — lock the known-truth cases as regression tests:
NAION → novel ∧ recent-onset ∧ SYNCHRONOUS ∧ clinical; pancreatitis → on-label ∧ INDEPENDENT;
cyclic-vomiting → sudden-step; product-dose-confusion → non-clinical. *Accept:* CI fails if a column
regresses. *Effort: S.* Do alongside Phase 1.

---

## Cross-cutting

- **MedDRA licensing:** the SOC-based non-clinical classification and any published PT→SOC/hierarchy
  are gated on the MSSO subscription. Ship only the derived boolean `nonclinical`, never the map.
  Phase-1 interim keyword flag is an internal approximation.
- **"Flags, doesn't rule":** every badge is advisory (esp. SYNCHRONOUS = "check timing", could be a
  real new class effect). UI copy must say check, not artifact.
- **Recompute cadence:** the whole triage precompute reruns per quarter with the signals refresh
  (that's why T8 is GPU'd — so it's cheap to redo).
- **Dependency spine:** T7 → T8 → T9 → T10 (the class chain); T1–T6 independent (ship first);
  T12 continuous.

## Recommended order

Phase 1 (T1–T6 + T12) delivers ~90% of the user value with none of the hard dependencies. Do it,
ship it in faers.mobi, then decide whether class-survivability (Phase 2, the ATC+GPU lift) is worth
it — by then real usage will say whether the notoriety chip matters enough to justify T7/T8.
