

## 1. Code Replication / DRY Violations

### 1.1 Duplicated “live GPS” signal engine (CSV upload tab)
**Duplicated files (near-identical):**
- `faers-mobi/app/logic/signal_engine.R` (entire file)
- `aers-mobi/app/logic/signal_engine.R` (entire file)
- `globalpatientsafety/app/logic/signal_engine.R` (entire file)

All three define the same two functions:
- `run_signal_detection()` (compute OE → fit prior → posterior → EB05/50/95 → detect → sort)
- `get_signals()` (filter and select columns)

**Why it’s a DRY issue**
- Business logic is duplicated across apps; if the `safetysignal` API changes or you change thresholds/defaults once, you must remember to update it 3 times.

**Refactor recommendation**
Put this into a small shared internal package (or a shared R file sourced by Rhino), e.g. `gpsapps` with functions:
- `gpsapps::run_signal_detection()`
- `gpsapps::format_signal_table()`

**Example extraction (package-style)**
Description: Create a shared helper that standardizes percentiles and sorting.
```r
# gpsapps/R/signal_engine.R
#' Run GPS signal detection on drug-event data
#' @param data tibble with columns drug,event or product,event
#' @param drug_col,event_col tidy-select columns
#' @param threshold EB05 threshold
#' @return tibble with EB percentiles + signal flags
run_signal_detection <- function(data, drug_col, event_col, threshold = 1) {
  drug_col  <- rlang::enquo(drug_col)
  event_col <- rlang::enquo(event_col)

  oe <- safetysignal::compute_observed_expected(data, !!drug_col, !!event_col)

  if (nrow(oe) < 10) return(oe)

  prior <- safetysignal::fit_prior(oe)

  oe |>
    safetysignal::compute_posterior(prior) |>
    safetysignal::posterior_percentile(percentile = 0.05, col_name = "eb05") |>
    safetysignal::posterior_percentile(percentile = 0.50, col_name = "eb50") |>
    safetysignal::posterior_percentile(percentile = 0.95, col_name = "eb95") |>
    safetysignal::detect_signals(threshold = threshold, percentile_col = "eb05") |>
    dplyr::arrange(dplyr::desc(.data$eb05))
}
```

Then each app’s `signal_table` server becomes a thin wrapper.

---

### 1.2 Duplicated Shiny “Signal results table module”
**Duplicated files (identical/near-identical):**
- `faers-mobi/app/view/signal_table.R` (entire file)
- `aers-mobi/app/view/signal_table.R` (entire file)
- `vaers-mobi/app/view/signal_table.R` (entire file)
- `globalpatientsafety/app/view/signal_table.R` (entire file)

**Refactor recommendation**
This should be one Rhino module (or shared package module), parameterized by:
- label text (“Upload FAERS/VAERS data” vs generic)
- default threshold range, etc.

Also, the current module UI sets `choices = NULL` for `selectInput(ns("product_filter"), ...)` but never populates it in server in any app (I don’t see an `updateSelectInput()` anywhere in these files). That’s either a bug or unfinished.

---

### 1.3 Duplicated “Signal timeline” logic between faers-mobi and aers-mobi
**Near-identical blocks:**
- `faers-mobi/app/view/signal_timeline.R`: most helper functions + server pipeline (blacklist loading, spelling normalization, label matching, fuzzy match, pair_stats_full, DT rendering, timeline plot)
- `aers-mobi/app/view/signal_timeline.R`: the same, with a few differences (no substance toggle; default row differs; some comments)

**High-value extractions (shared R file)**
- `.load_control_column()` duplicated (faers timeline + aers timeline).  
  Files: `faers-mobi/app/view/signal_timeline.R` and `aers-mobi/app/view/signal_timeline.R` (top helper section)
- `.normalize_spelling()`, `.event_in_label()`, `.event_in_label_expanded()` duplicated with tiny commentary diffs.
- `.diana_substance()`, `.find_label_row()`, `.enrich_label_match()` duplicated.
- `.fuzzy_match_pairs()` duplicated.
- Blacklist defaults duplicated (`.FALLBACK_BLACKLIST_EXACT`, `.FALLBACK_BLACKLIST_PATTERNS`).

**Refactor recommendation**
Create `R/signal_timeline_shared.R` with these helpers and source it from both apps, or make a shared package (preferred).

---

