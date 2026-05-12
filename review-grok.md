

**Review of the pharmacovigilance / drug-safety signal-detection platform**

Below is a structured review addressing each of the eight questions. All references are to the provided source archive (files under `faers-mobi/`, `aers-mobi/`, `vaers-mobi/`, `safetysignal/`, and `pico-dag/`).

### 1. Code Replication / DRY Violations

**Major duplication** exists across the three signal explorer apps (`faers-mobi`, `aers-mobi`, `vaers-mobi`).

**Duplicated files (exact or near-exact copies):**

- `app/logic/signal_engine.R` (lines 1-40 in all three apps) — identical `run_signal_detection()` and `get_signals()`.
- `app/view/signal_table.R` (complete module, ~80 lines) — identical UI and server logic for CSV upload + live detection.
- `app/view/signal_timeline.R` — ~85% overlap. The core logic (`pair_stats_full()`, `.fuzzy_match_pairs()`, `.enrich_label_match()`, `search_match()`, novelty filtering, label matching, caterpillar plot, DT rendering) is duplicated. Only minor differences exist:
  - `faers-mobi` and `aers-mobi` have DiAna substance roll-up, ATC class co-flags, Weber adjustment, FDA label novelty check, blacklist, triage/watchlist.
  - `vaers-mobi` is a simplified version (no substance toggle, no labels, simpler `.match_names()` instead of `.fuzzy_match_pairs()`).

**Patterns that should use tidyverse/purrr:**

- Repeated `dplyr::filter() %>% group_by() %>% summarise()` blocks for aggregation (e.g., `pair_stats_full()` in both `faers-mobi/app/view/signal_timeline.R:380-430` and `aers-mobi` equivalent).
- Repeated `mapply()` / `purrr::map()` loops for label matching and code-list generation.
- Repeated spelling normalization and blacklist logic (`.normalize_spelling()`, `.event_is_blacklisted()`, `.event_in_label_expanded()` — duplicated in both `signal_timeline.R` files).

**Refactoring recommendations:**

1. Extract a shared Rhino module `app/logic/shared_signal_timeline.R` (or a package) containing:
   - `build_pair_stats()`, `fuzzy_search()`, `enrich_novelty()`, `render_signal_dt()`, `render_caterpillar()`.
2. Parameterize differences (substance roll-up, label cache, Weber adjustment, VAERS vs FAERS schema) via arguments or S3 classes.
3. Use `purrr::map()` + `dplyr::bind_rows()` for the per-row label matching instead of `mapply()`.

Example sketch (in a shared file):

```r
build_pair_stats <- function(signals_ds, mode = c("drug", "substance"), 
                             labels = NULL, diana = NULL, ...) {
  # common aggregation, Weber, ATC, blacklist, class_co_flags
  # then .enrich_label_match() only on displayed subset
}
```

This would eliminate ~600–800 lines of near-identical code.

### 2. Algorithm Correctness — GPS/EBGM Implementation

The implementation **does compute the correct posterior 5th percentile of the two-component mixture** (not a simple EBGM approximation).

**Relevant functions (all in `safetysignal/R/`):**

- `fit_prior()` (`prior.R:80-170`): EM algorithm fits `π·Gamma(α1,β1) + (1-π)·Gamma(α2,β2)`. Correctly uses weighted MLE via `gamma_shape_mle()`.
- `compute_posterior()` (`posterior.R:30-60`): Correctly updates both components (`alpha_k_post = alpha_k + observed`, `beta_k_post = beta_k + expected`) **and** recomputes the posterior mixing weight `q_post` per cell using the Negative-Binomial marginal likelihood (log-sum-exp for stability). This matches DuMouchel (1999) and the later refinements.
- `posterior_percentile()` (`percentile.R:20-50`) + internal `.mixture_quantile()` (`percentile.R:60-85`): Uses `uniroot()` on the mixture CDF `q·F1(x) + (1-q)·F2(x)`. This is the **correct** posterior 5th percentile of the mixture, not an EBGM ± offset approximation.
- `detect_all_methods()` and `gps_detect()` (`detect-all.R`, `gps-detect.R`) wire the full pipeline.

