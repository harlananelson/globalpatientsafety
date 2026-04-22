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

**Also pending (from AI/plans/drug-name-matching.md, new-drug-bias thread):**

### New-drug / Weber-effect correction

Observation: faers.mobi shows inflated EB05 on drugs less than ~2 years
on market. Small background (E) + modest N blows up the raw N/E ratio,
and the current fixed gamma prior isn't tight enough to shrink it.

Two implementation paths:

1. **Adaptive gamma prior** (proper). Drug-age-dependent (α, β):
   ```
   years  | alpha | beta | effect
    <= 1  |  0.10 | 0.10 | strongly shrinks EB05
    <= 2  |  0.20 | 0.50 | moderately shrinks
    <= 3  |  0.50 | 1.00 | mild shrinkage
     > 3  |  1.00 | 2.00 | baseline (current)
   ```
   Where applied: **signal-compute**. Per-quarter EB05 is recomputed
   with the drug-age-specific prior, then EWMA-smoothed as today.
   `years_on_market` = (quarter_end_date - first_approval_date) / 365.25.
   first_approval_date already available via data/first_approval.parquet.

2. **Multiplicative post-hoc shrinkage** (quick approximation). Applied
   in the app's pair_stats reactive or in a lightweight post-process of
   signals.parquet:
   ```
   adjusted_eb05 <- eb05 * (1 - 0.6 * exp(-years_on_market))
   ```
   Less principled but a few minutes of work. Useful as a stopgap.

Decision needed with user. Adaptive prior is the right answer but
belongs in signal-compute.

### Canonical signal math (per user specification, 2026-04-22)

Replace the current safetysignal MGPS (2-component Gamma mixture) with
the operational FDA approach:

- **Likelihood:** N | E, λ ~ Poisson(λE) per (drug, event, stratum)
- **Prior:** λ ~ Gamma(a, b) with BOTH hyperparameters learned from data
  — not fixed, not simple, not single. Empirical Bayes.
- **Fit:** marginal likelihood of N given E integrates out λ to a
  Negative Binomial; MLE of (a, b) per stratum via numerical
  optimization (BFGS / Newton-Raphson). No EM, no mixture.
- **Per-pair posterior:** Gamma(â + N, b̂ + E)
- **Point estimate:** posterior mean (â + N) / (b̂ + E), on the raw
  rate-ratio scale — no log transform, no EBGM.
- **CI:** percentiles of the posterior Gamma directly (e.g. `qgamma(0.05, ...)`
  for 5th percentile), also raw-scale.

**Stratification** (per user clarification 2026-04-22):

Two natural stratum dimensions:

1. **Drug age — new vs established.** Fit separate (â, b̂) per tier.
   The EB prior learned on new drugs is naturally wider (reflecting
   sparse-background reality) without any post-hoc multiplier: the
   Weber correction falls out of the data. Starting tiers: 0–2 years,
   2–5 years, >5 years (subject to refinement).
2. **Drug category — e.g. oncology / antibiotics / small molecules
   vs biologics.** The expected-AE distribution is categorically
   different across therapeutic areas (oncology drugs expect severe
   AEs; chronic-care drugs less so). Fitting a single prior across
   all categories over-shrinks the signal-rich categories and
   under-shrinks the benign ones.

Both dimensions are valid. User-directed choice which to implement
first, or whether to combine. Not every split is a stratum — SOC,
time window, indication, etc. are NOT currently part of the design.

**Compute:** EB fit per stratum is embarrassingly parallel across
strata; at FAERS scale (millions of pairs × several strata) a GPU
implementation is appropriate. User has GPU hardware available.

Source of truth: user's 2006 simulation work at Lilly compared this
approach to the MGPS mixture and showed it performed better. The
literature papers I (Claude) initially referenced describe academic
MGPS, not the operational FDA method.

This replaces the current Weber-effect post-hoc shrinkage once built
(the adj_eb05 column becomes redundant).

---

## Top-20 Novel Signal Audit (2026-04-21)

Manually verified the top-20 novel pairs sorted by most-recent latest
quarter (all 2024Q4). **0 / 20 were truly novel.** Full audit at
`/home/harlan/projects/AI/reviews/top20-novel-verification.md`.

False-positive breakdown:

| Category | # of 20 | Driver |
|---|---|---|
| Product quality / medication error | 7 | Blacklist misses |
| Known / labeled | 5 | Label cache stale OR MedDRA-synonym walk misses |
| Confounding by indication | 4 | `indications_and_usage` exists but fuzzy matcher misses synonyms |
| Expected mechanism / formulation | 3 | No filter for on-label titration endpoints |
| Published case reports only | 1 | Dabigatran + cardiac tamponade (closest to "novel") |
| Duplicate PT at same HLT | 1 | `Product contamination` vs `Product contamination physical` |

### Filter improvements — ranked by fixability × impact

**Step 1. Expand product-quality / med-error PT blacklist** (removes 7/20).
Add to `EVENT_BLACKLIST_EXACT` and expand `EVENT_BLACKLIST_PATTERNS` to
cover the full MedDRA SOC **Product issues** and the **Medication
errors** SMQ. Specific PTs: `Product contamination*`, `Product cleaning
inadequate`, `Product residue present`, `Product deposit`, `Labelled
drug-disease interaction medication error`, `Injection site
extravasation`. Regex patterns: `^product `, `medication error$`,
`drug-disease interaction`.
**STATUS: shipped 2026-04-21**, aers@<pending>, faers@<pending>.

