# faers.mobi Signal Search Redesign

## Problem

The signal timeline datatable pre-filters to the **top 2000** (drug, event) pairs
by peak EB05 (`signal_timeline.R` ~line 400). This excludes clinically important
signals like "Ischaemic stroke" (153 drug pairs, best rank #5078 of 264,791).
Users searching for a specific event get no results unless it happens to rank
in the top 2000.

Additionally, DT's client-side column search is literal — "ischemic" won't match
MedDRA's British spelling "ischaemic".

## Current Architecture

```
Session start
  → open_dataset("data/signals.parquet")     # 305MB, 2.2M rows, lazy
  → pair_stats() reactive:
      filter(n_methods_flagged >= 2)
      group_by(rxnorm_name, outcome_name)     # ~265k pairs
      summarise(peak_eb05, quarters, etc.)
      head(2000)                               ← bottleneck
      collect()
      + blacklist removal
      + DiAna substance resolution
      + FDA label novelty check (per-row)
      + Weber-effect adjustment
      + ATC class co-flags
      + triage/watchlist joins
  → DT datatable with client-side column filters
```

The `head(2000)` exists because (a) running the per-row label string match
over 265k pairs blocks the page for minutes, and (b) DT can't handle 265k
rows client-side.

## Proposed Architecture

### 1. Server-Side Search

Replace the upfront `head(2000)` with on-demand search against the full parquet.

```
User types search term
  → server fuzzy-matches against outcome_name and rxnorm_name
  → filters parquet to matching pairs (typically 50-500)
  → runs the existing enrichment pipeline (novelty, Weber, ATC, triage)
  → returns to DT datatable
```

**Search implementation:**
- Use `.normalize_spelling()` (already exists) on both query and target
- `agrep()` for fuzzy matching (handles typos, ischemic→ischaemic)
- Also search `rxnorm_name` so users can search by drug
- Debounce input (500ms) to avoid hammering the parquet on every keystroke

**Key change to `pair_stats()`:**
```r
# Before: hardcoded top 2000
pair_stats <- reactive({
  ds <- signals()
  ps <- ds %>%
    filter(n_methods_flagged >= 2) %>%
    group_by(...) %>% summarise(...) %>%
    head(2000) %>% collect()          # ← remove this
  ...
})

# After: accepts search term OR returns default splash
pair_stats <- reactive({
  ds <- signals()
  query <- input$search_query

  if (nzchar(query)) {
    # Server-side fuzzy search against full parquet
    # 1. Collect distinct event/drug names (small: ~15k events, ~8k drugs)
    # 2. Fuzzy match locally with agrep + normalize_spelling
    # 3. Filter parquet to matched pairs only
    # 4. Enrich (novelty, Weber, etc.)
  } else {
    # Default splash: curated priority list (see section 2)
  }
})
```

### 2. Default Splash Page — Signal Priority Ranking

When no search term is entered, show signals ranked by **investigative priority**:
signals the FDA hasn't acted on yet, favoring recent emergence.

**Priority tiers (display order):**

| Tier | Label | Definition | Color |
|------|-------|-----------|-------|
| 1 | **Emerging** | First flagged in last 2 quarters, novel (not on label) | Red |
| 2 | **Novel** | Flagged ≥3 quarters, novel, not yet triaged | Orange |
| 3 | **Under review** | Triaged as "investigating" but not yet labeled | Yellow |
| 4 | **Established** | Known signals (on label) or triaged as "expected" | Grey |

**Ranking within each tier:** Adj EB05 descending (Weber-adjusted).

**Implementation:**

```r
# Compute priority_tier from existing columns:
ps <- ps %>% mutate(
  priority = case_when(
    # Tier 1: brand new + novel
    novel == TRUE & first_signal >= two_quarters_ago ~ "Emerging",
    # Tier 2: persistent novel signal
    novel == TRUE & quarters_flagged >= 3 & triage == "" ~ "Novel",
    # Tier 3: under active investigation
    triage %in% c("investigating", "under review") ~ "Under review",
    # Tier 4: everything else
    TRUE ~ "Established"
  ),
  priority_rank = case_when(
    priority == "Emerging"     ~ 1L,
    priority == "Novel"        ~ 2L,
    priority == "Under review" ~ 3L,
    TRUE                       ~ 4L
  )
)
```

**Splash size:** Show top ~200 across all tiers (enough to fill the page,
fast enough for label matching). User scrolls or searches for more.

### 3. Fuzzy Search Details

The app already has `.normalize_spelling()` which handles British→American
medical terms. Extend this for the search box:

```r
fuzzy_match_events <- function(query, event_names, max_dist = 0.2) {
  q_norm <- .normalize_spelling(tolower(query))
  e_norm <- .normalize_spelling(tolower(event_names))

  # Exact substring match first (fast)
  exact <- grepl(q_norm, e_norm, fixed = TRUE)

  # Fuzzy match for typos (agrep with max.distance)
  fuzzy <- agrep(q_norm, e_norm, max.distance = max_dist, value = FALSE)

  unique(c(which(exact), fuzzy))
}
```

This handles:
- "ischemic stroke" → matches "Ischaemic stroke" (normalize_spelling)
- "ischeamic" → matches "Ischaemic" (agrep fuzzy, edit distance)
- "stroke" → matches all stroke-related PTs (substring)

### 4. UI Changes

Replace the current DT column filter header for Event with a prominent
search box above the table:

```r
# In ui():
fluidRow(
  column(8,
    textInput(ns("search_query"), NULL,
              placeholder = "Search any drug or event (e.g. ischemic stroke, semaglutide)...")
  ),
  column(4,
    actionButton(ns("search_btn"), "Search", class = "btn-primary"),
    actionButton(ns("show_splash"), "Show Priority Signals", class = "btn-outline-secondary")
  )
)
```

Keep the DT column filters for further refinement (Novel, Quarters, Class, etc.)
after the server-side search narrows the results.

### 5. Performance Considerations

**Why this is faster than the current approach at scale:**
- Arrow parquet pushdown: `filter(outcome_name %in% matched_events)` runs
  in Arrow, not R — scans only relevant row groups
- Label matching runs on ~50-500 pairs (search result), not 2000
- Splash page is cached per session (invalidated only on triage/watchlist change)

**Potential bottleneck:** Building the distinct event/drug name list for fuzzy
matching. Solution: cache it once at session start (~15k distinct events,
~8k drugs from the full parquet). This is a one-time 2-3 second cost.

```r
# Cache at session start (outside pair_stats)
all_events <- reactive({
  ds <- signals()
  ds %>% distinct(outcome_name) %>% collect() %>% pull(outcome_name)
})
all_drugs <- reactive({
  ds <- signals()
  ds %>% distinct(rxnorm_name) %>% collect() %>% pull(rxnorm_name)
})
```

### 6. Temporal Trend Analysis

#### The Question: Is This Signal Getting Stronger?

Current signals are computed over all time (4-quarter rolling window pooled).
This answers "is there a signal?" but not "is it increasing?" A signal that
was flat for 10 years is very different from one that doubled last quarter.

#### Period-over-Period Comparison

Compare the most recent window against prior windows to detect acceleration:

```r
# For a given (drug, event) pair, compute trend metrics across quarters
trend <- ds %>%
  filter(rxnorm_name == drug, outcome_name == event) %>%
  arrange(quarter) %>%
  collect() %>%
  mutate(
    # Quarter-over-quarter change in EWMA-smoothed EB05
    eb05_delta = ewma_eb05 - lag(ewma_eb05),
    # Percentage change
    eb05_pct_change = eb05_delta / lag(ewma_eb05) * 100,
    # Rolling 4-quarter slope (linear trend)
    eb05_slope = slider::slide_dbl(ewma_eb05, ~ coef(lm(.x ~ seq_along(.x)))[2], .before = 3)
  )
```

**Trend classification:**

| Category | Definition | Display |
|----------|-----------|---------|
| **Accelerating** | EB05 slope > 0 over last 4 quarters AND latest > prior peak | Red arrow up |
| **Rising** | EB05 slope > 0 over last 4 quarters | Orange arrow up |
| **Stable** | Slope ≈ 0 (within ±10% of mean) | Grey dash |
| **Declining** | EB05 slope < 0 over last 4 quarters | Green arrow down |
| **New** | Fewer than 4 quarters of data | Blue "NEW" badge |

**Add to the datatable:**
- `Trend` column with arrow icons
- `Recent EB05` (latest quarter) vs `Prior EB05` (4 quarters ago) for quick comparison
- Sortable — users can find the fastest-growing signals

**Add to the splash page priority ranking:**
Accelerating novel signals should rank above stable novel signals. Modify the
priority tier:

```r
priority = case_when(
  novel & trend == "Accelerating" ~ "Emerging + Accelerating",  # top priority
  novel & first_signal >= two_quarters_ago ~ "Emerging",
  novel & trend %in% c("Accelerating", "Rising") ~ "Novel + Rising",
  novel & quarters_flagged >= 3 ~ "Novel",
  ...
)
```

#### User-Selectable Time Windows

Allow the user to compare two periods directly:

```r
# UI: two date-range pickers or quarter selectors
# "Compare: [2024Q1-2024Q4] vs [2023Q1-2023Q4]"
#
# Server: compute signal stats for each window independently,
# then join and show delta columns
period_a <- ds %>% filter(quarter %in% quarters_a) %>% ...
period_b <- ds %>% filter(quarter %in% quarters_b) %>% ...
comparison <- inner_join(period_a, period_b, by = c("rxnorm_name", "outcome_name"),
                         suffix = c("_recent", "_prior")) %>%
  mutate(
    eb05_change = peak_eb05_recent - peak_eb05_prior,
    eb05_ratio = peak_eb05_recent / peak_eb05_prior,
    new_in_recent = is.na(peak_eb05_prior) & !is.na(peak_eb05_recent)
  )
```

This answers: "What signals appeared or strengthened in the last year that
weren't there before?" — exactly the question for finding signals before
the FDA acts.

### 7. Stratified Analysis (Segmentation)

#### Why Segmentation Matters

Pooling all drugs and events together can **mask** real signals through
Simpson's paradox. A drug-event pair might show no disproportionality overall
because one large, safe drug class dilutes the background rate. Stratifying
by body system or drug class reveals signals hidden in the aggregate.

Conversely, stratification with small cell sizes inflates false positives.
The temporal dimension mitigates this: a stratified signal that persists
across quarters is more credible than one that appears once.

#### The Class-Wide Masking Problem (Critical)

There is a deeper failure mode that within-class disproportionality **cannot
detect at all**: when every drug in a class develops the same adverse event.

**Example:** Suppose a class of vaccines all cause myocarditis starting in
2021Q3. Within-class disproportionality compares each vaccine against the
class background rate. But the background rate IS the problem — every vaccine
has the elevated myocarditis rate, so none is disproportionate relative to
the others. The signal is perfectly masked. No amount of cross-sectional
stratification will find it.

**The temporal comparison breaks the mask.** Comparing the class's current
rate to its own historical baseline reveals the change:

```
Within-class cross-sectional (2022Q1):
  Vaccine A → myocarditis: EB05 = 0.9  (not flagged — class rate is high)
  Vaccine B → myocarditis: EB05 = 1.1  (not flagged)
  Vaccine C → myocarditis: EB05 = 0.8  (not flagged)
  → No signal detected. Every vaccine looks "normal" for the class.

Temporal comparison (2022Q1 vs 2020Q4, same class):
  Class "vaccines" → myocarditis: rate ratio = 8.3x  (SIGNAL)
  → The entire class shifted. Something changed.
```

This means the temporal analysis is not just a refinement of stratification —
it is the **only way** to detect class-wide effects. The architecture must
support comparing a stratum against its own past, not just against other
drugs in the same period.

**Implementation: class-level temporal signals**

```r
# For each (ATC class, event, quarter), compute the class-aggregate rate
# and compare to the class's historical baseline
class_temporal <- contingency %>%
  # Tag each drug with its ATC class
  left_join(atc, by = "rxnorm_name") %>%
  # Aggregate within class: total reports of this event across all drugs in class
  group_by(atc_class4, outcome_name, quarter) %>%
  summarise(
    class_observed = sum(observed),
    class_total = sum(total_reports),
    .groups = "drop"
  ) %>%
  # Compute rate per quarter
  mutate(class_rate = class_observed / class_total) %>%
  # Compare to historical median rate for this (class, event)
  group_by(atc_class4, outcome_name) %>%
  mutate(
    historical_median_rate = median(class_rate[quarter < cutoff_quarter]),
    rate_ratio = class_rate / historical_median_rate,
    is_class_signal = rate_ratio > 2.0 & class_observed >= 5
  ) %>%
  ungroup()
```

**This analysis answers three distinct questions:**

| Question | Method | What it detects |
|----------|--------|----------------|
| Is this drug worse than others? | Cross-sectional disproportionality (current GPS) | Drug-specific effects |
| Is this drug worse than others in its class? | Within-class disproportionality (Phase 5 Approach B) | Drug-specific effects masked by inter-class variation |
| Did something change for this entire class? | Temporal class-rate comparison | **Class-wide effects invisible to any cross-sectional method** |

All three are needed. The third is the one that current pharmacovigilance
tools typically miss.

#### Segmentation Dimensions

**By MedDRA body system (SOC/HLGT/HLT):**

The app already loads `meddra_hierarchy.parquet` which maps PT → HLT → HLGT → SOC.
Use this to let users focus on a body system:

```r
# User selects SOC = "Nervous system disorders"
# Filter events to PTs under that SOC
nervous_pts <- meddra %>%
  filter(soc == "Nervous system disorders") %>%
  pull(pt)

# Recompute disproportionality within this stratum:
# - Numerator: reports of (drug, PT in nervous system)
# - Denominator: all reports of (drug, any PT in nervous system)
# This changes the expected count and can reveal masked signals
```

**By ATC drug class:**

The app already has `atc_classes.parquet` and computes `class_co_flags`.
Extend to allow users to restrict analysis to a drug class:

```r
# User selects ATC class = "Antithrombotic agents"
# Show only drugs in that class
# Background rate is computed within-class, not across all drugs
# This reveals signals specific to one drug vs its class
```

**By time period (critical for masking mitigation):**

When you stratify by body system AND look at trends over time, you can
distinguish:
- A signal that's real but masked in the aggregate (appears when stratified)
- A signal that's artifactual from small numbers (appears once, doesn't persist)
- A class effect vs a drug-specific effect (compare within-class trend to
  across-class trend)