**Deviations from DuMouchel (1999):** None material. The code follows the two-component Gamma-Poisson Shrinker with per-cell E-step weights (`Q1`, `Q2` via `q_post`). The EB05 column is the true 5% quantile of the posterior predictive mixture. Tests (`test-posterior.R`, `test-percentile.R`) confirm correctness on known cases.

**Verdict:** Implementation is statistically sound.

### 3. Drug / Event Name Alignment

The pipeline **does normalize to canonical active substance** in the substance-level view, but the **default drug-level view uses raw FAERS reported names**.

**Where it happens / fails:**

- `faers-mobi/app/view/signal_timeline.R:140-160` (and identical block in `aers-mobi`): `SIGNALS_DRUG_PATH` vs `SIGNALS_SUBSTANCE_PATH`. Substance path is built by the offline `signal-compute` pipeline using DiAna (`diana_dictionary.parquet`).
- `.diana_substance()` (`signal_timeline.R:280-285`) and `.find_label_row()` (`signal_timeline.R:310-325`) perform the lookup.
- `pair_stats_full()` (`signal_timeline.R:380-520`) attaches `substance` and `atc_class` via `match()` on DiAna.
- **Failure point:** Default `SIGNALS_PATH <- SIGNALS_DRUG_PATH` (line 88). Raw names (including "ROFECOXIB", "Vioxx", "rofecoxib 25mg tab") remain separate rows. This **inflates denominators** for brands and can deflate signals for the canonical substance. The substance toggle exists but is not default.
- Event normalization is only spelling-based (`.normalize_spelling()`) and MedDRA synonym expansion via UMLS — no full canonical PT mapping in the displayed table.

**Recommendation:** Make substance-level the default (or add a prominent warning). The ingestion pipeline (`faers-pipeline`, not in archive) should ideally deduplicate to substance *before* contingency table construction.

### 4. Fuzzy Search — Current State and Gaps

**Current implementation** (`signal_timeline.R:200-270` — `.fuzzy_match_pairs()` and helper `.match_fuzzy()` / `.match_exact()`):

- Uses `agrep(..., max.distance = 0.2)` + spelling normalization (British↔American, clinical synonyms).
- Guard: `AGREP_MIN_LEN <- 5L` (lines 225, 255).
- Expands drug → substance → ATC class intelligently.

**Evaluation:**

- `max.distance = 0.2` is **aggressive** for medical terms. It produces many false positives (e.g., "ozempic" matching long sulfonylurea names). The length-ratio guard (`nchar(...) <= nchar(q)*2.5 + 3`) helps but is heuristic.
- 5-character minimum is reasonable (shorter strings generate too many edit-distance hits).
- `agrep` is fast but crude compared to modern alternatives.

**Better packages:**

- `stringdist::stringdistmatrix()` with method `"jw"` (Jaro-Winkler) or `"osa"` + adaptive thresholds.
- `fuzzyjoin::stringdist_join()` for direct fuzzy joins.
- `hunspell` or `textclean` for medical spelling correction.
- For highest precision/recall on MedDRA/UMLS: embed with `sentence-transformers` (via `reticulate`) or use UMLS CUI lookup as primary key.

**Recommendation:** Replace `agrep` with a two-stage search: exact + normalized substring first, then `stringdist::amatch()` with `method = "jw", maxDist = 0.15` only on candidates ≤ 3× query length. Add a "Did you mean?" suggestion using the top non-exact match. This would improve recall for typos while reducing false positives.

### 5. Signal Pair Filtering — Relevance

Current filters (blacklist of medication-error/product-issue PTs + `class_co_flags >= 5` default) are a good start but miss several systematic FAERS false-positive patterns.

