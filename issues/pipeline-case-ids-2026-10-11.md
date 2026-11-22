# Case IDs through the pipeline (`n_unique`) + VAERS `background=no_covid` recompute

Handshake only. Do not merge. This is the pipeline half of the #102 follow-up. The 3090 runs it in `harlananelson/faers-pipeline` and `harlananelson/signal-compute`, and the API/MCP side goes in `vaers-mobi` and `faers-mobi`. Deploy under standing permission when green, then post a deploy note with `<!-- role:linux -->`, the pushed commit SHAs, and sample curls. No pay gate (parked, #68): no keys, no billing.

Every output is a hypothesis from spontaneous reports, not causation. **The stats layer (signal-compute on the 3090) stays authoritative. No new math and no rescaling in the API layer.**

## Evidence

### What #102's follow-up shipped and what it left blocked

Live 2026-10-11 7:50 AM ET: vaers-mobi `src-9bee0b3`, `X-VAERS-Through: 2026Q2`, homepage 200. Linux's note on #102 (comment 6108674561) says:

> `background=no_covid` is not served. It needs a signal-compute recompute on a contingency that drops COVID19 `VAX_TYPE` reports, using the same GPS/EBGM method. This pass did not rescale the stored EB05 values.

> `n_unique` is not in this extract. The signals parquet has no `VAERS_ID`, so a distinct-report count cannot be derived from it. `n` remains the sum of overlapping 4-quarter windows. The API docs, `format=brief`, and the MCP tool text say that. faers.mobi `/signals` has the same gap (no case id) and was left unchanged.

> The pre-2021 value is the max EB05 on quarters before 2021Q1 in the same series `format=series` returns, with the earliest quarter on a tie. It is not a new statistic.

Because the windows overlap, `n` counts each report up to 4 times (about 4× the real volume).

Linux's correction, accepted: Moderna × Myocarditis (`COVID19 (COVID19 (MODERNA))`) was **not** below EB05 1 until 2025Q2. Measured: 2024Q1 1.0002, 2024Q2 0.9448, 2024Q3 0.7852, 2024Q4 0.9971, 2025Q1 1, 2025Q2 1.181, then a peak of 1.8329 in 2026Q1 and 1.6601 in 2026Q2. It hovers around 1 through 2024–25. Use these numbers, not the earlier Career sentence.

### Reference values (live 2026-10-11 ~7:47 AM ET)

- `GET https://faers.mobi/signals?drug=tzield&event=Nausea&limit=1` returns `X-FAERS-Build: api-f88bd019b098 src-3ae1844`, `X-FAERS-Through: 2025Q4`, `n` 319, `eb05` 7.8091, `eb05_recent` 7.4217, `eb05_prior` 5.5494, `ingredient` teplizumab.
- `GET https://vaers.globalpatientsafety.com/signals?vaccine=MMR&event=Autism%20spectrum%20disorder&limit=1` returns MMR II with `n` 600, `eb05` 91.8767, `ewma_eb05` 113.5004, `eb05_peak_pre2021` 4.2382 (2018Q2), `eb05_peak_quarter` 2021Q4, `peak_in_covid_era` true. No `n_unique` key, and no `background` param.

### Where the case key is dropped today (read from `main`)

**faers-pipeline** (`b18478e`, 2026-09-19):