#### Stratified Signal Computation

Two approaches, in order of complexity:

**Approach A: Post-hoc filtering (Phase 4)**

Filter the existing `signals.parquet` by MedDRA SOC or ATC class. This
doesn't recompute disproportionality — it just narrows the view. Fast,
no pipeline changes needed. Useful for exploration but doesn't address
the masking problem directly.

```r
# Filter pair_stats to a SOC
pair_stats_filtered <- pair_stats() %>%
  filter(outcome_name %in% pts_in_selected_soc)
```

**Approach B: Stratified disproportionality (Phase 5)**

Recompute expected counts within strata. This is the proper solution to
masking: the "expected" count in the GPS model is based on the marginal
rates within the stratum, not across all drugs/events.

This requires changes to `signal-compute`, not just the app:

```r
# In compute_quarterly.R, add stratification:
# For each (SOC, quarter):
#   subset contingency to PTs in that SOC
#   recompute observed/expected within-SOC
#   run detect_all_methods on the within-SOC table
#
# Output: signals_faers_stratified_v<date>.parquet
# Additional columns: stratum_type, stratum_value
```

The stratified parquet would be larger (~5-10x) but Arrow handles this
efficiently with row-group filtering.

**Approach C: On-the-fly stratified computation (Phase 5 alternative)**

