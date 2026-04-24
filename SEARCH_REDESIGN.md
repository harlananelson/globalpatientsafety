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

### 8. Downloadable Reports (Monetization — Phase 7)

#### Concept

Users can generate a professional PDF report from their current search/analysis
session. The report is rendered server-side with Typst (bundled with Quarto) and
returned as a downloadable file. Free users see the interactive app; reports
cost a micropayment.

#### Report Content

A report captures the user's session state — their search, filters, selected
pairs, and any temporal/stratified analysis — into a self-contained document:

```
┌──────────────────────────────────────────────────┐
│  Global Patient Safety — Signal Report           │
│  Generated: 2026-04-24                           │
│                                                  │
│  Search: "ischaemic stroke"                      │
│  Filters: ATC = Antithrombotic agents            │
│  Period: 2023Q1–2024Q4 vs 2021Q1–2022Q4          │
│                                                  │
│  1. Signal Summary Table                         │
│     (drug, event, EB05, trend, novelty, class)   │
│                                                  │
│  2. Caterpillar Plots                            │
│     Per selected (drug, event) pair              │
│                                                  │
│  3. Temporal Trend Analysis                      │
│     Quarter-over-quarter EB05 with slope          │
│     Period comparison (rate ratios)              │
│                                                  │
│  4. Class-Level Analysis (if stratified)         │
│     Class rate vs historical baseline            │
│     Within-class disproportionality              │
│                                                  │
│  5. FDA Label Cross-Reference                    │
│     Novel vs known classification per pair       │
│     Label sections matched                       │
│                                                  │
│  6. Methodology & Data Provenance                │
│     Signal detection methods, data source,       │
│     date range, filters applied, caveats         │
│                                                  │
│  Disclaimer: Statistical signals, not causation. │
└──────────────────────────────────────────────────┘
```

#### Typst Rendering

Quarto bundles Typst — no LaTeX installation needed on the VPS. The report
template lives in the app:

```
faers-mobi/
├── app/
│   └── logic/
│       └── report_generator.R     # Builds .qmd from session state
├── templates/
│   └── signal-report.qmd          # Typst template with parameterized content
│   └── signal-report.typ          # Custom Typst template for branding
```

```r
# report_generator.R
generate_report <- function(search_state, output_path) {
  # 1. Build a parameterized QMD from the session state
  params <- list(
    search_query = search_state$query,
    filters = search_state$filters,
    pairs = search_state$selected_pairs,   # tibble of (drug, event) rows
    signals_data = search_state$pair_stats, # enriched signal data
    trend_data = search_state$trends,
    class_data = search_state$class_signals
  )

  # 2. Render with Quarto → Typst → PDF
  quarto::quarto_render(
    "templates/signal-report.qmd",
    output_file = output_path,
    execute_params = params
  )
}
```

```yaml
# templates/signal-report.qmd front matter
---
title: "Signal Report"
subtitle: "`r params$search_query`"
author: "globalpatientsafety.com"
date: today
format:
  typst:
    papersize: us-letter
    mainfont: "Linux Libertine"
    template: signal-report.typ
params:
  search_query: ""
  filters: !expr list()
  pairs: !expr tibble::tibble()
  signals_data: !expr tibble::tibble()
  trend_data: !expr tibble::tibble()
  class_data: !expr tibble::tibble()
---
```

#### UI

```r
# In signal_timeline.R ui():
downloadButton(ns("download_report"), "Generate Report (PDF)",
               class = "btn-success mt-3",
               icon = icon("file-pdf"))

# In server():
output$download_report <- downloadHandler(
  filename = function() {
    paste0("signal-report-", Sys.Date(), ".pdf")
  },
  content = function(file) {
    # Check payment status before rendering
    if (!user_has_credit(session)) {
      showModal(modalDialog(
        title = "Report Generation",
        "PDF reports require a one-time micropayment of $X.XX.",
        footer = tagList(
          actionButton(ns("pay_report"), "Pay & Generate", class = "btn-primary"),
          modalButton("Cancel")
        )
      ))
      return()
    }
    generate_report(current_search_state(), file)
  }
)
```

### 9. API & Monetization (Phase 8)

#### Revenue Model

Three tiers:

