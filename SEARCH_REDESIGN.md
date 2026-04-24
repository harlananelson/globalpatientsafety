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

### 6. Files to Modify

| File | Change |
|------|--------|
| `app/view/signal_timeline.R` | Main changes: search UI, `pair_stats()` refactor, priority tiers |
| `app/view/signal_timeline.R` | Remove `head(2000)`, add `fuzzy_match_events()` |
| `app/view/signal_timeline.R` | Add priority tier column to DT display |

No new files needed. This is a refactor of the existing module.

### 7. Migration Path

1. **Phase 1:** Add search box + server-side fuzzy search. Keep `head(2000)` as
   the splash default. This is additive — doesn't break existing behavior.
2. **Phase 2:** Replace `head(2000)` splash with priority-ranked default view.
   Requires the priority tier logic and a smaller default set (~200).
3. **Phase 3:** Add MedDRA hierarchy expansion — searching "stroke" also matches
   HLT/HLGT parent terms using `meddra_hierarchy.parquet`.

### 8. Validation

After implementation, verify:
- "ischemic stroke" returns results (fuzzy → "Ischaemic stroke")
- "semaglutide" returns all semaglutide pairs
- Default splash shows emerging/novel signals first
- Caterpillar plot still works when clicking a search result
- Page load time < 5 seconds (was instant with top-2000 DT)