Instead of precomputing all strata, compute disproportionality on the fly
for the user's selected stratum. This uses `safetysignal` directly in the
app — slower (seconds per query) but no pipeline changes and no storage
multiplication.

```r
# In faers-mobi, load the raw contingency (not just signals)
contingency <- open_dataset("data/contingency/")

# When user selects a stratum:
stratum_data <- contingency %>%
  filter(outcome_name %in% pts_in_soc, quarter %in% selected_quarters) %>%
  collect()

# Run safetysignal on the stratum
result <- safetysignal::detect_all_methods(
  stratum_data,
  methods = c("gps", "prr", "ror", "ic"),
  min_count = 3
)
```

This requires shipping the contingency parquet to the VPS alongside
signals.parquet (~2-3 GB for all quarters).

#### UI for Segmentation

```r
fluidRow(
  column(4,
    selectInput(ns("soc_filter"), "Body System (MedDRA SOC)",
                choices = c("All" = "", sort(unique(meddra$soc))),
                selected = "")
  ),
  column(4,
    selectInput(ns("atc_filter"), "Drug Class (ATC Level 4)",
                choices = c("All" = "", sort(unique(atc$atc_class4))),
                selected = "")
  ),
  column(4,
    selectInput(ns("time_compare"), "Time Comparison",
                choices = c("All time", "Last 4 quarters vs prior 4",
                            "Last 2 quarters vs prior 2", "Custom..."),
                selected = "All time")
  )
)
```

