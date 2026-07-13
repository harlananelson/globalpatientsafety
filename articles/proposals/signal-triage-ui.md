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

## Relation to the rest of the work

This is the productized form of the `cluster.md` "GPU pharmacovigilance lab" idea and the Signal &
Noise series: every gotcha the series names becomes a computed guardrail in the tool. It also gives
the series articles a natural call-to-action ("see this check live in faers.mobi").