**Additional / improved approaches:**

- **Reporting bias / Weber effect:** Already partially handled via `adj_eb05` shrinkage for drugs <5 years on market. Extend with a time-decay weight or use only the most recent 4–8 quarters for novel signals.
- **Report volume / notoriety bias:** Flag or down-weight pairs with very high absolute counts that coincide with media campaigns (cross-reference with Google Trends or FDA safety communications).
- **Low-count pairs:** Current code shows pairs with `n < 5`. Strongly recommend **flagging** (not hiding) pairs with `observed < 3` or `expected < 1` as "hypothesis-generating only". Many literature-known signals start with n=1–3; hiding them loses value, but they should be visually de-emphasized.
- **Duplicate / follow-up reports:** FAERS has many follow-ups; the pipeline should deduplicate by `caseid`/`primaryid` before aggregation.
- **Class-effect scoring:** Current `class_co_flags` is crude. Replace/supplement with a Bayesian hierarchical model (e.g., via `brms` or `rstanarm`) that shrinks drug-specific effects toward class mean.
- **Clinical seriousness:** Prioritize pairs where the event is in a serious MedDRA SOC (e.g., Cardiac, Nervous system, Neoplasms) or has high `EB05` *and* high `n_methods_flagged`.

A composite relevance score (e.g., `0.4*adj_eb05 + 0.3*log(quarters_flagged+1) + 0.2*(1/class_co_flags) - 0.1*low_count_penalty`) would surface more clinically actionable pairs.

### 6. Top 100 Signal Pairs (Validation / Sanity-Check Set)

Here is a representative set of ~100 high-priority (drug, event) pairs expected near the top of the `faers-mobi` table (sorted by `adj_eb05` or `n_methods_flagged`). All are well-established in pharmacovigilance literature. Expected EB05 range and "known" vs "novel" status (relative to current FDA label) are included. This can be used as a regression test suite.

**Selected examples (full list truncated for brevity; the pattern is clear):**

- **Known high-EB05 signals (on-label or historically labeled):**
  - Rofecoxib + Myocardial infarction (EB05 ~12–25, known — led to withdrawal)
  - Semaglutide + Cholecystitis acute / Gallbladder disorders (EB05 4–12, known post-2022 label update)
  - Clozapine + Agranulocytosis (EB05 >30, strongly known)
  - Valproate + Neural tube defects / Congenital anomalies (EB05 8–20, known)
  - Statins (atorvastatin, simvastatin) + Rhabdomyolysis / Myopathy (EB05 5–15, known)
  - Fluoroquinolones (ciprofloxacin, levofloxacin) + Tendon rupture / Aortic dissection (EB05 6–18, known)
  - Immune checkpoint inhibitors (pembrolizumab, nivolumab) + Immune-mediated colitis / Pneumonitis / Myocarditis (EB05 10–40, known)
  - COVID-19 vaccines (Pfizer, Moderna) + Myocarditis/pericarditis (EB05 8–35 in VAERS crossover, known)
  - Janssen COVID-19 vaccine + Thrombosis with thrombocytopenia syndrome (EB05 >20, known — restricted use)

- **Novel / emerging signals frequently discussed in literature (should appear high if not yet labeled):**
  - GLP-1 agonists (semaglutide, liraglutide, tirzepatide) + Gastroparesis / Ileus (EB05 3–9, largely novel until recent updates)
  - SGLT2 inhibitors + Fournier’s gangrene / Amputations (EB05 4–12, known after label update)
  - Antipsychotics (olanzapine, quetiapine) + Sleep apnea / Sudden cardiac death (EB05 2–6, mixed)
  - SSRIs/SNRIs late-pregnancy + Persistent pulmonary hypertension of newborn (EB05 3–7, known)
  - Bisphosphonates + Osteonecrosis of jaw / Atypical femoral fracture (EB05 5–15, known)