### 8. Files to Modify

| File | Change | Phase |
|------|--------|-------|
| `app/view/signal_timeline.R` | Search UI, `pair_stats()` refactor, priority tiers | 1-2 |
| `app/view/signal_timeline.R` | Remove `head(2000)`, add `fuzzy_match_events()` | 1 |
| `app/view/signal_timeline.R` | Trend column (slope, arrows), period comparison UI | 3 |
| `app/view/signal_timeline.R` | SOC/ATC filter dropdowns, post-hoc stratification | 4 |
| `signal-compute/R/compute_quarterly.R` | Stratified disproportionality output | 5 |
| `signal-compute/scripts/deploy_to_vps.sh` | Ship contingency parquet if using on-the-fly approach | 5 |

### 9. Migration Path

1. **Phase 1:** Add search box + server-side fuzzy search. Keep `head(2000)` as
   the splash default. This is additive — doesn't break existing behavior.
2. **Phase 2:** Replace `head(2000)` splash with priority-ranked default view.
   Requires the priority tier logic and a smaller default set (~200).
3. **Phase 3:** Temporal trend analysis. Add trend classification (Accelerating /
   Rising / Stable / Declining / New) per pair. Trend column in DT. Period-over-period
   comparison UI. Integrate trend into splash priority ranking.