| Tier | Audience | Access | Price |
|------|----------|--------|-------|
| **Free** | Researchers, public | Interactive app, basic search, top signals | $0 |
| **Pay-per-report** | Occasional users, consultants | PDF report generation | $2–5 per report |
| **API access** | AI agents, programmatic users | REST API with rate limiting | $0.01–0.05 per query |
| **Enterprise subscription** | Pharma companies | Unlimited API, bulk export, custom strata, SLA | $500–2000/month |

#### REST API

Plumber API alongside the Shiny app, or a separate service on the same VPS.
The API exposes the same signal data the app uses, structured for programmatic
consumption.

**Endpoints:**

```
GET  /api/v1/signals/search?q=ischaemic+stroke&fuzzy=true
     → Returns matching (drug, event) pairs with signal metrics

GET  /api/v1/signals/drug/{drug_name}
     → All signals for a specific drug

GET  /api/v1/signals/event/{event_name}
     → All drugs flagged for a specific event

GET  /api/v1/signals/trend?drug=semaglutide&event=Pancreatitis&quarters=8
     → Temporal trend data for a specific pair

GET  /api/v1/signals/class/{atc_class}
     → Class-level temporal analysis

GET  /api/v1/signals/class/{atc_class}/temporal?baseline=2020Q1-2022Q4&current=2023Q1-2024Q4
     → Class-wide temporal comparison (the masking-breaker)

GET  /api/v1/signals/emerging?days=90
     → New signals in the last N days (splash page data)

POST /api/v1/reports/generate
     → Generate and return a PDF report for a set of search parameters
     Body: { "query": "...", "filters": {...}, "pairs": [...] }
     Returns: PDF binary or a job ID for async generation

GET  /api/v1/meta/events
     → All available event names (for autocomplete / fuzzy matching)

GET  /api/v1/meta/drugs
     → All available drug names

GET  /api/v1/meta/classes
     → ATC classes and MedDRA SOCs available for stratification
```

**Response format:**

```json
{
  "query": "ischaemic stroke",
  "fuzzy_matched": true,
  "matched_event": "Ischaemic stroke",
  "results": [
    {
      "drug": "ozanimod",
      "event": "Ischaemic stroke",
      "peak_eb05": 992.3,
      "adj_eb05": 891.1,
      "n_methods_flagged": 4,
      "quarters_flagged": 3,
      "first_signal": "2019Q4",
      "latest_signal": "2020Q2",
      "trend": "Declining",
      "novel": true,
      "substance": "ozanimod",
      "atc_class": "Immunosuppressants"
    }
  ],
  "total_results": 153,
  "api_credits_remaining": 487
}
```

#### Implementation Options

**Option A: Plumber API (R-native)**

Runs alongside Shiny on the same VPS. Shares the same parquet data and R
environment. Simplest to implement — same language, same data access code.

```r
# api/plumber.R
library(plumber)
library(arrow)
library(dplyr)

ds <- open_dataset("data/signals.parquet")

#* Search signals by drug or event name
#* @param q Search query
#* @param fuzzy Enable fuzzy matching (default true)
#* @get /api/v1/signals/search
function(q, fuzzy = TRUE) {
  # Reuse the same fuzzy_match_events() from signal_timeline.R
  matches <- fuzzy_match_events(q, all_events, max_dist = 0.2)
  ds %>%
    filter(outcome_name %in% matches | rxnorm_name %in% drug_matches) %>%
    filter(n_methods_flagged >= 2) %>%
    group_by(rxnorm_name, outcome_name) %>%
    summarise(...) %>%
    collect()
}
```

**Option B: FastAPI (Python) with Arrow**

Separate service, reads the same parquet files. Better async performance
and ecosystem for payment integration (Stripe SDK is Python-first).

**Recommendation:** Start with Plumber (Option A) — the fuzzy search,
signal computation, and novelty logic already exist in R. Add a thin
Python proxy later only if performance requires it.

#### AI Agent Integration

The API is designed for AI consumption. An LLM with tool use can:

1. Search for signals related to a drug or condition
2. Pull temporal trends to assess whether a signal is growing
3. Compare drug classes to identify class-wide effects
4. Generate a report summarizing findings

**MCP server potential:** The API endpoints map naturally to an MCP tool
server. A future `mcp-globalpatientsafety` server would let Claude or other
AI assistants query signal data directly during conversations.