### 1.4 Patterns replaceable by tidyverse/purrr
1) **Manual `mapply()` over rows for label checking**
- In `faers-mobi/app/view/signal_timeline.R`, `.enrich_label_match()` uses `mapply(function(drug, event) ...)` returning a matrix and then indexing rows. Same in AERS.  
  This is OK, but you could improve clarity and allow parallelization later by using `purrr::pmap()` returning a tibble of results and `dplyr::bind_cols()`.

2) **Manual `for` loops building lists of tibbles**
- In `pico-dag/app/R/network_viz.R`, `add_category()` loops row-by-row and appends to `nodes_list` / `edges_list`.
  Replace with vectorized tibble creation plus `bind_rows()`; it will be simpler and faster.

---

## 2. Algorithm Correctness — GPS/EBGM Implementation

### 2.1 Is the posterior computed as the correct 2-component mixture posterior?
**Relevant functions**
- Prior fit: `safetysignal/R/prior.R` → `fit_prior()`  
- Posterior: `safetysignal/R/posterior.R` → `compute_posterior()`  
- Quantiles: `safetysignal/R/percentile.R` → `posterior_percentile()` + `.mixture_quantile()`

**Finding: posterior is a proper 2-component Gamma mixture posterior**
- `compute_posterior()` computes component-wise posteriors:
  - `alpha1_post = prior$alpha1 + observed`
  - `beta1_post  = prior$beta1  + expected`
  - `alpha2_post = prior$alpha2 + observed`
  - `beta2_post  = prior$beta2  + expected`
  This matches the conjugate Gamma-Poisson update for the Poisson mean ratio model.

- It then computes posterior mixture weight `q_post` **per cell** using the marginal likelihood under each component:
  - Uses `dnbinom(observed, size=alpha_k, prob=beta_k/(beta_k+E))` and mixes with `prior$pi`.
  - `q_post` is normalized via a log-sum-exp trick.
  This is the right structure: $$ q_{ij} = \frac{\pi f_1(n_{ij}|E_{ij})}{\pi f_1(n_{ij}|E_{ij}) + (1-\pi) f_2(n_{ij}|E_{ij})} $$ as in the GPS model setup. [1]

**Answer:** Yes—mixture weights are recalculated per (drug,event) cell (`q_post` is a column vector computed row-wise in `compute_posterior()`). The posterior is not a global fixed mixture weight.

---

### 2.2 Is EB05 computed as the 5th percentile of the *mixture posterior*, not an approximation?
**Finding: EB05 is computed using mixture CDF root-finding**
- `posterior_percentile()` calls `.mixture_quantile(p, q_post, alpha1_post, beta1_post, alpha2_post, beta2_post)` for each row.
- `.mixture_quantile()` defines the mixture CDF:  
  `q * pgamma(x; alpha1_post, beta1_post) + (1-q) * pgamma(x; alpha2_post, beta2_post)`
- It then uses `stats::uniroot()` to solve `mix_cdf(x) - p = 0`.

**Answer:** Yes—EB05 is the numerical 5th percentile of the mixture posterior distribution, not “EBGM ± offset”.

---

### 2.3 Deviations / caveats vs DuMouchel (1999)
The code implements a correct *Empirical Bayes mixture* with conjugate posteriors and mixture-quantile computation. The main deviations I see are *modeling/estimation choices* rather than “wrong EB05”:

1) **Prior fitting is done on `rr` directly**
- `fit_prior()` fits a mixture of Gammas to `rr` values (from `compute_observed_expected()`), not via the full marginal likelihood across varying expected counts. In classic GPS, the EM is typically posed using the marginal likelihood of counts given expected, not simply fitting the distribution of observed ratios. This can be a practical approximation but it’s not the full DuMouchel likelihood formulation. [1]

2) **No covariates / stratification inside the model**
- Stratified GPS sometimes models strata (age/sex/report year) and shrinks across them; here you fit a single mixture prior per dataset slice (quarter/window). That is an architecture choice, not an EB05 computation bug.

**Bottom line for Q2:** EB05 is computed as the correct posterior mixture quantile using per-cell posterior mixture weights; the main potential “deviation” is that prior estimation uses a simpler RR-mixture fit rather than the full count/expected marginal likelihood EM described in the GPS literature. [1]