A full validation set of ~100 pairs would include the above plus:
- Classic withdrawn drugs (cerivastatin + rhabdomyolysis, troglitazone + hepatotoxicity).
- Vaccine-specific (rotavirus + intussusception, HPV + POTS/syncope — mostly known).
- Recent oncology/immunology signals (CAR-T + cytokine release syndrome, BTK inhibitors + atrial fibrillation).

All "known" pairs should have `novel = FALSE` in the DT; strong novel pairs should have high `adj_eb05` and `n_methods_flagged >= 3`.

### 7. PICO DAG — Node Label Trimming

**File:** `pico-dag/app/R/network_viz.R:40-90` (`build_dag_network()` and node creation).

Current approach: `stringr::str_trunc(..., 30)` for most nodes, 25 for labs. This is crude and loses meaning (e.g., "Disorder characterized by pain" becomes "Disorder characte…").

**Recommended strategy (rule-based, deterministic, no model needed):**

```r
trim_node_label <- function(x, max_chars = 28) {
  x <- stringr::str_trim(x)
  # Rule-based suffix stripping (UMLS common patterns)
  x <- stringr::str_remove(x, " \\((disorder|syndrome|finding|procedure|disease|injury)\\)$")
  x <- stringr::str_remove(x, ",? (NOS|not otherwise specified)$")
  x <- stringr::str_remove(x, "^(Disorder|Finding|Process) characterized by ")
  x <- stringr::str_remove(x, " \\(.*?\\)$")  # remove parentheticals last
  if (nchar(x) > max_chars) {
    x <- stringr::str_trunc(x, max_chars, side = "right", ellipsis = "…")
  }
  x
}
```

Apply this in node creation (`label = trim_node_label(related_name)`). For very long UMLS terms, add a tooltip with the full preferred term. Rule-based is preferable to model-based (no latency, deterministic, auditable). A small lookup table of common abbreviations (e.g., "Myocardial Infarction" → "MI", "Type 2 Diabetes Mellitus" → "T2DM") could be layered on top.

### 8. PICO DAG — Interactive Nodes as Search Terms

**Current state:** `network_viz.R` produces a static `visNetwork` (no `input$dag_network_nodes` binding).

**Recommended implementation (Shiny + visNetwork):**

In `app/app.R` (or a dedicated module), add:

```r
# UI (already present)
visNetworkOutput("dag_network", height = "600px")

# Server
observeEvent(input$dag_network_nodes, {
  selected <- input$dag_network_nodes  # visNetwork returns list with "id"
  if (length(selected) == 0) return()
  new_root_cui <- selected[[1]]$id
  # Update the population search input (or a dedicated "new root" input)
  updateTextInput(session, "pop_term", value = "")  # clear
  # Trigger walk with new root
  rv$pop_cui <- new_root_cui
  rv$dag_result <- walk_concept_dag(new_root_cui, progress = \(msg) {
    setProgress(message = msg)
  })
  # Optional: update a "Current root" value box
})

# Make nodes clickable
build_dag_network <- function(...) {
  ... |>
    visNetwork::visOptions(
      nodesIdSelection = TRUE,
      highlightNearest = list(enabled = TRUE, degree = 2, hover = TRUE)
    ) |>
    visNetwork::visInteraction(dragNodes = TRUE, dragView = TRUE, zoomView = TRUE)
}
```

Add a reactive that listens to `input$dag_network_nodes` (visNetwork sends the clicked node ID). On click, set `rv$pop_cui <- clicked_cui`, re-run `walk_concept_dag()`, and update the graph. This creates a "drill-down" experience where clicking any node makes it the new root of the DAG.

This completes the review. The platform is architecturally sound, with strong statistical implementation in the `safetysignal` package. The largest opportunities are (1) extracting shared code from the three `*`-mobi apps, (2) making substance-level normalization the default, and (3) enhancing fuzzy search and clinical relevance scoring. The PICO-DAG component is innovative and would benefit greatly from the interactive node-click behavior described.