**Step 2. Make indication confounder matching work on synonyms**
(removes 4/20). The `indications_and_usage` text is already being
folded into the label match, but the fuzzy matcher misses PT↔label
synonyms like "Nephrogenic anaemia" ↔ "anemia of chronic kidney
disease" or "Acute lymphocytic leukaemia recurrent" ↔ "relapsed or
refractory B-ALL". Extend the `.event_in_label_expanded` synonym walk
so it applies to the indications section, not just the warnings/AE
sections. ~30 min.

**Step 3. MedDRA HLT-level deduplication** (removes 1+/20).
When the DT has two rows that share the same `(drug, HLT)` — e.g.
`chloraprep + Product contamination` and `chloraprep + Product
contamination physical` — collapse to one row with the best stats
across both. Needs the HLT column from UMLS (we already cache the
CUI; HLT lookup requires a separate UMLS call per PT). Or: simple
heuristic that collapses PTs sharing >=80% of tokens. Medium effort.

**Step 4. Mechanism / formulation ignore-list** (removes 3/20).
Per-drug "expected on-label effects" allowlist-to-ignore, e.g.
flecainide → QRS prolongation (titration endpoint), Urocit-K → ghost
tablet, Depo-T → crystalline deposit. Hard to automate cleanly;
probably manual curation per drug or SMQ-based. Lower priority.

**Step 5. Refresh label cache with MedDRA synonyms baked in**
(further reduces 5/20 known-but-mismatched). Re-fetch openFDA labels
and preprocess each section so that "keratopathy" + "keratitis" +
"corneal injury" all register as the same concept via CUI. The MedDRA
hierarchy cache we already have is the right basis for this. ~hours.

**Step 6. FDA recall feed integration** (removes recent spurious
signals like levothyroxine `Product substitution issue`). Subscribe to
the FDA Enforcement Report CDER feed and auto-suppress PTs in active
recall windows for affected NDC. Feature work.

### Recommended execution order

After #1 ships and we rebuild the top-20 list, expect the new top to
still contain indication confounders (#2) and some labeled-but-missed
(#5) pairs — #2 is next most valuable. #3 is a nice-to-have. #4 and
#6 are longer-term.

---

## 2026-04-21 progress snapshot

**Shipped tonight:**
- Step 1: blacklist expansion — commits `aers-mobi@87592cb`,
  `faers-mobi@2f7c0ca`. 7 of the original top-20 false positives
  dropped (all `Product *` and `Medication error` PTs).
- Step 2: spelling normalization + looser synonym threshold —
  `aers-mobi@00aa141`, `faers-mobi@be46156`. British↔American
  medical spellings (anaemia, leukaemia, oedema, etc.) plus
  curated clinical synonyms (adrenocortical↔adrenal,
  lymphoblastic↔lymphocytic, relapsed/refractory↔recurrent,
  staining↔discoloration, colour↔color). Synonym match threshold
  dropped from 0.7 to 0.6 (direct-event match stays at 0.7).
- Step 5 ROOT CAUSE: the `indications_and_usage` column was NEVER
  deployed to Hetzner — an earlier background waiter had a
  self-matching pgrep bug and never fired. Manually scp'd the
  augmented parquet tonight. Label cache now has indication text
  for 658 of 2000 drugs (remaining 1342 have no retrievable
  openFDA label record — all that would return the same result).
- Step 2's clinical-synonym path caught blinatumomab (ALL recurrent
  now matches indication "relapsed/refractory b-cell precursor ALL")
  and daprodustat (nephrogenic anaemia → anemia of renal disease
  via UMLS synonym, matching "anemia of chronic kidney disease").
  Neither appears in top 20 after deploy.

**Still false positive in top 20:**
- `alkindi sprinkle` + adrenocortical insufficiency — LABEL CACHE
  MISS: cache has topical anti-itch hydrocortisone, not oral Alkindi.
- `chlorhexidine gluconate` + tooth discolouration — same: cache has
  antiseptic skin solution, not Peridex dental rinse.
- `tioconazole`, `miconazole` + vulvovaginal — UMLS synonyms are
  narrow; label wording doesn't match.
- Procedural pairs (bss plus + endophthalmitis, ranibizumab +
  conjunctival, lidocaine + foreign body, etelcalcetide + shunt) —
  need step 4.
- `flecainide` + QRS prolongation — mechanism/titration endpoint;
  needs step 4.

### New bottleneck: label cache product-variant selection

The label fetch (`scripts/fetch_fda_labels.R`) queries openFDA by
`openfda.generic_name` with `limit=1`. For a generic ingredient with
multiple marketed products, the API returns the first hit — often the
wrong formulation for the signal we're checking. Examples:
- hydrocortisone → anti-itch topical (not Alkindi oral tabs)
- chlorhexidine gluconate → antiseptic skin solution (not Peridex rinse)

**Fix direction (signal-compute side, not app):** fetch multiple
labels per ingredient and concatenate the warning/AE/indication
sections across all marketed products. That way any labeled effect
across any formulation will be matched. Doubles label fetch cost
(~2000 → ~6000 calls) but makes the novel flag correct.

### When the full roadmap is done (post step 1-6 + label fetch fix)

Expected effective novel rate on top-N: should approach what a
pharmacovigilance reviewer would flag for deeper investigation.
Sevoflurane + nephrogenic DI (subtle but documented), glimepiride
+ cholangiocarcinoma (potentially novel), ondansetron + G6PD
(interaction not causation), and dabigatran + cardiac tamponade
(case reports exist) are the kinds of pairs that would survive
even a rigorous filter pass — and those are what's surfacing
tonight, albeit mixed with the product-variant-label-cache noise.

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