**Reference**
- DuMouchel W (1999). “Bayesian data mining in large frequency tables…” *Drug Safety* / *Pharmacoepidemiology and Drug Safety* context. [1]

---

## 3. Drug / Event Name Alignment

### 3.1 Does the pipeline normalize drug names to canonical substances before computing contingency counts?
From the code you provided, **in-app** logic confirms that *both modes exist*:

- In `faers-mobi/app/view/signal_timeline.R`:
  - It explicitly documents two parquets:
    - `SIGNALS_DRUG_PATH = "data/signals.parquet"` (raw FAERS drug strings)
    - `SIGNALS_SUBSTANCE_PATH = "data/signals_substance.parquet"` (DiAna-rolled substances)
  - And provides a UI toggle `signals_mode` to select "drug" vs "substance".
  - It builds DiAna mappings for enrichment and search expansion (`diana_dict()`, `substance_to_drugs()`, etc.).

**Implication**
- The platform **does not enforce** substance rollup by default; it supports both:
  - Drug-level: each raw name becomes its own “drug” in the contingency, which absolutely can fragment counts and distort denominators.
  - Substance-level: uses the offline pipeline output `signals_substance.parquet`, which implies the ingestion pipeline performed rollup there.

**Where fragmentation occurs**
- When `signals_mode == "drug"`, `signals()` reads `data/signals.parquet` and all computations (aggregation to `pair_stats_full`) group by `.data$drug, .data$event` without further normalization in-app.
  - See `faers-mobi/app/view/signal_timeline.R` → `pair_stats_full()` grouping: `group_by(.data$drug, .data$event)`.

**Where normalization occurs (if you choose it)**
- When `signals_mode == "substance"`, the app reads `data/signals_substance.parquet` (already rolled up offline).
- Additionally, for label matching the app maps raw drug strings to substances using DiAna:
  - `.diana_substance()` and `.find_label_row()` in the same file.

### 3.2 Do we see event-name normalization?
In the code shown:
- Events are treated as MedDRA PT strings coming from parquet; no PT spelling normalization before signal counts (that would be upstream).
- There is spelling normalization only for *label matching* and *search* (`.normalize_spelling()`), not for deduplicating event PTs into a canonical PT.

**Answer for Q3**
- **Drug normalization prior to contingency counts is not guaranteed** in the default “drug-level” view; fragmentation is explicitly acknowledged and can inflate/deflate denominators.
- Canonical rollup exists only when you use the *substance parquet*, meaning normalization is handled in the offline pipeline (not shown here). The in-app code does not itself roll up names before computing counts; it only toggles which precomputed dataset it reads.

---

## 4. Fuzzy Search — Current State and Gaps (signal_timeline.R)

### 4.1 Is `agrep max.distance = 0.2` well-calibrated?
**Code reference**
- `faers-mobi/app/view/signal_timeline.R` → `.fuzzy_match_pairs(..., max_dist = 0.2)`
- Same in `aers-mobi/app/view/signal_timeline.R`.
- VAERS uses `.match_names(..., max_dist = 0.2)` in `vaers-mobi/app/view/signal_timeline.R`.

**Assessment**
- `agrep`’s `max.distance` is relative; `0.2` allows up to ~20% edits. For an 8–12 char medical token, that’s ~1–2 edits—reasonable for typos.
- But medical terms often have longer multiword PTs; since you run `agrep` against the *full string*, multiword edits behave inconsistently (spaces/punctuation). You partially mitigate this by:
  - Also allowing exact substring match
  - Applying a length-ratio guard: `candidate length <= query*2.5 + 3`

**Result in practice**
- Likely decent for brand/generic typos (“sertralin” → “sertraline”), but:
  - Too permissive on short-ish queries that are common substrings (“card”, “rash”, “pain”), where substring match already returns many hits and fuzzy adds noise.
  - Too strict for abbreviations clinicians type (e.g., “MI”, “AKI”, “SJS”), because of the `<5 chars` guard.

### 4.2 Guard against agrep on strings < 5 chars
**Code reference**
- `AGREP_MIN_LEN <- 5L` in both FAERS/AERS timeline `.fuzzy_match_pairs()` and VAERS `.match_names()`.

**Assessment**
- This is sensible for general English, but in medical search, **abbreviations are common**:
  - “MI”, “AF”, “AKI”, “SJS”, “DVT”, “PE”, “ICH”
