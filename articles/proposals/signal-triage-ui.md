# Design proposal: Signal & Noise triage in the UI

**Idea:** the Signal & Noise methodology (the gotcha checks I ran by hand for NAION/Ozempic) is
mechanical enough to **precompute for every flagged drug–event pair** and surface in faers.mobi as
per-pair badges, filters, and a trajectory "report card." The articles teach the traps; the UI
enforces them, so a user searching a signal is *steered away from the naive read automatically*.

**Why now:** disproportionality itself is cheap, but the triage layer (per-pair trajectories,
change-point detection, class-survivability across every co-drug, on-label cross-reference) is
O(pairs × quarters × class-size) — heavy on CPU. With the GPU engine (`gpudisprop`) the whole
triage becomes a batch precompute over all ~265k flagged pairs in the `signal-compute` step, stored
as extra columns in `signals.parquet`. The UI then just renders precomputed flags — no live compute.
This is the "GPU-accelerated pharmacovigilance lab" made user-facing.

## The triage indicators (each = one Signal & Noise gotcha, made computable)

| Indicator | Gotcha it operationalizes | How to compute (per pair) | UI badge |
|---|---|---|---|
| **Onset / sudden-emergence** | non-stationary; overnight epidemic; notoriety | First quarter the pair crossed threshold; step-change score = max quarter-over-quarter jump in observed / EB05. Big single-quarter jump → suspect. | 🕐 *sudden onset* |
| **Class survivability + synchrony** | survivability ≠ causation | For the drug's class, count co-members that also flag E, AND whether their onsets cluster after one date (synchronous = notoriety) vs independent histories. | 🔁 *class-consistent* / ⚠️ *class-synchronous (notoriety?)* |
| **Non-clinical PT** | the leaderboard lies | Tag event by MedDRA SOC: Product issues, Injury/procedural, Investigations, Social circumstances, General disorders → not a biological ADR. | ⚙️ *device/error/procedural* |
| **On-label vs novel** | novelty | Cross-reference (drug, event) against FDA label text (`fda_labels.parquet`). On-label = known; off-label + recent onset = genuinely novel. | 🏷️ *on-label* / ✨ *novel* |
| **Small-N / unstable** | small-N needs the trajectory | Observed count; EB05 volatility (SD across recent quarters); expected≈0 inflation. | 📉 *small N / unstable* |
| **Reverse-causation risk** | protopathic bias | Heuristic: malignancy/mortality PT on a metabolic/weight-loss drug, or event that can be a *reason* for the prescription. Flag for manual review (not auto-reject). | ↩️ *protopathic risk* |

Composite: a per-pair **"read-with-care" score** = weighted roll-up, plus the individual badges (badges beat a single opaque score — they tell the user *which* trap applies).

## UI treatment (faers.mobi)

1. **Badges on every signal row** — the icons above, so the trap is visible at a glance in the table.
2. **A triage filter panel** — checkboxes: *hide non-clinical PTs* · *novel only* · *exclude
   sudden-onset* · *class-consistent only* · *min observed N*. Lets a user reshape 265k pairs into
   the ones worth their attention in one click. (This is the "help users get better results" ask.)
3. **Per-pair "Signal & Noise report card"** — click a pair → the EB05/observed trajectory
   (small-multiples vs class co-members), the automated verdicts, and a one-line link to the Signal &
   Noise article explaining whichever trap fired. Closes the loop: tool → teaching → tool.