- VAERS: `R/parse_vaers.R` `parse_vaers_csv_row()` joins `.parse_vaers_data_csv()` (`vaers_id`, `quarter` from `RECVDATE`), `.parse_vaers_vax_csv()` (`rxcui` = `VAX_TYPE`, `rxnorm_name` = `VAX_NAME`), and `.parse_vaers_symptoms_csv()`. It then runs `distinct(vaers_id, rxcui, outcome_name, .keep_all = TRUE)`. **`vaers_id` is still present here** (target `vaers_long` in `_targets.R`). `R/contingency_vaers.R` `build_vaers_contingency()` then `count()`s by `quarter, rxcui, rxnorm_name, outcome_concept_id, outcome_name`. **That is where `vaers_id` is lost.** Output: `contingency/source=vaers/year=/quarter=/part-0.parquet`.
- FAERS: in `_targets.R`, target `fda_demo_dedup` keeps the latest `caseversion` per `caseid`, with `caseversion` coerced to integer first. `R/contingency.R` `build_quarterly_contingency_fda()` joins DRUG (role `PS`) × REAC × DEMO on `primaryid`, runs `distinct(primaryid, rxcui, outcome_name, .keep_all = TRUE)`, then `count()`s by quarter. **`primaryid`/`caseid` is lost at that `count()`.** The target is `contingency_final`. (Banda path: `build_quarterly_contingency()`, same pattern.)
- Note: `faers-pipeline` `main` has not changed since 9/19. If the #96 ingredient-level recompute changed the FAERS drug key on the 3090, push that first (keep-GitHub-current rule) so the membership artefact keys match what faers.mobi serves.

**signal-compute** (`7910fee`, 2026-07-14), `R/compute_quarterly.R`:

- Args: `--source vaers|faers`, `--window-quarters` 4, `--prior-strategy` cumulative, `--min-observed` 3, `--ewma-lambda` 0.3, `--contingency-root`, `--output-root`.
- `window_data()` sets `drug = coalesce(rxnorm_name, rxcui)` and `event = outcome_name`, then sums `observed` over the window's quarters. Per quarter: `safetysignal::fit_prior()` on the cumulative data, then `safetysignal::detect_all_methods(methods = c("gps","prr","ror","ic"), min_count = min_observed, prior = pooled_prior)`, then EWMA (`stats::filter(..., method = "recursive")`) on `eb05` and `ic025` per (drug, event). Writes `signals_<source>_v<date>.parquet`.
- Deploy: `scripts/deploy_vaers_to_vps.sh` (VAERS → `/srv/shiny-server/vaers-mobi/data/signals.parquet` plus `vaccine_dictionary.parquet`, then `restart.txt`) and `scripts/deploy_to_vps.sh` (FAERS).
- No `control/runbook.yaml` was found in globalpatientsafety, faers-pipeline, signal-compute, faers-mobi, or vaers-mobi. If Harlan's runbook convention lives somewhere else, use it. Otherwise commit the run config next to the code (see C).

## Asks

### A. Carry the case key → `n_unique`, `n_unique_recent`

1. **faers-pipeline:** alongside the existing contingency (unchanged), write a case-membership artefact with one row per (`quarter`, `rxcui`, `rxnorm_name`, `outcome_name`, case key). For example, write `case_membership/source=vaers|fda/year=/quarter=/part-0.parquet`; the name is your call.
   - VAERS: case key = `vaers_id`, taken from `vaers_long` before `build_vaers_contingency()` counts.
   - FAERS: case key = `caseid` (keep `primaryid` too), taken from the `build_quarterly_contingency_fda()` join after `fda_demo_dedup`, so each case contributes only its latest version.