- Your current implementation will fall back to substring match only, which might still work when the abbreviation appears, but many PTs won’t contain the abbreviation.

**Recommendation**
- Keep the guard for edit-distance, but add an abbreviation expansion dictionary (small curated map) for common safety terms.

### 4.3 Better packages?
- `stringdist` (distance metrics like Jaro-Winkler, cosine q-grams) can improve precision/recall vs base `agrep`.
- `stringi` for robust normalization/tokenization.
- `fuzzyjoin` if you need join semantics; here you mostly need fast lookup, so precomputed nearest-neighbor indexing might be better.

### 4.4 Concrete improvements (without flooding)
1) **Token-based matching for events**
   - Split query into tokens; match against tokens in PTs (or build an inverted index once per session).
2) **Use q-gram cosine distance for long PTs**
   - For medical terms, q-grams often outperform Levenshtein on multiword strings. Consider `stringdist::stringdistmatrix(method="cosine", q=2)` on a narrowed candidate set.
3) **Two-stage retrieval**
   - Stage 1: substring OR token overlap to get a candidate set (fast).
   - Stage 2: apply distance metric within that candidate set and take top-k.

---

## 5. Signal Pair Filtering — Relevance

### 5.1 What systematic false positives are likely missed?
Even with blacklist + class co-flags, common FAERS artefacts remain:

1) **Indication / disease spillover**
- Drugs used to treat a disease cause reports of the disease itself or complications (“metformin” + “diabetes mellitus”).
- You have a `treats` column computed in `.enrich_label_match()` (FAERS/AERS timeline), but it’s not used as a default suppression filter.
  - Code: `faers-mobi/app/view/signal_timeline.R` → `.enrich_label_match()` returns `treats`.

**Recommendation**
- Downrank or flag pairs where `treats == TRUE` (likely confounding by indication), rather than presenting as “novel high EB05”.

2) **Notoriety / stimulated reporting**
- Media events, lawsuits, Dear Healthcare Provider letters cause spikes.
- You have an “Emerging” flag and a Weber adjustment, but not a stimulated-reporting detector.

**Recommendation**
- Add a “spike score”: compare last 1–2 quarters vs historical baseline (e.g., Poisson GLR, or simple ratio with Bayesian smoothing).

3) **Duplicate reports / follow-ups**
- FAERS contains follow-up versions; pipelines usually deduplicate at case level (not shown here). If deduplication is incomplete, disproportionality inflates.

4) **Competition bias / masking**
- Known strong signals can mask others; not addressed by your current scoring.

### 5.2 Temporal biases beyond Weber effect
- **Seasonality** (vaccines, respiratory drugs)
- **Regulatory actions** / label changes
- **Coding changes** (MedDRA versioning)

**Recommendation**
- Show/compute stability measures:
  - quarters_flagged already exists; emphasize it more (and maybe require `observed_total >= X` too).
  - Add “time-to-first-signal” and “persistence” scores: fraction of quarters flagged after first signal.

### 5.3 Very low observed counts (n < 5)
In spontaneous reporting, tiny `a` counts can yield large EB05 if the prior is permissive, though EB05 is designed to be conservative.

**Recommendation**
- Add an explicit observed count filter or at least an “n_obs_total” display and default filter:
  - “exclude total observed across all quarters < 5” or “< 10” for the splash table
  - or a triage badge “low-count—unstable”

(Your DT currently defaults to `Quarters >= 3` and novelty/class filters; it does not filter by cumulative observed count in the shown code.)

---

## 6. Top 100 Signal Pairs (validation/sanity-check set)

I can’t generate **platform-specific** “expected top 100” ranked by your `adj_eb05` without the actual parquet contents and your exact schema fields (`drug`, `event`, `eb05`, `n_methods_flagged`, `adj_eb05`). I am not sure.

---

## 7. PICO DAG — Node Label Trimming (network_viz.R)

**Code reference**
- `pico-dag/app/R/network_viz.R`:
  - Root node uses full label: `label = dag_result$concept$name`
  - Relation nodes truncate: `stringr::str_trunc(..., 30)` and labs 25.

### Recommendation: clinically-safe trimming strategy
Use **rule-based** trimming (deterministic, auditable) rather than model-based, because:
- Clinical DAG nodes must remain reviewable; LLM/model abbreviations can hide meaning or introduce drift.