4. **Default view** de-emphasizes (doesn't hide) the ⚙️ non-clinical and ⚠️ notoriety pairs, so the
   naive "sort by EB05" no longer surfaces garbage at the top.

## Data / columns to add to signals.parquet

`onset_quarter`, `step_change_score`, `class_id`, `class_n_flagged`, `class_onset_synchrony`,
`pt_soc`, `is_nonclinical_pt`, `on_label` (bool), `novelty_flag`, `obs_stability`,
`protopathic_risk`, `triage_score`. All precomputed in `signal-compute` (GPU-assisted for the
trajectory/class passes).

## Implementation map (spans three repos)

- **`gpudisprop`** — batch kernels: per-pair trajectory stats + change-point score; class-survivability
  join (for each pair, gather co-class drugs' signals). This is the heavy part the GPU justifies.
- **`signal-compute`** — orchestrate the triage pass, join FDA labels + a drug→class map + PT→SOC map,
  write the new columns.
- **`faers-mobi`** — render badges, the filter panel, and the report card.

## Open questions / caveats

- **Drug→class map:** need ATC or a curated grouping (GLP-1, statin, ADC…). ATC is the scalable
  answer; curate the high-traffic classes first.
- **MedDRA licensing (important):** the PT→SOC map and any MedDRA hierarchy are licensed — they can
  drive the *internal* `is_nonclinical_pt` computation but **must not be published** to the public
  repo/site (see the MedDRA/UMLS licensing note). Ship the derived boolean flag, not the map.
- **Notoriety detection is a heuristic, not truth** — a synchronous class onset *suggests* notoriety
  but can co-occur with a real class effect newly recognized. Badge should say "check timing," not
  "artifact." Keep the human in the loop; the UI flags, it doesn't rule.
- **On-label matching** is fuzzy (label text ≠ MedDRA PT); start with high-precision string/concept
  matches and accept misses.
- Scope: this is a multi-repo feature, not a one-afternoon build. Suggested first slice: onset +
  non-clinical-PT badges + the min-N/novel filters (highest value, lowest dependency), then class
  survivability, then the report card.

## Prototype (validated 2026-07-13)

First slice built and run on real FAERS: `signal-compute/proto_signal_noise_triage.R`. Computes
`onset_q`, `step_score`, `onset_recent`, `nonclinical`, `small_n` → a triage badge per pair. On
Ozempic it **reproduces the manual clustering** automatically:
- **Cyclic vomiting syndrome** (1→175 in one quarter) → `SUDDEN-STEP` ✓ (the coding artifact)
- **Optic ischaemic neuropathy / NAION** (onset 2024Q3) → `RECENT-ONSET` ✓ (the notoriety timing —
  a *ramp*, caught by onset-recency after `step_score` alone missed it)
- Product/device/dose confusion, titration, label, cataract operation, colonoscopy, corrective
  lens → `NON-CLINICAL` ✓
- Gastroparesis, ileus, appetite terms, pancreatitis → `solid` ✓

Two lessons from the proto: (1) naive "first flag" mis-dates onset (NAION → 2020 on a tiny-N
flicker); require obs≥10 & eb05≥3 for a *meaningful* onset. (2) notoriety comes as both STEPS
(cyclic vomiting) and RAMPS (NAION) — need both `step_score` and `onset_recent`.

**Cleanup impact — run across ALL 265,108 flagged pairs (2025Q4):** small-N 87.8%, non-clinical
8.2%, recent-onset 4.5%, sudden-step 1.3%; **any caution flag 90.3%**; **SOLID only 3.9% (10,461
pairs).** The triage turns a 265k-row firehose into a ~10k high-value shortlist. Starkest on the
naive leaderboard: of the **top 200 by EB05, only 3 (2%) are SOLID** — 170 are small-N (rare-event
inflation), 35 recent-onset (notoriety), 10 non-clinical, 7 sudden. The default "sort by strongest
signal" is ~98% noise; the badges are what surface the 2% worth reading. This *measures* the
AEMS-page "the raw leaderboard lies" lesson.

**MedDRA-licensing dependency (live blocker for the public non-clinical badge):** the proto tags
non-clinical PTs via the VAERS-derived `in_noise` flag + a keyword fallback, because the VAERS map
misses FAERS product/device PTs and the proper SOC-based classification needs the MedDRA hierarchy.
That classification is **feature #3 in the pending MSSO subscription letter**
(`articles/reviews/meddra-email-2026-07-05-draft.txt`, the "low-information-term filter"). Publishing
the SOC-derived non-clinical badge is gated on that subscription; the keyword fallback is an interim
internal approximation.

## Class-survivability column (built + validated 2026-07-13)

`signal-compute/proto_class_survivability.R`. Per (drug, event): do other agents in the drug's
class flag the event (`class_n_flag`), and did the class ignite together *recently* vs have a deep
independent history (`class_verdict`)? Agent-level (semaglutide, not ozempic+wegovy separately);
curated class map (ATC is the production path). **The discriminator the validation forced:** NOT
onset spread — NAION's onsets span 2024Q3–2025Q4 (staggered but all recent) while pancreatitis
starts 2018. Use **earliest-onset recency**: whole class's earliest meaningful onset within ~6
quarters → SYNCHRONOUS.

Validated on GLP-1 (1,176 flagged events): **ISOLATED 828** (drug-specific) · **WEAK 235**
(small-N) · **INDEPENDENT 101** (real class effects, histories from 2018) · **SYNCHRONOUS 12**
(notoriety-suspect). NAION lands in the 12 (earliest 2024Q3) alongside skin laxity, GI hypomotility,
malnutrition (the weight-loss-boom emergents). The column reduces "which of 1,176 need a timing
check" to 12. Badge says **"check the timing"** (could be notoriety OR a genuinely new class
effect), it does not rule. Perf: match class regexes against distinct drug strings once, then join
(not per-agent full-table scans). Production scale-out (all classes × all pairs) is the gpudisprop
batch.

## On-label vs novel column (built + validated 2026-07-14)

`signal-compute/proto_onlabel_novel.R`. Cross-references each flagged (drug, event) against the
FDA label safety sections (`fda_labels.parquet`: boxed_warning + warnings_and_cautions +
adverse_reactions + warnings). Agent-level join (Wegovy/Rybelsus inherit the OZEMPIC/semaglutide
label); **NA when no label exists** — never call a pair novel merely for a missing label.

The wording gotcha (documented in code): raw full-PT substring under-matches — it read gastroparesis,
"medullary thyroid CANCER", and "gallbladder injury" as novel because the label says gastroparesis's
synonym, "carcinoma", and "gallbladder" (bare). Fixed with general normalizations (head-noun drop,
cancer↔carcinoma, a small synonym map) → those flip to on-label; NAION stays NOVEL. Residual
false-novels remain (lab terms like "blood glucose decreased" vs label "hypoglycemia") — the design's
"string is a first pass; production = UMLS/MedDRA concept matching" caveat, now demonstrated.
Semaglutide result: 46 on-label / 121 novel / 0 unknown (of 167 flagged, obs≥15); **NAION = novel**.

**All three triage columns now prototyped and validated** (non-clinical + onset/notoriety;
class-survivability; on-label/novel). They **compose**: the highest-value set is
`novel ∧ ¬non-clinical ∧ recent-onset ∧ ¬small-N` — genuinely new clinical signals, not the tool
re-reading the label or resurfacing device/error terms. NAION is the exemplar that clears every gate.
Remaining: ATC class map + the GPU batch scale-out (all classes × all pairs), then the faers.mobi
render (badges/filters/report-card). Public non-clinical badge still gated on the MSSO reply.

## Relation to the rest of the work

This is the productized form of the `cluster.md` "GPU pharmacovigilance lab" idea and the Signal &
Noise series: every gotcha the series names becomes a computed guardrail in the tool. It also gives
the series articles a natural call-to-action ("see this check live in faers.mobi").
