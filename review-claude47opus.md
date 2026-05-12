

# Code Review: Pharmacovigilance Signal Detection Platform

## 1. Code Replication / DRY Violations

**Severity: High.** The three signal-explorer apps share massive amounts of near-identical code.

### Duplicated blocks identified

| Block | Files | Lines (approx) |
|-------|-------|----------------|
| `signal_engine.R` (entire file) | `faers-mobi`, `aers-mobi`, `globalpatientsafety` | 100% identical |
| `signal_table.R` (entire module) | `faers-mobi`, `aers-mobi`, `vaers-mobi`, `globalpatientsafety` | 100% identical |
| `.normalize_spelling()` | `faers-mobi/signal_timeline.R`, `aers-mobi/signal_timeline.R` | ~20 lines, identical |
| `.event_in_label()` / `.event_in_label_expanded()` | faers-mobi, aers-mobi | ~30 lines |
| `.FALLBACK_BLACKLIST_EXACT/PATTERNS` | faers-mobi, aers-mobi | ~80 lines, identical |
| `.fuzzy_match_pairs()` | faers-mobi, aers-mobi | ~70 lines, near-identical |
| `.enrich_label_match()`, `.find_label_row()`, `.diana_substance()` | faers-mobi, aers-mobi | ~50 lines |
| `pair_stats_full()` reactive logic | faers-mobi, aers-mobi | ~80 lines |
| The whole `renderPlot(timeline)` block | faers-mobi, aers-mobi, vaers-mobi | ~50 lines, identical |

### Refactoring recommendation

Create a new package, `signalviz` (sibling to `safetysignal`), exporting:

```r
# signalviz/R/normalize.R
#' @export
normalize_spelling <- function(x) { ... }

# signalviz/R/blacklist.R
#' @export
load_event_blacklist <- function(exact_path = NULL, pattern_path = NULL) { ... }
#' @export
event_is_blacklisted <- function(event, blacklist) { ... }

# signalviz/R/label_match.R
#' @export
event_in_label <- function(event, label_text, threshold = 0.7) { ... }
#' @export
enrich_label_match <- function(ps_subset, lbl, mh, diana) { ... }

# signalviz/R/fuzzy.R
#' @export
fuzzy_match_pairs <- function(query, events, drugs, ...) { ... }

# signalviz/R/timeline_plot.R
#' @export
plot_signal_timeline <- function(ts, drug, event) { ... }

# signalviz/R/modules.R  -- Shiny module
#' @export
signal_timeline_ui <- function(id, splash_size = 2000L) { ... }
#' @export
signal_timeline_server <- function(id, signals_path, ...) { ... }
```

Then each app's `signal_timeline.R` collapses to:

```r
box::use(
  signalviz[signal_timeline_ui, signal_timeline_server]
)

#' @export
ui <- function(id) signal_timeline_ui(id, splash_size = 2000L)

#' @export
server <- function(id) {
  signal_timeline_server(id,
    signals_path = "data/signals.parquet",
    default_pair = list(drug = "vioxx", event = "Myocardial infarction")
  )
}
```

### purrr / tidyverse opportunities

In `pair_stats_full()` (faers-mobi/signal_timeline.R, ~lines 595–610), the column filter list construction:

```r
searchCols = local({
  list(
    NULL, NULL, NULL, NULL, NULL,
    list(search = "3 ... 9999"),
    NULL, ...
  )
})
```

Replace with a named-driven approach using `purrr::map`:

```r
build_search_cols <- function(col_filters, ncol) {
  cols <- vector("list", ncol)
  purrr::iwalk(col_filters, \(filter, idx) cols[[idx]] <<- filter)
  cols
}
```

Also, the per-row `mapply` in `.enrich_label_match()` (faers-mobi/signal_timeline.R lines 295–315) should be `purrr::pmap_dfr()`:

```r
purrr::pmap_dfr(list(ps_subset$drug, ps_subset$event), \(drug, event) {
  row <- find_label_row(lbl, drug, diana)
  if (nrow(row) == 0 || is.na(row$set_id[1])) return(tibble(novel = NA, treats = NA))
  ...
  tibble(novel = novel, treats = treats)
})
```

