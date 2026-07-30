# globalpatientsafety.com — Global Safety Metrics Clearing House

## Overview

Landing site at globalpatientsafety.com for the pharmacovigilance tool suite.
This project is the **clearing house only** — it does not run signal detection itself.

**Production front end is the static site** built by `scripts/build_static_site.R`
and deployed to `/var/www/globalpatientsafety/` on the VPS (nginx, zero R workers).
The interactive Rhino/Shiny app is **retired** for this domain and was archived to
`archive/rhino-app/` on 2026-07-30 (see the README there). Tool subdomains
(faers.mobi, aers.mobi, vaers, pico-dag) remain separate Shiny apps.

What is left under `app/` is **static-site input, not a Shiny app**: the `app/logic/`
registries and the pre-rendered `app/static/` HTML. The builder reads both by path.

## Architecture

| Layer | Role |
|-------|------|
| **Static site (production)** | `scripts/build_static_site.R` → `static_site/` → rsync to VPS |
| **Registries (source of truth)** | `app/logic/articles.R` (`ARTICLES`), `app/logic/tools.R` (`TOOLS`) |
| **Article HTML** | Quarto sources in `articles/*.qmd` → render into `app/static/<id>.html` |
| **Standalone pages** | `articles/methods.qmd`, `articles/aems-analysis.qmd` → `app/static/{methods,aems}.html` |
| **Retired Shiny portal** | `archive/rhino-app/` — archived, not built, not deployed, not tested |

### Key Files

| File | Role |
|------|------|
| `scripts/build_static_site.R` | **Production builder** — index, articles grid, article pages, standalone nav pages |
| `app/logic/articles.R` | `ARTICLES` tribble — published/draft rows; static site ships only `published` |
| `app/logic/tools.R` | `TOOLS` tribble — one row per tool card on the homepage |
| `app/static/<id>.html` | Pre-rendered Quarto HTML consumed by the builder |
| `scripts/check_site_consistency.R` | CI guard — registries vs shipped HTML; base R only |
| `.github/workflows/site-checks.yml` | Runs the consistency check on push and PR |
| `archive/rhino-app/` | Retired Shiny portal — see its README before touching it |

### Build & deploy

```bash
# After rendering new/changed Quarto articles into app/static/
Rscript scripts/build_static_site.R

# Deploy static_site/ to the VPS (path is also printed by the builder)
rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/
```

The builder:
- Emits nav links for standalone pages (`/methods`, `/aems`) **only when** `app/static/<id>.html` exists
- Warns on dead same-site internal links in the built HTML
- Opens same-site tool URLs (e.g. `/methods`) in the current tab; external tools in a new tab

## Tool Suite

| Tool | URL | Project | Status |
|------|-----|---------|--------|
| **faers.mobi** | https://faers.mobi | `/projects/faers-mobi/` | Live |
| **aers.mobi** | https://aers.mobi | `/projects/aers-mobi/` | Beta |
| **pico-dag** | https://picodag.globalpatientsafety.com | `/projects/pico-dag/` | Live |
| **VAERS vaccine safety** | https://vaers.globalpatientsafety.com | (vaers app) | Live |
| **Signal methods** | `/methods` (Signal & Noise) | this repo | Live |
| MAUDE device safety | — | — | Coming soon |

## Signal Detection Data Flow

Understanding how data reaches the apps (sibling projects; not run here):

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

Each row is a (drug, event, quarter) tuple. Column names after the 2026-04 migration
(see DECISION_LOG): **`drug`** / **`event`** (not `drug_name` / `*_concept_id` / `rxnorm_name`).

| Column | Description |
|--------|-------------|
| `drug`, `event` | Drug name and MedDRA PT event name |
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
   ds |> filter(grepl("ischemic stroke", event, ignore.case = TRUE)) |> collect()
   ```

3. **Check the full signal-compute output**:
   ```r
   ds <- open_dataset("~/data/signal-compute/signals_faers_v2024-12-31.parquet")
   ds |> filter(grepl("ischemic stroke", event, ignore.case = TRUE)) |>
     arrange(desc(eb05)) |> head(20) |> collect()
   ```

4. **If the event exists in full output but not in app data:** rare; confirm the
   app is on the full parquet (not an old top-N slice).

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

# Build the production static site (the only build path)
Rscript scripts/build_static_site.R

# Same consistency check CI runs — registries vs shipped HTML
Rscript --vanilla scripts/check_site_consistency.R
```

There is no `shiny::runApp()` / `rhino::app()` path any more; that portal is archived.

### Adding a published article

1. Write/render Quarto → `app/static/<id>.html`
2. Add a `published` row to `app/logic/articles.R` (`id` must match the HTML stem)
3. Rebuild: `Rscript scripts/build_static_site.R`

A `published` row with no matching `app/static/<id>.html` fails CI. Keep an article
`draft` until its HTML is rendered — the builder skips drafts and the consistency
check rejects any link to one from `methods.html` / `aems.html`.

### Adding a tool card

Append a row to `TOOLS` in `app/logic/tools.R`. Use `status = "live"` and a real URL
(same-site paths like `/methods` are fine). Rebuild the static site.

## Deployment

- **This domain (globalpatientsafety.com):** static files from `static_site/` via nginx.
- **faers.mobi / aers.mobi / vaers / pico-dag:** separate Shiny deployments on the same VPS.
- Do not assume rsconnect/Shiny is serving the homepage; the builder header and
  `articles/DEPLOY-christine-cotton.md` record the retirement.
