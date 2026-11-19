---
title: "FAERS data refresh — steps"
subtitle: "faers-pipeline → signal-compute → faers-mobi → globalpatientsafety · 2026-11-19"
---

**Key.** [read] = read from code. [inf] = inferred, check first.
WS = workstation terminal. SSH to the VPS (root@5.78.69.136) works only from
your own terminal or a Claude prompt starting with `! `.

# Where things stand now

- **FAERS raw:** the workstation has quarters through **2026Q2**.
  Live faers.mobi runs only through **2025Q4** (the July build).
- **Signals live:** `signals_faers_v2026-07-08` (3.6 GB). Its smoothing step is
  wrong: y = x + 0.3·y(prev), not an EWMA. A steady EB05 of c is shown as
  ≈ 1.43c. A missing quarter blanks every later quarter.
- **Oct-17 parquet:** runs through 2026Q2, never deployed.
  1.72M → 568k flagged pairs, cause unknown.
- **RxNorm:** full release of **2026-04-06**. Newer monthly releases exist [inf].
- **FDA labels:** the cache was built in October.
- **Bulk export (#119):** live and verified, 401,527 rows.

# A. Decisions — make before starting

**D1. Headline EB05.** (i) latest EWMA at the last flagged quarter, or
(ii) keep the peak (max EWMA), with only the formula fixed.
Fix alone: median EB05 × 0.55, ranking within a drug unchanged.
Fix + latest: × 0.49, ranking moves (ivosidenib ρ 0.57).

Choice: ______________________

**D2. n_unique.** (i) ship without it, or (ii) wait for the RxNorm mapping (#122).

Choice: ______________________

**D3. Oct-17 parquet.** (i) discard and rebuild *(recommended by faers-mobi)*, or
(ii) ship it once the 1.72M → 568k drop is explained.

Choice: ______________________

**D4. #122 RxNorm ingredient table:** build it in faers-pipeline or in faers-mobi.

Choice: ______________________

**D5. Portfolio:** switch from 1,800 `/signals` calls to the export (this also
fixes the 300-row cap on event counts), then enable the weekly timer.

Yes / Later: ______________________

# B. faers-pipeline — WS, ~/projects/faers-pipeline

**☐ 1.** Check fda.gov for a quarter newer than 2026Q2.
[inf] 2026Q3 is usually out by mid-November.

**☐ 2.** Enter the environment:

```bash
nix develop
```

**☐ 3.** Clean rebuild (optional, run first):

```bash
Rscript scripts/clean_contingency_source.R faers
```

**☐ 4.** Run the pipeline [read]:

```bash
FAERS_PIPELINE_SOURCE=fda \
FAERS_FROM_QUARTER=2004Q1 \
FAERS_TO_QUARTER=<YYYYQN> \
Rscript scripts/run_pipeline.R
```

✔ The targets run finishes with no errored branch.
Output: `~/data/faers-pipeline/contingency/source=faers/` [inf]

**☐ 5.** RxNorm: download the current full release.
[inf] How the pipeline picks it up has not been checked.

**☐ 6.** Labels: `scripts/build_fda_labels_v2.R`, then
`augment_fda_labels_multi_product.R`. [inf] Order and arguments not checked.

Notes:

\

\

# C. signal-compute — two builds, WS, ~/projects/signal-compute

Fix (a) has **no flag** [read]. The old smoothing is in HEAD. The fix is
uncommitted: `R/ewma.R`, the edit to `compute_quarterly.R`, `tests/test_ewma.R`.

**☐ 7.** Commit fix (a) on a branch, then run its test. ✔ It passes.

```bash
Rscript tests/test_ewma.R
```

**☐ 8.** Old-smoothing build, from a worktree at the commit before the fix:

```bash
git worktree add ../sc-old <pre-fix sha>
cd ../sc-old
nix develop -c Rscript R/compute_quarterly.R \
  --output-root ~/data/signal-compute/ab/old
```

**☐ 9.** Fixed build:

```bash
cd ~/projects/signal-compute
nix develop -c Rscript R/compute_quarterly.R \
  --output-root ~/data/signal-compute/ab/fixed
```

**!! Use separate output roots.** Both runs write `signals_faers_v<today>.parquet`.
Defaults [read]: window 4 quarters, cumulative prior, min-observed 3, λ 0.3.

**☐ 10.** Substance build: `scripts/build_substance_contingency.R`, then
`compute_quarterly.R` on its output. [inf] Arguments not checked.

**☐ 11.** Ask Claude (globalpatientsafety) to compare:
old vs fixed = **method effect**; old vs July = **data effect**.

**☐ 12.** Copy **only** the chosen build into `~/data/signal-compute/`.
It must be the newest `signals_faers_v*.parquet` there.

Notes:

\

\

# D. faers-mobi — WS, ~/projects/faers-mobi

**☐ 13.** faers-mobi Claude commits the code for your D1/D2 choice on top of the
deployed signals-export branch (7d83b0c). You review the diff.
✔ The tests pass and the diff has been shown to you.

**☐ 14. NOTIFY globalpatientsafety first.** Wait until it says the old-EB05
baseline is saved: the current export (sha256 `7118ce7a…`) and the monitor values.

**☐ 15.** Upload the data (needs SSH):

```bash
cd ~/projects/signal-compute
./scripts/deploy_to_vps.sh
```

!! It ships the **newest** parquet by mtime [read].
✔ It prints the right file names and sizes, then "Deployed."
It restarts only shiny-server, so run step 16 straight after.

**☐ 16.** Deploy the code (needs SSH; ~26 min, rebuilds the export):

```bash
! cd /home/harlan/projects/faers-mobi-export && scripts/deploy.sh
```

✔ `live and verified`, then `export: wrote N rows … through <quarter>`,
then 3× `worker :384x current`, and exit 0.

**☐ 17.** Check. The meta should show `"current":true` and the new `through`;
tzield should return 200.

```bash
curl -s https://faers.mobi/signals/export/meta
curl -sI 'https://faers.mobi/signals?drug=tzield'
```

A 503 from the export means it is still rebuilding; the reason is in the body.

**☐ 18.** Optional: a nightly export rebuild via cron at 03:40 (see faers-mobi's notes).

**☐ 19.** Tell faers-mobi Claude the deploy is done. It runs the parity check
and posts the result on the PR.

Notes:

\

\

# E. globalpatientsafety — Claude does these; you say go

**☐ 20.** Verify the export: meta, sha256, and parity against `/signals` for
tiopronin, ivosidenib, tzield, glargine and semaglutide. Post on the PR.

**☐ 21.** Compare new against old EB05 using the step-14 baseline.
Check whether the monitor checks that assert EB05 values need re-pinning.

**☐ 22.** If D5 = yes: switch Portfolio to the export (it keeps its cache on a
503), commit, deploy.

**☐ 23.** Run the Portfolio refresh, then enable the weekly timer:

```bash
ssh root@5.78.69.136 \
  'systemctl enable --now gps-portfolio-refresh.timer'
```

**☐ 24.** List the articles that quote EB05 values whose numbers changed.

Notes:

\

\