4. **Phase 4:** Post-hoc segmentation. MedDRA SOC and ATC class filter dropdowns.
   Filters the existing signal results — doesn't recompute disproportionality.
   Also: MedDRA hierarchy expansion for search ("stroke" matches all stroke PTs).
5. **Phase 5:** Stratified disproportionality. Recompute expected counts within
   strata (SOC or ATC class) to unmask Simpson's paradox signals. Either
   precompute in signal-compute (larger parquet) or compute on-the-fly in the
   app (requires shipping contingency data to VPS).
6. **Phase 6:** Class-level temporal signals. Aggregate reporting rates at the
   ATC class level per quarter, compare to historical baseline. Detects class-wide
   effects that are invisible to any cross-sectional disproportionality method
   (every drug in the class has the same problem, so none is disproportionate
   relative to the others). This is the "did something change for this entire
   class?" question — requires contingency data with total report counts.

### 10. Validation

After implementation, verify:

**Search (Phase 1):**
- "ischemic stroke" returns results (fuzzy → "Ischaemic stroke")
- "semaglutide" returns all semaglutide pairs
- Caterpillar plot still works when clicking a search result
- Page load time < 5 seconds

**Splash (Phase 2):**
- Default view shows emerging/novel signals first
- Accelerating novel signals rank above stable novel signals

**Trends (Phase 3):**
- Trend arrows are directionally correct against visual caterpillar plots
- Period comparison shows signals that appeared in recent window but not prior
- "New in recent" flag correctly identifies first-time signals

**Segmentation (Phase 4-5):**
- Filtering by SOC = "Nervous system disorders" shows only neuro PTs
- Filtering by ATC = "Antithrombotic agents" shows only anticoagulant/antiplatelet drugs
- Stratified analysis reveals signals hidden in aggregate (test with known masked cases)
- Temporal persistence filter removes single-quarter stratified artifacts
- Cross-stratum comparison: same (drug, event) pair shows different EB05 within-SOC
  vs pooled, confirming masking was present

**Class-wide temporal signals (Phase 6):**
- Known class-wide effect (e.g., fluoroquinolones + tendon rupture) detected by
  class-level temporal comparison even when no single drug is disproportionate within-class
- Class rate ratio flags quarters where the entire class shifted
- False positive rate: class signals that appear in one quarter but not adjacent quarters
  should be flagged as unstable
