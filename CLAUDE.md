# globalpatientsafety.com — Global Safety Metrics Dashboard

## Overview

Rhino/Shiny portal app at globalpatientsafety.com. Renders a landing page with cards linking
to each tool in the pharmacovigilance suite. This project is the **clearing house only** — it
does not run signal detection itself.

## Architecture

- **Framework:** Rhino (production Shiny with `box` modules)
- **Sass:** Compiled via Node (`rhino.yml: sass: node`)
- **Deployment:** rsconnect (see `dependencies.R` for packrat discovery)

### Key Files

| File | Role |
|------|------|
| `app/main.R` | App entry point — hero banner + portal cards + about section |
| `app/logic/tools.R` | `TOOLS` tribble — one row per tool card. Add tools here. |
| `app/view/portal.R` | Renders tool cards from `TOOLS` tribble |
| `app/logic/signal_engine.R` | Wraps `safetysignal` package (not used by portal itself) |
| `app/view/signal_table.R` | Signal results table module (not used by portal itself) |
| `rhino.yml` | Rhino config (`sass: node`) |
| `dependencies.R` | Packrat/rsconnect dependency discovery |

## Tool Suite

The portal links to these apps:

| Tool | URL | Project | Status |
|------|-----|---------|--------|
| **faers.mobi** | https://faers.mobi | `/projects/faers-mobi/` | Live |
| **aers.mobi** | https://aers.mobi | `/projects/aers-mobi/` | Beta |
| **pico-dag** | https://picodag.globalpatientsafety.com | `/projects/pico-dag/` | Live |
| Signal methods | — | — | Coming soon |
| MAUDE device safety | — | — | Coming soon |

## Signal Detection Data Flow

Understanding how data reaches the apps:

```
faers-pipeline (Python)          signal-compute (R)           faers-mobi (R/Shiny)
─────────────────────            ──────────────────           ────────────────────
FDA FAERS XML                    Reads contingency parquet    Reads signals.parquet
  → parse + clean                Runs safetysignal per qtr     → DT datatable search
  → contingency parquet          Outputs:                      → caterpillar plots
    at ~/data/faers-pipeline/      signals_faers_v<date>.parquet   → novelty filter
                                   at ~/data/signal-compute/
                                                              scp to VPS → data/signals.parquet
```

### Data Locations

| Data | Path | Producer |
|------|------|----------|
| Raw FAERS contingency | `~/data/faers-pipeline/contingency/` | `faers-pipeline` |
| Drug/event dictionaries | `~/data/faers-pipeline/{drug,event}_dictionary.parquet` | `faers-pipeline` |
| Computed signals | `~/data/signal-compute/signals_faers_v<date>.parquet` | `signal-compute` |
| App-ready signals | `faers-mobi/data/signals.parquet` | Copied from signal-compute output |
| FDA labels | `faers-mobi/data/fda_labels.parquet` | Manual / script |
| MedDRA hierarchy | `faers-mobi/data/meddra_hierarchy.parquet` | Manual / script |

### signals.parquet Schema

Each row is a (drug, event, quarter) tuple:

| Column | Description |
|--------|-------------|
| `drug_concept_id`, `drug_name` | Drug identifier and name |
| `outcome_concept_id`, `outcome_name` | MedDRA PT event identifier and name |
| `quarter` | Time period (YYYY-QN) |
| `observed` | Count in 4-quarter rolling window |
| `eb05`, `eb50`, `eb95` | GPS/EBGM credible interval |
| `prr`, `prr_lci`, `prr_uci`, `prr_chisq` | PRR with CI |
| `ror`, `ror_lci`, `ror_uci` | ROR with CI |
| `ic`, `ic025`, `ic975` | Information Component (BCPNN) |
| `n_methods_flagged` | How many of 4 methods flagged this pair |
| `is_signal_any` | TRUE if ≥1 method flagged |

### Splash Cap (in-app), not a deploy filter

`signal-compute/scripts/deploy_to_vps.sh` `scp`s the **full** `signals_faers_v*.parquet`
(~305 MB, 2.22M rows, ~265k unique pairs at `n_methods_flagged ≥ 2`) to the VPS at
`/srv/shiny-server/faers-mobi/data/signals.parquet`. There is no top-2000 deploy-side filter.

The 2000-row cap is a **splash-display constraint inside the app** at
`faers-mobi/app/view/signal_timeline.R` (`SPLASH_SIZE`). With Track A landed
(2026-04-27, see `DECISION_LOG.md`), the splash shows the top 2000 by Adj EB05 by default,
but server-side fuzzy search (`agrep` over the full set of distinct event/drug names) lets
users reach any of the ~265k pairs by typing a query.

**Implication for "no results" debugging:** if a user searches and gets nothing, the
signal is genuinely absent from the parquet (or the term needs a spelling variant — try
the British/American normalizer or `agrep`). It is NOT being filtered out by a
deploy-time top-N cut.

### Debugging "No Results" for an Event Search

When a user reports that searching for an event returns nothing:

1. **Check if `data/signals.parquet` exists** in the faers-mobi project:
   ```bash
   ls -la /home/harlan/projects/faers-mobi/data/signals.parquet
   ```
   If missing, the data hasn't been deployed locally. Copy from signal-compute output.

2. **Check if the event is in the parquet** (R):
   ```r
   library(arrow)
   library(dplyr)
   ds <- open_dataset("data/signals.parquet")
   ds |> filter(grepl("ischemic stroke", outcome_name, ignore.case = TRUE)) |> collect()
   ```

3. **Check the full signal-compute output** (before top-2000 filtering):
   ```r
   ds <- open_dataset("~/data/signal-compute/signals_faers_v2024-12-31.parquet")
   ds |> filter(grepl("ischemic stroke", outcome_name, ignore.case = TRUE)) |>
     arrange(desc(eb05)) |> head(20) |> collect()
   ```

4. **If the event exists in full output but not in app data:** The top-2000 filter excluded it.
   Options: increase the cutoff in signal-compute, or add a manual inclusion list.

5. **If the event doesn't exist anywhere:** Check MedDRA PT spelling. FAERS uses MedDRA
   Preferred Terms. "Ischemic stroke" might be listed as "Ischaemic stroke" (British spelling)
   or under a different PT like "Cerebrovascular accident".

## Related Projects

| Project | Path | What It Does |
|---------|------|-------------|
| `safetysignal` | `/projects/safetysignal/` | R package: 2-component Gamma-Poisson Shrinker (GPS/EBGM) |
| `signal-compute` | `/projects/signal-compute/` | Runs safetysignal across quarterly contingency → signals.parquet |
| `faers-pipeline` | `/projects/faers-pipeline/` | Python: downloads + parses FDA FAERS XML → contingency parquet |
| `faers-mobi` | `/projects/faers-mobi/` | Shiny app: signal timeline, caterpillar plots, novelty filter |
| `aers-mobi` | `/projects/aers-mobi/` | Shiny app: historical AERS (2004-2012) |
| `pico-dag` | `/projects/pico-dag/` | Shiny app: PICO → UMLS DAG → code lists |

## Development

```bash
# Enter dev shell
nix develop

# Run the portal app
Rscript -e 'shiny::runApp()'

# Or with rhino
Rscript -e 'rhino::app()'
```

## Deployment

The portal is deployed to a Hetzner VPS at globalpatientsafety.com.
faers.mobi and aers.mobi are separate deployments on the same VPS.
