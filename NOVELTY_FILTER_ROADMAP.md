# Novelty filter roadmap — aers.mobi / faers.mobi

**Context:** Grok reviewed the "Top 20 novel signals" table on aers.mobi (2026-04-20,
`/home/harlan/projects/AI/reviews/groc-aers.md`) and pointed out that a naive
substring match of the MedDRA PT against the drug's FDA label was calling many
well-known pairs "novel." This document tracks the plan to fix it.

---

## Round 1 — shipped 2026-04-21

Commits: `aers-mobi@e5b241c`, `faers-mobi@6422f7b`. Live on Hetzner.

**Round 2 #5 — shipped (in progress) 2026-04-21:**
- App code: `aers-mobi@1b2f1e6`, `faers-mobi@5a8478a`. Live. Reads
  `indications_and_usage` column from `fda_labels.parquet` when
  present; otherwise behaves identically to round 1.
- Augmenter: `faers-pipeline@1a87c52` adds
  `scripts/augment_fda_labels_indications.R`. Running locally to
  fetch indication text for all 2000 cached drugs; ETA ~30-40 min.
  A background waiter (not yet committed) will scp the augmented
  parquet to `/srv/shiny-server/{aers,faers}-mobi/data/fda_labels.parquet`
  on Hetzner and touch `restart.txt` when the fetch completes, so
  #5 activates without further human action.

1. **Medication-error / admin PT blacklist.** Hardcoded list of exact PT
   names plus regex patterns (`dispensing error`, `product.*error`, etc.).
2. **Fuzzy label match.** `.event_in_label()` helper: exact substring OR
   ≥70% of the PT's non-trivial words (stop-words stripped) appearing
   anywhere in the label.
3. **Honest UI copy.** Table renamed to "Top 20 pairs not in cached FDA
   label"; caption states what is and isn't filtered.
4. **Badge consistency.** The per-pair KNOWN/NOVEL badge now uses the same
   matcher as the table (was diverging).

What this fixes: the Keratopathy / Spinal-cord-infarction class of misses
where the label uses related but not-identical wording. What it doesn't
fix: Round 2 below.

---

## Round 2 — deferred, needs offline data prep in signal-compute

All three filters below require data that isn't currently bundled with the
apps. Doing them live at session start would either break the data
governance model (app makes outbound API calls) or be too slow (~15k drug
lookups). The right home is `signal-compute` (the offline pipeline that
builds `signals.parquet`), which bundles extra parquets alongside.

### 3. MedDRA hierarchy match

**Goal:** a PT is "known" if the drug's label mentions any term in the PT's
hierarchy path (PT → HLT → HLGT → SOC), not just the PT itself. Fixes cases
like "Spinal cord infarction" vs "serious neurologic events".

**Data needed:** a lookup from PT → {HLT, HLGT, SOC} for every outcome_name
in `signals.parquet`. Covers ~20k PTs.

**Source:**
- UMLS REST API (user has `UMLS_API_KEY`). The `MDR` vocabulary exposes
  MedDRA. Hierarchy via `/content/{vocab}/{version}/CUI/{cui}/relations`.
- Alternative: licensed MedDRA download. User would need to supply.

**Deliverable:** `data/meddra_hierarchy.parquet` in each app, with columns:
`outcome_name, hlt, hlgt, soc`. Built once per MedDRA release.

**Code change in signal_timeline.R:** `.event_in_label()` adds a second
pass: for an event, also check each level of its hierarchy against the
label text with the same fuzzy rule. A match at ANY level → "known".

### 4. Class-effect filter (ATC)

**Goal:** drop pairs where many drugs in the same class flag the same
event — indicates a class effect that's likely already on-label for the
class description even if not on this specific drug. Fixes corticosteroid
/ local-anesthetic / anticoagulant class noise.

**Data needed:** for each `rxnorm_name` in signals, its ATC class(es) at
levels 3 and 4.

**Source:** RxNav (NLM, free). Endpoint
`/rxclass/class/byRxcui.json?rxcui={cui}&relaSource=ATC`. Batch fetch
~15k drugs. Use the RxCui already implied by the rxnorm_name (may need a
name → RxCui resolution step via `/rxcui.json?name=...`).

**Deliverable:** `data/drug_classes.parquet` with columns:
`rxnorm_name, rxcui, atc3, atc4`. Refresh quarterly.

**Code change in signal_timeline.R / logic/:** a new reactive computes,
per event, the fraction of drugs in the same ATC3 class that also flag
this event at the same criteria (≥3 methods, is_signal_any). If fraction
≥ 0.3 (configurable), mark as class effect and drop from novel table.

### 5. Indication confounder exclusion

**Goal:** drop pairs where the event IS the drug's indication (or the
condition the drug is used to treat). Fixes Leuprolide → Prostate cancer
stage IV, Clopidogrel → In-stent restenosis, Sirolimus → Heart transplant
rejection.

**Data needed:** the `indications_and_usage` label section for every drug.
Not currently in `fda_labels.parquet` — the schema has boxed_warning,
contraindications, warnings_and_cautions, warnings, adverse_reactions,
drug_interactions but not indications.

**Source:** openFDA label API — same endpoint already used to build the
current cache, just include `indications_and_usage` in the returned
fields.

**Deliverable:** augment `fda_labels.parquet` with an
`indications_and_usage` column. Requires re-running the label fetch in
signal-compute.

**Code change in signal_timeline.R:** extend the sections concatenated
in `top_novel`'s novel check to include `indications_and_usage` in
addition to the warning/adverse-reaction sections. The same
`.event_in_label()` fuzzy matcher will catch the indication.

---

## Execution order when picked up

1. **Start with #5** — it's the smallest delta (add one field to the
   existing label fetch; one line in the timeline's novel check). Will
   kill the biggest chunk of obvious false-novelty (indication confounding).
2. **Then #3** — MedDRA hierarchy. Needs a bit more plumbing but once the
   parquet is built, the filter is a one-pass change.
3. **Finally #4** — class-effect filter. Most complex, most domain-judgy
   (threshold of 30% of class members is a design choice that needs review
   by a pharmacovigilance expert).

For each: update this doc's Round 1 section when shipped, and update the
UI caption on both apps to remove the relevant caveat.

---

## Verification approach

After each round ships, re-run Grok (or a pharmacovigilance expert) against
the new top-20 table output and compare against their previous review. The
goal is for a senior pharmacovigilance reviewer to say "these are
plausible-but-uncertain hypotheses worth chart review" rather than "every
one of these is already on label."