```json
{
  "tools": [
    {
      "name": "search_signals",
      "description": "Search pharmacovigilance signals by drug or adverse event",
      "parameters": {
        "query": "string — drug name, event name, or general search term",
        "fuzzy": "boolean — enable fuzzy matching for spelling variants"
      }
    },
    {
      "name": "get_signal_trend",
      "description": "Get temporal trend for a specific drug-event pair",
      "parameters": {
        "drug": "string",
        "event": "string",
        "quarters": "integer — number of quarters to include"
      }
    },
    {
      "name": "compare_class_temporal",
      "description": "Compare a drug class's current adverse event rate to historical baseline",
      "parameters": {
        "atc_class": "string",
        "event": "string (optional)",
        "baseline_period": "string — e.g. 2020Q1-2022Q4",
        "current_period": "string — e.g. 2023Q1-2024Q4"
      }
    }
  ]
}
```

#### Payment Integration

**Stripe** for all payment tiers:

| Component | Stripe Product |
|-----------|---------------|
| Micropayment (reports) | Stripe Checkout one-time payment |
| API credits | Stripe metered billing (usage-based) |
| Enterprise subscription | Stripe recurring subscription |

**Authentication flow:**

```
Free user → no auth required (rate-limited by IP)
Report buyer → Stripe Checkout → one-time token → download
API user → API key (issued after Stripe subscription)
Enterprise → API key + higher rate limits + SLA dashboard
```

**Rate limiting:**

| Tier | Rate Limit |
|------|-----------|
| Free (app) | No limit (interactive only) |
| Free (API, if offered) | 10 queries/day |
| API paid | 1000 queries/day per $10/month |
| Enterprise | Unlimited (fair use) |

#### Deployment Architecture (Phase 8)

```
VPS (Hetzner)
├── nginx (reverse proxy, SSL)
│   ├── faers.mobi → Shiny Server (port 3838)
│   ├── api.globalpatientsafety.com → Plumber (port 8000)
│   └── globalpatientsafety.com → Shiny Server (portal)
├── Shiny Server
│   ├── faers-mobi/
│   └── globalpatientsafety/
├── Plumber API
│   └── api/ (reads same data/signals.parquet)
└── data/
    ├── signals.parquet
    ├── contingency/ (for stratified analysis)
    └── fda_labels.parquet
```

### 10. Files to Modify

| File | Change | Phase |
|------|--------|-------|
| `faers-mobi/app/view/signal_timeline.R` | Search UI, `pair_stats()` refactor, priority tiers | 1-2 |
| `faers-mobi/app/view/signal_timeline.R` | Remove `head(2000)`, add `fuzzy_match_events()` | 1 |
| `faers-mobi/app/view/signal_timeline.R` | Trend column (slope, arrows), period comparison UI | 3 |
| `faers-mobi/app/view/signal_timeline.R` | SOC/ATC filter dropdowns, post-hoc stratification | 4 |
| `signal-compute/R/compute_quarterly.R` | Stratified disproportionality output | 5 |
| `signal-compute/scripts/deploy_to_vps.sh` | Ship contingency parquet if using on-the-fly approach | 5-6 |
| `faers-mobi/app/logic/report_generator.R` | **New** — builds parameterized QMD from session state | 7 |
| `faers-mobi/templates/signal-report.qmd` | **New** — Typst report template | 7 |
| `faers-mobi/templates/signal-report.typ` | **New** — Custom Typst branding template | 7 |
| `faers-mobi/api/plumber.R` | **New** — REST API endpoints | 8 |
| `faers-mobi/api/auth.R` | **New** — API key validation + Stripe integration | 8 |
| VPS nginx config | Add `api.globalpatientsafety.com` proxy | 8 |

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
7. **Phase 7:** Downloadable reports. Typst-rendered PDF from session state
   (search, filters, selected pairs, trends, class analysis). Micropayment
   via Stripe Checkout before download.
8. **Phase 8:** REST API (Plumber) + monetization. API keys, metered billing,
   enterprise subscriptions. MCP server wrapper for AI agent integration.

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

**Reports (Phase 7):**
- PDF renders successfully from a search session with filters and selected pairs
- Report includes signal table, caterpillar plots, trend data, and methodology section
- Typst rendering completes in < 30 seconds on the VPS
- Stripe Checkout flow works end-to-end (test mode)
- Download link expires after 24 hours

**API & Monetization (Phase 8):**
- `/api/v1/signals/search?q=ischaemic+stroke` returns correct JSON
- Fuzzy matching works identically to the app
- API key authentication rejects invalid keys
- Rate limiting enforced per tier
- Stripe metered billing records usage correctly
- MCP tool server wrapping the API allows AI agents to search signals