**Suggested approach**
1) Normalize whitespace and strip parenthetical boilerplate:
   - Remove trailing semantic-type parentheses like `"(...)"` when it’s generic.
2) Remove generic UMLS filler phrases:
   - Leading: “Disorder characterized by”, “Disease or Syndrome”, “Finding of”, “Structure of”
3) Keep key head noun and qualifiers:
   - Prefer to preserve: laterality, acuity, anatomical site, severity, organism, drug class

**Implement as a reusable helper**
Description: Create a label cleaner that applies deterministic rules and then truncates with an informative suffix.
```r
# pico-dag/app/R/network_viz_label.R
# Deterministic node label cleaner for visNetwork nodes
clean_node_label <- function(x, max_chars = 34) {
  # Defensive: handle NA
  if (is.na(x) || !nzchar(x)) return("")

  y <- x

  # Collapse whitespace
  y <- gsub("\\s+", " ", y)

  # Drop very generic UMLS scaffolding phrases
  y <- sub("^Disorder characterized by\\s+", "", y, ignore.case = TRUE)
  y <- sub("^Disease or Syndrome\\s*:?\\s*", "", y, ignore.case = TRUE)
  y <- sub("^Finding of\\s+", "", y, ignore.case = TRUE)

  # Drop trailing parenthetical qualifiers when they are generic
  # (keep parentheses if they contain critical abbreviations like "MI", "AKI")
  y <- sub("\\s*\\((disease|disorder|finding|procedure)\\)\\s*$", "", y, ignore.case = TRUE)

  # Final truncation
  stringr::str_trunc(y, width = max_chars, side = "right")
}
```
Then replace `stringr::str_trunc(data$related_name[i], 30)` with `clean_node_label(data$related_name[i])`.

---

## 8. PICO DAG — Interactive Nodes as Search Terms

### Goal
Click a node in the visNetwork graph → set that node’s CUI as the new root → rerun `walk_concept_dag()` and update the graph/tables.

### Code sketch (Shiny + visNetwork)
**How to capture click**
visNetwork sends input `input$<outputId>_selected` (selected node id) or events via `visEvents()`.

Description: Add click event handling that updates a reactive root CUI and recomputes the DAG.
```r
# In pico-dag/app/app.R server section (sketch)

server <- function(input, output, session) {

  rv <- reactiveValues(
    root_cui   = NULL,
    dag_result = NULL
  )

  # 1) Render the network with events enabled
  output$dag_network <- renderVisNetwork({
    req(rv$dag_result)

    build_dag_network(rv$dag_result) |>
      visNetwork::visEvents(
        selectNode = "function(nodes) { Shiny.setInputValue('dag_node_click', nodes.nodes[0], {priority: 'event'}); }"
      )
  })

  # 2) When the user clicks a node, use its id as the new root CUI
  observeEvent(input$dag_node_click, {
    clicked_id <- input$dag_node_click
    req(clicked_id)

    # Optional: guard so we only re-root on valid CUIs (C + digits)
    if (!grepl("^C\\d+$", clicked_id)) return()

    # Update the Population selection UI as well (so the left panel reflects it)
    rv$root_cui <- clicked_id
    updateTextInput(session, "pop_term", value = clicked_id)  # or keep term unchanged
    # If you have a selectInput for CUI, you could update that instead.

    # Re-walk the DAG from the clicked node
    withProgress(message = "Re-rooting DAG...", {
      rv$dag_result <- walk_concept_dag(
        clicked_id,
        progress = \(msg) setProgress(message = msg)
      )
    })
  })

  # 3) Initial walk still triggered by the existing "Walk DAG" button
  observeEvent(input$pop_walk, {
    req(rv$pop_cui_select)
    rv$root_cui <- input$pop_cui_select

    withProgress(message = "Walking UMLS concept graph...", {
      rv$dag_result <- walk_concept_dag(
        rv$root_cui,
        progress = \(msg) setProgress(message = msg)
      )
    })
  })

}
```

This approach:
- Captures click with `visEvents(selectNode=...)`
- Writes `input$dag_node_click`
- Triggers recomputation by updating `rv$dag_result`

---

## References

[1] DuMouchel W. “Bayesian data mining in large frequency tables, with an application to the FDA spontaneous reporting system.” *The American Statistician* / *Pharmacoepidemiology and Drug Safety* (1999).