2. **signal-compute** (or a small sibling script; your call): for the same pair key the signals use (`drug = coalesce(rxnorm_name, rxcui)`, `event = outcome_name`, plus whatever the #96 ingredient key is for FAERS), compute
   - `n_unique` = distinct case keys for the pair over all quarters
   - `n_unique_recent` = distinct case keys over the last 4 quarters (the latest window)
   
   and write them to the signals output or a side parquet that ships with it.
3. **Serve:** VAERS `/signals` (json, csv, brief), faers.mobi `/signals` (json, csv, brief), and the MCP tools `vaers_get_signal`, `vaers_get_profile`, `get_signal`, `get_profile`. **Keep `n` unchanged** for backward compatibility.
4. **Docs** (`/api`, `/api.md`, `/openapi.json`, `/mcp.md`, `llms.txt`, MCP tool text, brief): say `n_unique` is the number to quote as "reports", and `n` is the sum of overlapping 4-quarter windows (not a report count).
5. Sanity check worth reporting: since each report sits in exactly one quarter (VAERS by `RECVDATE`, FAERS by filing quarter after caseid dedup), `n_unique` should come close to the sum of the per-quarter contingency `observed` for the pair. Explain any gap. One known quirk: `distinct(..., .keep_all = TRUE)` on `rxcui` keeps only one `rxnorm_name` per report and VAX_TYPE.

**Bar:** every served row has `n_unique ≤ n`. If any row breaks this (for example reports in quarters whose window fell below `min_observed`), report how many rows and why, and don't clamp. `tzield × Nausea` still returns `n` 319 and `eb05` 7.8091, and the other existing fields are unchanged.

### B. VAERS `background=no_covid` (full recompute, no rescaling)

1. Build a second VAERS contingency that drops **every report** with a COVID19 `VAX_TYPE` from the whole table (both the pair cells and the background), not just the COVID rows. List the exact `rxcui` codes dropped (check for variants beyond `COVID19`) and the number of reports removed.
2. Run `R/compute_quarterly.R --source vaers` on it with the **same** method, prior strategy, window, `min_observed`, and EWMA λ as the default run (`--window-quarters 4 --prior-strategy cumulative --min-observed 3 --ewma-lambda 0.3`, or whatever the deployed run actually used; state it). Write it to a separately named output (for example a `--output-root` variant). Recompute the pre-2021 peak and `peak_in_covid_era` fields from that series too.
3. Serve it as an opt-in `background=no_covid` on VAERS `/signals` (all formats, including `format=series`) and the `vaers_*` MCP tools. Echo `background` in each response and an `X-VAERS-Background` header. **The default (`background=all` or omitted) is unchanged.** COVID19 vaccines return no rows under `no_covid`; say so in the brief and docs instead of returning an error. An unknown `background` value → 400.

**Bar:** MMR II × Autism spectrum disorder under `no_covid` shows a 2021–22 peak far below 91.9. **Report the actual number and quarter. Don't presume it.** The default response for the same pair is unchanged (`n` 600, `eb05` 91.8767).

### C. Who runs it, provenance, monitoring

- The 3090 runs A and B. The stats layer stays authoritative. The API and MCP only read its outputs.
- Commit the code **and the run config** (CLI args, input data vintage, safetysignal version, output file names). Use Harlan's `control/runbook.yaml` convention if it exists. Otherwise put a run-config file in signal-compute and reference it in the deploy note.
- **Push before deploy** (faers-pipeline, signal-compute, vaers-mobi, faers-mobi, globalpatientsafety). Put every pushed SHA in the `<!-- role:linux -->` deploy note, and say so if a push fails. The live build headers must match GitHub.
- Add one monitor check per new field or param to `scripts/monitor_faers_mobi.sh`: `n_unique` present and ≤ `n` on the VAERS and faers.mobi reference pairs; `n_unique_recent` present; `background=no_covid` returns 200 and echoes the background value; `background=bogus` → 400; the default MMR II × ASD values are unchanged; MCP `vaers_get_signal` and `get_signal` return `n_unique`.
- Pay gate stays parked.

## Live bar

- [ ] `curl -s 'https://faers.mobi/signals?drug=tzield&event=Nausea&limit=1'` → `n` 319, `eb05` 7.8091, plus `n_unique` ≤ 319 and `n_unique_recent`
- [ ] `curl -s 'https://vaers.globalpatientsafety.com/signals?vaccine=MMR&event=Autism%20spectrum%20disorder&limit=5'` → `n` 600, `eb05` 91.8767, plus `n_unique` ≤ 600 and `n_unique_recent`
- [ ] The same URL with `&background=no_covid` → the response echoes `background`, and the 2021–22 peak is reported (actual value and quarter)
- [ ] `background=bogus` → 400. The default response is unchanged.
- [ ] MCP `vaers_get_signal`, `vaers_get_profile`, `get_signal`, and `get_profile` return `n_unique` and match `/signals`
- [ ] The docs say to quote `n_unique`
- [ ] The deploy note lists the pushed SHAs for all touched repos plus the run config, and the build headers match GitHub