This is materially faster (no character-coercion via `mapply`'s matrix return) and easier to read.

---

## 2. Algorithm Correctness — GPS/EBGM Implementation

**Verdict: The implementation is correct in structure (it does mix two Gamma components with proper posterior weights and root-finds the mixture quantile), but contains one notable deviation from DuMouchel (1999).**

### What is correct

- **`safetysignal/R/posterior.R`** properly forms both posterior shape parameters (`alpha_k_post = alpha_k + observed`) and rate parameters (`beta_k_post = beta_k + expected`) for each component (lines 26–32). ✓
- **Mixture weight update** uses the Negative Binomial marginal likelihood with log-sum-exp normalization (lines 34–53). The form `dnbinom(observed, size = alpha_k, prob = beta_k / (beta_k + E))` is the correct Gamma-Poisson marginal. ✓
- **`safetysignal/R/percentile.R`** uses `uniroot()` on the actual mixture CDF `q * pgamma(...) + (1-q) * pgamma(...)` (lines 53–56), which is the correct posterior quantile of the two-component mixture. ✓
- The E-step weights (`q_post`) are recalculated per (drug, event) cell, exactly as DuMouchel specifies. ✓

### Deviation from DuMouchel (1999)

In **`safetysignal/R/prior.R` lines 76–81 (M-step)**:

```r
fit1 <- gamma_shape_mle(rr, weights = r)
fit2 <- gamma_shape_mle(rr, weights = 1 - r)
```

The prior is being fit to the **observed RR values** `rr = observed/expected`, treating each pair as a single observation. **This is not DuMouchel's likelihood.** DuMouchel fits the prior by maximizing the marginal likelihood of the *counts*, not the RRs:

$$ L(\theta) = \prod_i \left[\pi \cdot \mathrm{NB}(n_i; \alpha_1, \beta_1/(\beta_1+E_i)) + (1-\pi) \cdot \mathrm{NB}(n_i; \alpha_2, \beta_2/(\beta_2+E_i))\right] $$

The current code is closer to fitting a Gamma mixture to a kernel density of `n/E`, which:
- Ignores the Poisson sampling variance (small-E pairs are over-weighted),
- Cannot use cells where `observed = 0` (these are dropped at line 41 `rr > 0`),
- Will give wrong shrinkage for pairs with very small expected counts.

**Recommendation:** Replace the M-step with proper NB-marginal-likelihood EM. The classic reference implementation is the `openEBGM` CRAN package (`autoHyper()` and `hyperEM()`), which Ahmed & Poncet 2016 verified against DuMouchel. You could also benchmark against `PhViD::GPS()`. I'd add a unit test that compares the prior fit on a known FAERS slice to `openEBGM::autoHyper()` output and asserts the EBGM values are within ~5%.

### Other minor issues

- **`safetysignal/R/prior.R` line 53**: the moment-based init splits at the median, which is fragile when most RRs are concentrated near 1. DuMouchel's quasi-Newton-with-restarts initialization is more robust.
- The `gamma_shape_mle()` Newton-Raphson has no safeguard against `s <= 0` due to weighting — when responsibilities concentrate on one tail, the function aborts. Add a graceful fallback rather than `cli_abort`.
- **EB05 ≠ "EB05 ± offset"**: this is computed correctly via `uniroot` on the true mixture CDF, so the marketing copy in the apps is accurate. ✓

---

## 3. Drug / Event Name Alignment

**Verdict: Partially fixed via DiAna, but the rollup happens at the wrong layer.**

### Current state

Looking at `faers-mobi/app/view/signal_timeline.R`:
- The pipeline emits **two** parquet files: `signals.parquet` (drug-level, 44k+ raw names) and `signals_substance.parquet` (DiAna-rolled, ~3,000 substances + 29k unresolved long-tail).
- The toggle (lines 343–355) lets the user pick which one to display.
- DiAna is consulted only **after** signal computation — `diana_dictionary.parquet` is loaded in `diana_dict()` and used for display labels and the brand→substance crosswalk in fuzzy search.

### The actual problem

The denominator inflation/deflation occurs **upstream**, in `faers-pipeline` (not shown in your archive but inferred). The fact that you have a `signals_substance.parquet` means the pipeline does run rollup, which is the correct place. **But:**

1. **Per-row 5% of report volume falls into the unresolved long-tail.** Comments in the code acknowledge: "Drugs DiAna can't resolve (~5% of report volume, ~91% of distinct long-tail strings)." For very rare drugs or new-market entrants this matters far more than 5% suggests.

2. **Brand name fragmentation in the drug-level view systematically inflates `class_co_flags`** ("86 ibuprofen brands all flagging GI bleeding => co_flags can hit 80+") — see comments at faers-mobi `signal_timeline.R` ~line 60. This is acknowledged with `CLASS_EFFECT_THRESHOLD_SUB`, but the threshold is the same (5) for both modes, defeating the rationale.

3. **No event-side normalization.** MedDRA PTs *should* be canonical (they're a controlled vocabulary), but FAERS reports often contain LLT strings, free-text variants, or misspellings. The pipeline does not appear to roll LLT→PT or apply a canonical MedDRA mapping. The MedDRA hierarchy file is loaded only for synonym expansion in label-matching, not for normalization at ingestion.

### Recommendations

1. **Add a third parquet: `signals_canonical.parquet`** that resolves both drugs (via DiAna *plus* a curated ATC code fallback for the long-tail) and events (via MedDRA LLT→PT lookup). Make it the default.
2. **In the pipeline, log the rollup loss rate** per quarter — track what fraction of reports cannot be resolved to substance, and surface this as a quality metric in the About tab.
3. **Calibrate `CLASS_EFFECT_THRESHOLD` empirically per mode** rather than setting both to 5. A bootstrap on a known class-effect set (statins + myalgia, NSAIDs + GI bleed) would give defensible thresholds.

---

## 4. Fuzzy Search — Current State and Gaps

### Evaluation of current implementation (`signal_timeline.R` lines 200–260)

**`agrep` with `max.distance = 0.2`:**
- For a 7-char query, this allows 1.4 edits — appropriate for typos like "ozempic"/"ozempik."
- For a 12-char query like "rivaroxaban," it allows ~2.4 edits, which is generous.
- The **length-ratio guard** (`nchar <= q_norm * 2.5 + 3`, line 235) is a clever safety net but ad-hoc.

**Verdict on 0.2:** Probably too loose for short medical terms (4–6 chars) and too tight for long compound names. The fact that you had to introduce `AGREP_MIN_LEN = 5L` and the length-ratio guard is evidence the threshold is poorly calibrated.

**The `< 5 chars` agrep skip:** Defensible — at 4 chars, `max.distance = 0.2` rounds to 0 anyway, and false positives explode. You could push this to 6 with little loss.

### Recommended replacement: `stringdist` + `fuzzyjoin`

```r
# Replace agrep with stringdist::amatch using Jaro-Winkler
match_fuzzy_jw <- function(query, names, threshold = 0.15) {
  q_norm <- normalize_spelling(tolower(query))
  n_norm <- normalize_spelling(tolower(names))
  
  # Exact substring still gets priority
  exact_idx <- which(stringr::str_detect(n_norm, stringr::fixed(q_norm)))
  
  # Jaro-Winkler for typo tolerance — empirically much better than 
  # Levenshtein for short medical terms
  jw_dist <- stringdist::stringdist(q_norm, n_norm, method = "jw", p = 0.1)
  fuzzy_idx <- which(jw_dist < threshold)
  
  unique(names[union(exact_idx, fuzzy_idx)])
}
```

### Recommendations

1. **Switch to Jaro-Winkler** (`stringdist::stringdist(method = "jw")`) — better for short strings and much faster than `agrep` on 15k vocabularies.
2. **Tier the matching:** exact substring (always), then prefix match, then JW < 0.10 (high precision), then JW < 0.20 (recall pass). Show separate counts in the status bar.
3. **For multi-word queries, tokenize and require all tokens to match** — "myocardial infarct" should match "Myocardial infarction" not "Myocarditis."
4. **Add a phonetic option** (`phonetic::soundex` or `metaphone`) for drug names — handles "Ozempic"/"ozempik" but also "Coumadin"/"Cumadin." Best as opt-in.
5. **Index the events with `fuzzyjoin::stringdist_inner_join`** for downstream pair lookups — much faster than per-query rescans.

A practical gain: the current "ozempic → clorazepic acid" false positive is a Levenshtein artifact. Jaro-Winkler with the prefix bonus would not produce it.

---

## 5. Signal Pair Filtering — Relevance

The current filters (blacklist of admin/product PTs, class co-flags, Weber adjustment, novelty) are good. Additional improvements:

### Systematic FP patterns currently missed

1. **Indication-confounding (protopathic bias).** A drug used to treat condition X will appear correlated with X's symptoms. Example: anti-emetics signaling for "nausea." The `Treats` flag (lines 295–305 of `.enrich_label_match`) does this for explicit indications, but doesn't catch precursor symptoms. Add an indication-CUI ancestor check via the MedDRA hierarchy — drop pairs where the event is in the SOC of any indicated condition.

2. **Channeling bias for second-line therapies.** Drugs prescribed only after first-line failure inherit the failure modes of first-line drugs. There's no easy automated fix; flag drugs whose typical-use is documented as "second-line" via the label.

3. **Comparator drugs co-reported.** When report mentions both drug A and drug B, both get the event credit. The current pipeline likely uses primary suspect only; if not, switch to PS-only or run a sensitivity analysis.

4. **Country/reporting-system bias.** FAERS over-represents US AEs; some events are over-reported in lawyer-driven reporting (talc → ovarian cancer is the textbook case). No current mitigation; consider down-weighting reports flagged as "consumer/lawyer source."

### Temporal biases beyond Weber

- **Notoriety bias / DEAR (Drug-Event-Activated-Reporting)** — when an FDA Drug Safety Communication is issued, retrospective reports flood in. The current `is_emerging` flag amplifies this. Recommendation: cross-reference DEAR-eligible events against an FDA DSC date list and add a `post_dsc` flag rather than blindly elevating "emerging" status.
- **Calendar-time effects** unrelated to drug — e.g., influenza-vaccine season. For VAERS this is critical and isn't currently addressed.

### Low-count handling

Currently all pairs with `n_methods_flagged ≥ 2` enter the table regardless of `observed`. This includes pairs with `a = 3, 4`. Recommendations:

- Stratify the display: show `n < 5` pairs only when explicitly requested (a "Show low-count signals" toggle), with prominent warning.
- For low-count pairs, the GPS shrinkage already pulls EB05 toward 1, but the PRR/ROR CIs are wide and the chi-square is unreliable. Consider hiding `is_signal_prr` for `a < 5` regardless of the threshold, and rely on IC025 for low counts (which has well-defined behavior at small N).

---

## 6. Top 100 Signal Pairs — Validation Set

Below is a representative validation set spanning known associations (positive controls), known class effects, and well-publicized novel signals. EB05 ranges are approximate based on published FAERS analyses.

| # | Drug (substance) | Event (PT) | Expected EB05 | Status | Reference |
|---|---|---|---|---|---|
| 1 | rofecoxib | Myocardial infarction | 8–15 | Known (withdrawn 2004) | Vioxx litigation |
| 2 | rosiglitazone | Myocardial infarction | 4–8 | Known | Nissen 2007 |
| 3 | cerivastatin | Rhabdomyolysis | 20–40 | Known (withdrawn 2001) | Baycol |
| 4 | troglitazone | Hepatic failure | 15–30 | Known (withdrawn 2000) | Rezulin |
| 5 | semaglutide | Cholecystitis acute | 4–8 | Known | EMA 2022 PRAC |
| 6 | semaglutide | Pancreatitis acute | 3–6 | Known (label) | GLP-1 class |
| 7 | semaglutide | Gastroparesis | 5–12 | Known (recent label) | 2023 update |
| 8 | semaglutide | Suicidal ideation | 2–4 | Investigated, EMA cleared | 2024 |
| 9 | liraglutide | Pancreatitis acute | 3–6 | Known | GLP-1 class |
| 10 | exenatide | Pancreatitis acute | 4–7 | Known | GLP-1 class |
| 11 | tirzepatide | Cholecystitis acute | 3–6 | Known | GLP-1 class |
| 12 | empagliflozin | Diabetic ketoacidosis | 5–10 | Known | SGLT2 class |
| 13 | dapagliflozin | Diabetic ketoacidosis | 5–10 | Known | SGLT2 class |
| 14 | canagliflozin | Lower limb amputation | 4–8 | Known | CANVAS trial |
| 15 | atorvastatin | Rhabdomyolysis | 3–6 | Known (label) | Statin class |
| 16 | simvastatin | Rhabdomyolysis | 4–8 | Known | Statin class |
| 17 | atorvastatin | Myalgia | 2–4 | Known | Statin class |
| 18 | clopidogrel | Thrombotic thrombocytopenic purpura | 8–15 | Known | Bennett 2000 |
| 19 | warfarin | Haemorrhage intracranial | 3–6 | Known (boxed) | Anticoagulant |
| 20 | rivaroxaban | Gastrointestinal haemorrhage | 4–8 | Known | DOAC class |
| 21 | apixaban | Gastrointestinal haemorrhage | 3–6 | Known | DOAC class |
| 22 | dabigatran | Gastrointestinal haemorrhage | 5–10 | Known | RE-LY |
| 23 | metformin | Lactic acidosis | 3–6 | Known (boxed) | Biguanide |
| 24 | infliximab | Tuberculosis | 8–15 | Known (boxed) | TNF class |
| 25 | adalimumab | Tuberculosis | 6–12 | Known (boxed) | TNF class |
| 26 | etanercept | Lymphoma | 3–6 | Known (boxed) | TNF class |
| 27 | natalizumab | Progressive multifocal leukoencephalopathy | 30–60 | Known (boxed) | Tysabri |
| 28 | rituximab | Progressive multifocal leukoencephalopathy | 8–15 | Known (boxed) | Anti-CD20 |
| 29 | clozapine | Agranulocytosis | 15–30 | Known (REMS) | Atypical antipsychotic |
| 30 | clozapine | Myocarditis | 8–15 | Known | |
| 31 | olanzapine | Diabetes mellitus | 3–6 | Known | Atypical class |
| 32 | quetiapine | Diabetes mellitus | 2–5 | Known | Atypical class |
| 33 | aripiprazole | Pathological gambling | 8–15 | Known (FDA 2016) | |
| 34 | varenicline | Suicidal ideation | 4–8 | Known (boxed, removed 2016) | Chantix |
| 35 | montelukast | Suicidal ideation | 3–6 | Known (boxed 2020) | Singulair |
| 36 | montelukast | Depression | 3–6 | Known (boxed 2020) | |
| 37 | isotretinoin | Depression | 3–6 | Known (boxed) | Accutane |
| 38 | isotretinoin | Inflammatory bowel disease | 2–4 | Disputed/controversial | |
| 39 | finasteride | Erectile dysfunction | 4–8 | Known (label) | Propecia |
| 40 | finasteride | Suicidal ideation | 3–6 | Known (label 2022) | Post-finasteride syndrome |
| 41 | levofloxacin | Tendon rupture | 8–15 | Known (boxed) | Fluoroquinolone class |
| 42 | ciprofloxacin | Tendon rupture | 6–12 | Known (boxed) | Fluoroquinolone class |
| 43 | ciprofloxacin | Aortic aneurysm | 4–8 | Known (label 2018) | |
| 44 | levofloxacin | Peripheral neuropathy | 4–8 | Known (label) | |
| 45 | gadolinium-based contrast | Nephrogenic systemic fibrosis | 30–60 | Known (boxed) | |
| 46 | proton pump inhibitors (omeprazole) | Clostridium difficile colitis | 3–6 | Known (label 2012) | PPI class |
| 47 | omeprazole | Acute interstitial nephritis | 3–6 | Known | PPI class |
| 48 | esomeprazole | Acute interstitial nephritis | 3–6 | Known | PPI class |
| 49 | omeprazole | Hypomagnesaemia | 4–8 | Known (label 2011) | PPI class |
| 50 | bisphosphonate (alendronate) | Osteonecrosis of jaw | 8–15 | Known (label) | |
| 51 | alendronate | Atypical femoral fracture | 6–12 | Known (label 2010) | |
| 52 | denosumab | Osteonecrosis of jaw | 8–15 | Known (boxed) | |
| 53 | hydroxychloroquine | Retinopathy | 4–8 | Known (label) | |
| 54 | amiodarone | Pulmonary fibrosis | 8–15 | Known (boxed) | |
| 55 | amiodarone | Hypothyroidism | 6–12 | Known (label) | |
| 56 | amiodarone | Hyperthyroidism | 6–12 | Known | |
| 57 | linezolid | Serotonin syndrome | 6–12 | Known (label) | MAOI activity |
| 58 | linezolid | Lactic acidosis | 4–8 | Known | |
| 59 | tramadol | Serotonin syndrome | 4–8 | Known | |
| 60 | tramadol | Seizure | 4–8 | Known (label) | |
| 61 | bupropion | Seizure | 3–6 | Known (label) | |
| 62 | methotrexate | Pulmonary fibrosis | 4–8 | Known (label) | |
| 63 | methotrexate | Hepatic fibrosis | 4–8 | Known (label) | |
| 64 | tacrolimus | Renal failure | 3–6 | Known (label) | |
| 65 | cyclosporine | Renal failure | 3–6 | Known (label) | |
| 66 | abacavir | Hypersensitivity | 30–60 | Known (HLA-B*5701) | |
| 67 | carbamazepine | Stevens-Johnson syndrome | 8–15 | Known (HLA-B*1502 boxed) | |
| 68 | allopurinol | Stevens-Johnson syndrome | 6–12 | Known | |
| 69 | lamotrigine | Stevens-Johnson syndrome | 8–15 | Known (boxed) | |
| 70 | sulfasalazine | Stevens-Johnson syndrome | 6–12 | Known | |
| 71 | nitrofurantoin | Pulmonary fibrosis | 8–15 | Known (label) | |
| 72 | minocycline | Drug reaction with eosinophilia | 6–12 | Known | DRESS |
| 73 | vancomycin | Drug reaction with eosinophilia | 4–8 | Known | DRESS |
| 74 | sulfamethoxazole-trimethoprim | Stevens-Johnson syndrome | 6–12 | Known (label) | |
| 75 | acetaminophen | Hepatic failure | 3–6 | Known (boxed) | |
| 76 | valproate | Hepatic failure | 4–8 | Known (boxed) | |
| 77 | valproate | Pancreatitis | 4–8 | Known (boxed) | |
| 78 | febuxostat | Cardiac death | 3–5 | Known (boxed 2019) | CARES trial |
| 79 | tofacitinib | Venous thromboembolism | 4–8 | Known (boxed 2019) | ORAL Surveillance |
| 80 | tofacitinib | Major adverse cardiovascular events | 3–6 | Known (boxed 2021) | |
| 81 | baricitinib | Venous thromboembolism | 3–6 | Known | JAK class |
| 82 | upadacitinib | Venous thromboembolism | 3–6 | Known | JAK class |
| 83 | dronedarone | Hepatic failure | 4–8 | Known (boxed 2011) | |
| 84 | belimumab | Suicidal ideation | 2–4 | Known (label) | |
| 85 | abacavir | Myocardial infarction | 2–4 | Disputed (D:A:D study) | |
| 86 | atomoxetine | Suicidal ideation | 3–6 | Known (boxed) | |
| 87 | atomoxetine | Hepatotoxicity | 3–6 | Known (label) | |
| 88 | rosuvastatin | Diabetes mellitus | 2–4 | Known (label, statin class) | |
| 89 | metoclopramide | Tardive dyskinesia | 8–15 | Known (boxed) | |
| 90 | omalizumab | Anaphylaxis | 4–8 | Known (boxed) | |
| 91 | natalizumab | Hepatic failure | 3–6 | Known (label) | |
| 92 | ipilimumab | Colitis | 15–30 | Known (boxed) | Checkpoint inhibitor |
| 93 | nivolumab | Pneumonitis | 8–15 | Known (label) | Checkpoint inhibitor |
| 94 | pembrolizumab | Pneumonitis | 8–15 | Known (label) | Checkpoint inhibitor |
| 95 | nivolumab | Myocarditis | 8–15 | Known (label) | Checkpoint inhibitor |
| 96 | pembrolizumab | Hypophysitis | 15–30 | Known (label) | Checkpoint inhibitor |
| 97 | trastuzumab | Cardiac failure | 6–12 | Known (boxed) | |
| 98 | doxorubicin | Cardiomyopathy | 6–12 | Known (boxed) | |
| 99 | thalidomide | Phocomelia | 30–60+ | Historical (Known) | (in older AERS) |
| 100 | terfenadine | Torsade de pointes | 15–30 | Known (withdrawn 1998) | |

For VAERS, similar set: COVID19+myocarditis (mRNA, EB05 ~30+), Janssen+TTS (EB05 ~18), influenza+Guillain-Barre (1976 swine flu & subsequent, EB05 ~3–6), MMR+thrombocytopenic purpura (EB05 ~4–8).

**Use:** Run this list against the deployed app and flag any that don't appear in the top 2,000 splash. Misses indicate either pipeline drug-name resolution failures (e.g., "ipilimumab" reported as "Yervoy" only) or filtering that's too aggressive.

---

## 7. PICO DAG — Node Label Trimming

Looking at `pico-dag/app/R/network_viz.R` (lines 33–45), labels are already trimmed via `stringr::str_trunc(data$related_name[i], 30)`. This is rule-based and naive — it cuts mid-word and produces things like "Disorder characterized by p…" which are unreadable.

### Recommendations

**Tiered trimming strategy (rule-based, no model needed):**

```r
trim_concept_label <- function(label, max_chars = 30) {
  # 1. Strip generic UMLS/SNOMED suffixes
  label <- stringr::str_remove(label, " \\((disorder|finding|substance|product|qualifier value|morphologic abnormality|observable entity|procedure)\\)$")
  
  # 2. Strip common verbose prefixes that add no clinical information
  label <- stringr::str_remove(label, "^(Disorder of|Disease of|Finding of|Disorder characterized by) ")
  
  # 3. Replace common phrases with abbreviations
  label <- stringr::str_replace_all(label, c(
    "Type 2 diabetes mellitus" = "T2DM",
    "Myocardial infarction" = "MI",
    "Cerebrovascular accident" = "Stroke",
    "Acute kidney injury" = "AKI",
    "Atrial fibrillation" = "AFib"
  ))
  
  # 4. If still too long, truncate at word boundary
  if (nchar(label) > max_chars) {
    label <- stringr::str_extract(label, paste0("^.{1,", max_chars - 1, "}\\b"))
    label <- paste0(label, "…")
  }
  
  label
}
```

**Hover tooltip should show the full label** — it already does via the `title` field (lines 38–43). The truncation is purely visual.

**Model-based trimming is overkill** for this domain. UMLS preferred terms follow predictable patterns; rule-based handles >95% of cases. Consider model-based (e.g., a small T5 fine-tuned on UMLS abbreviations) only if you find recurring failure cases.

---

## 8. PICO DAG — Interactive Nodes as Search Terms

The current implementation uses `visNetwork::visOptions(nodesIdSelection = TRUE)` (line 110), which exposes a dropdown but doesn't trigger expansion on click.

### Implementation sketch

`visNetwork` natively supports click events via `visEvents()`. Wire it like this:

```r
# In R/network_viz.R — modify build_dag_network() to inject the click handler

build_dag_network <- function(dag_result, pico_elements = list(), 
                              ns_prefix = NULL) {
  # ... existing node/edge construction ...
  
  vn <- visNetwork::visNetwork(nodes, edges, width = "100%", height = "600px") |>
    # ... existing visGroups, visLegend, visOptions, visPhysics ...
    visNetwork::visEvents(
      selectNode = sprintf(
        "function(properties) {
          if (properties.nodes.length > 0) {
            var clicked_cui = properties.nodes[0];
            Shiny.setInputValue('%snode_clicked', clicked_cui, {priority: 'event'});
          }
        }",
        if (is.null(ns_prefix)) "" else ns_prefix
      )
    )
  vn
}
```

Then in the server (`app/app.R`):

```r
# Capture the click; reactive trigger when CUI changes
observeEvent(input$node_clicked, {
  new_cui <- input$node_clicked
  
  # Skip if this node is already the root
  req(!is.null(new_cui), new_cui != rv$pop_cui)
  
  # Confirm with user (clicking shouldn't blow away their state silently)
  showModal(modalDialog(
    title = "Re-root DAG?",
    paste0("Re-run DAG expansion using '", new_cui, "' as the new root concept?"),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_reroot", "Re-root", class = "btn-primary")
    ),
    easyClose = TRUE
  ))
  
  # Stash the candidate CUI for the confirm handler
  rv$pending_reroot_cui <- new_cui
})

observeEvent(input$confirm_reroot, {
  removeModal()
  req(rv$pending_reroot_cui)
  
  # Update the population CUI and trigger re-walk
  rv$pop_cui <- rv$pending_reroot_cui
  
  # Optionally update the search box too
  updateTextInput(session, "pop_term", value = rv$pending_reroot_cui)
  
  # Re-walk
  withProgress(message = "Walking DAG from new root...", {
    rv$dag_result <- walk_concept_dag(
      rv$pop_cui,
      progress = \(msg) setProgress(message = msg)
    )
    rv$pop_concept <- rv$dag_result$concept
  })
  
  rv$pending_reroot_cui <- NULL
})
```

### Key design considerations

1. **Confirm before re-rooting** — the DAG walk takes 5–30 seconds and clears the user's exploration state. A modal is friendlier than auto-recompute.

2. **Maintain a navigation history** — push prior `pop_cui` values onto a stack so the user can "back-button" through their exploration:
   ```r
   rv$nav_history <- c(rv$pop_cui, rv$nav_history)
   ```
   Render a breadcrumb above the network: `Atrial Fibrillation → Stroke → Embolism`.

3. **Filter clickable nodes by category.** Not every node should be re-rootable — clicking a leaf "monitoring lab" to make it the new root makes no sense. Pass category via the node `group` field and gate in the JS handler:
   ```js
   var node = nodes.get(properties.nodes[0]);
   if (['treatment', 'comorbidity', 'subtype', 'parent'].includes(node.group)) {
     Shiny.setInputValue(...);
   }
   ```

4. **Cache results.** Re-walking from a CUI you've already visited is wasteful; memoize on `cui`:
   ```r
   walk_cache <- shiny::reactiveVal(list())
   # ... in observer:
   cache <- walk_cache()
   if (!is.null(cache[[new_cui]])) {
     rv$dag_result <- cache[[new_cui]]
   } else {
     rv$dag_result <- walk_concept_dag(new_cui, ...)
     cache[[new_cui]] <- rv$dag_result
     walk_cache(cache)
   }
   ```

5. **Consider `visNetworkProxy` for incremental updates** rather than full re-render. If the new root is already a node in the current graph, you can recolor it as the root and add new edges incrementally rather than redrawing.

---

## Summary of Priorities

| Priority | Item | Effort |
|----------|------|--------|
| **High** | Extract shared code into `signalviz` package (Q1) | 2–3 days |
| **High** | Replace prior fitting M-step with NB marginal likelihood (Q2) | 1 day + validation |
| **High** | Switch fuzzy search to `stringdist` Jaro-Winkler (Q4) | 0.5 day |
| **Medium** | Add canonical (drug + event) parquet path (Q3) | 1–2 days |
| **Medium** | Implement node-click re-rooting in pico-dag (Q8) | 0.5 day |
| **Medium** | Add MedDRA hierarchy-based indication confounding filter (Q5) | 1 day |
| **Low** | Improve DAG label trimming (Q7) | 2 hours |
| **Low** | Run top-100 validation set against deployed app (Q6) | 0.5 day |

References used: DuMouchel W (1999) "Bayesian Data Mining in Large Frequency Tables, with an Application to the FDA Spontaneous Reporting System," *The American Statistician* 53(3):177–190 [1]; Bate A et al. (1998) [2]; Evans SJW et al. (2001) [3]; van Puijenbroek EP et al. (2002) [4]; Ahmed I & Poncet A, `openEBGM` CRAN package [5]; Weber JCP (1984) on the Weber effect [6].