# Deploy Plan — Dependent Dropdowns for aers.mobi & faers.mobi

**Status:** drafted 2026-04-20, not yet executed.
**Scope:** code change in two sibling repos + deploy to Hetzner Shiny Server host.
**Originating repo:** globalpatientsafety (this plan lives here because the
three apps share a Hetzner box and a CLAUDE.md mentions them together).

---

## 1. The feature

In `aers.mobi` and `faers.mobi` the Signal Timeline view currently populates
the Drug and Event dropdowns from the full dictionaries (`drug_dictionary.parquet`,
`event_dictionary.parquet`). Many of those entries have no signal row in
`signals.parquet`, so users can select a pair that returns "No signals found".

**Desired behavior:** only list options where signals data exists, and cross-filter.

- Initial load: both dropdowns list only drugs / events that appear in
  `signals.parquet`.
- After the user picks a Drug: the Event dropdown narrows to events with
  at least one signal row for that drug. Current Event stays selected if
  still valid; cleared otherwise.
- After the user picks an Event: the Drug dropdown narrows to drugs with
  at least one signal row for that event. Same selection-preservation rule.
- Clearing a selection restores the full (signal-bearing) list on that side.

---

## 2. Files to change

Both apps have identical structure:

| Repo | File |
|---|---|
| `aers-mobi` | `app/view/signal_timeline.R` |
| `faers-mobi` | `app/view/signal_timeline.R` |

Changes to that file:

1. Add a reactive `pairs_cache()` that materializes distinct
   `(rxnorm_name, outcome_name)` pairs from `SIGNALS_PATH`. Memoize: read
   once per session, use `arrow::open_dataset() |> distinct() |> collect()`.
2. Replace the existing `observe({...})` block that populates choices from
   `DRUG_DICT_PATH` / `EVENT_DICT_PATH`. Populate instead from
   `pairs_cache()`.
3. Add `observeEvent(input$drug, ...)` that narrows event choices. Use
   `updateSelectizeInput(..., server = TRUE)` with `selected = input$event`
   if still in the new choices, else `selected = character(0)`.
4. Add `observeEvent(input$event, ...)` that narrows drug choices, same
   selection-preservation rule.
5. Handle the "empty selection" case: if `input$drug` is `""`/`NULL`,
   restore the full (signal-bearing) event list. Vice versa.

**Tradeoff:** materializing distinct pairs from a 200–500 MB parquet on first
access takes seconds. If that's visible to the user, add a precomputed
`pairs.parquet` in the offline `signal-compute` job and read it directly
here. V1 uses the in-process distinct; V2 the precomputed file.

---

## 3. Deploy workflow (needs Hetzner SSH)

Box: `5.78.69.136` (nginx + Shiny Server, per earlier recon).

Steps the executing agent must run:

```bash
# 1. Make the edits in both local repos
#    - /home/harlan/projects/aers-mobi/app/view/signal_timeline.R
#    - /home/harlan/projects/faers-mobi/app/view/signal_timeline.R

# 2. Commit + push each repo
cd /home/harlan/projects/aers-mobi && git add -A && git commit -m "..." && git push
cd /home/harlan/projects/faers-mobi && git add -A && git commit -m "..." && git push

# 3. SSH to Hetzner and pull both clones
ssh <HETZNER_USER>@5.78.69.136 "cd <AERS_PATH> && git pull"
ssh <HETZNER_USER>@5.78.69.136 "cd <FAERS_PATH> && git pull"

# 4. Reload Shiny Server (if it does not pick up changes automatically)
ssh <HETZNER_USER>@5.78.69.136 "<RELOAD_CMD>"

# 5. Smoke-test both URLs
curl -sI https://aers.mobi/ | head -1
curl -sI https://faers.mobi/ | head -1
```

---

## 4. Environment (resolved 2026-04-20)

1. **SSH.** `ssh root@5.78.69.136` works with the user's default
   `~/.ssh/id_ed25519`. Box hostname is `ubuntu-2gb-hil-1`. No
   `~/.ssh/config` entry needed.
2. **App paths on the box.**
   - `/srv/shiny-server/aers-mobi/` — HTTPS clone of
     `github.com/harlananelson/aers-mobi`, owned by `shiny` user
   - `/srv/shiny-server/faers-mobi/` — HTTPS clone of
     `github.com/harlananelson/faers-mobi`, owned by `shiny` user
   - Also present on the same box: `globalpatientsafety/` and `pico-dag/`.
   - Access git as the owner: `sudo -u shiny git -C <path> pull`.
3. **Reload mechanism.** Shiny Server auto-reloads the R process when
   `<app>/restart.txt` is touched. No `systemctl` needed.
   Command: `sudo -u shiny touch /srv/shiny-server/<app>/restart.txt`.

nginx vhosts are already wired: `/etc/nginx/sites-enabled/{aers-mobi,
faers-mobi, globalpatientsafety, picodag}`.

---

## 5. Verification checklist

After deploy:

- [ ] `https://aers.mobi/` returns HTTP 200
- [ ] `https://faers.mobi/` returns HTTP 200
- [ ] Drug dropdown on both apps only lists drugs that have signal rows
- [ ] Picking `vioxx` on aers.mobi narrows the event list (should include
      `Myocardial infarction`, far fewer rows than the full MedDRA PT list)
- [ ] Picking `Myocardial infarction` with no drug selected shows only
      drugs that have signals for MI (narrower drug list)
- [ ] Clearing a dropdown restores the full signal-bearing list on that side
- [ ] No "No signals found" should appear for any selectable pair

---

## 6. Rollback

Revert the commit in each repo on GitHub, then repeat steps 3 + 4 on the
Hetzner box to pull the revert and reload.
