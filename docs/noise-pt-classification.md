# VAERS noise-PT classification

Status: **rescued, not yet integrated** (2026-07-05). Methodology + pointer only — the
data artifacts are **not** in this repo (see *Data location* below).

## What it is

An effort (June 2026) to classify VAERS MedDRA Preferred Terms as **signal-bearing
("EVENT")** vs **low-information ("NOISE")** — lab/investigation results, procedure
terms, non-specific findings — so the signal display can de-emphasize noise.

## Data location (NOT in this repo)

The artifacts live in `~/data/faers-pipeline/noise-pts/` with a provenance README.
They are deliberately kept out of this **public** repo because `vaers_pt_soc_map.parquet`
and the `deterministic_soc` labels encode the **MedDRA PT→SOC hierarchy**, which is
licensed IP — the same reason `meddra_hierarchy.parquet` is symlinked from `~/data/diana/`
rather than committed. `.gitignore` guards the `articles/reviews/` copies.

| Artifact | Rows | Content |
|----------|------|---------|
| `vaers_pt_soc_map.parquet` | 18,577 | MedDRA-derived PT→SOC map (`event`, `n_soc`, `soc_list`, `in_noise`, `in_disorder`, `unmapped`) |
| `noise_pts_final.csv` | 4,998 | Final noise list (`event`, `source` ∈ {llm_consensus 3,511, deterministic_soc 1,483}) |
| `llm_gemma_preds.csv` / `llm_qwen_preds.csv` | 11,569 each | Per-PT EVENT/NOISE from two local models (ollama) |
| `review_disagreements.csv` | 1,373 | gemma-vs-qwen disagreements, pending adjudication |

## Method (reconstructed — generating script is lost)

1. **Deterministic**: PT→SOC via the map; PTs in Investigations/procedure SOCs → noise.
2. **LLM**: gemma + qwen (local, via ollama) each label every PT EVENT/NOISE.
3. **Consensus**: both-NOISE → final noise list; disagreements set aside for review.

A filesystem-wide search found only the outputs, not the code. Reconstruct before
extending.

## Integration plan — FLAG, do not DROP

This is the load-bearing design decision (from the 2026-07-05 grounded review; see
`DECISION_LOG.md`):

- **Never filter at the signal-detection layer.** Compute EBGM/PRR/ROR/IC on every PT.
  Add an `is_low_information_pt` flag to the event dictionary / signal table and let the
  app collapse/gray/toggle noise. Dropping the Investigations SOC would suppress real
  *early objective* drug-toxicity signals (e.g. `5'nucleotidase increased` →
  hepatobiliary injury; `ACTH stimulation test abnormal` → adrenal insufficiency).
- **Deterministic SOC map is the backbone; LLM labels are human-reviewed suggestions**,
  not a co-equal source. Noise is contextual ("blood glucose increased" is noise for most
  drugs, a key signal for antipsychotics).
- **Adjudicate disagreements by rule, not by hand**: flag only PTs that are *both*
  LLM-noise *and* never statistically flagged; human-review only the small set that is
  LLM-noise yet statistically flagged.
- Keep **VAERS-scoped** until re-validated against the FAERS event vocabulary.

## Known issues to fix before integration

- CSV comma-quoting bug: PT names with commas break all three CSVs (~20–30 rows each);
  re-emit with `readr::write_csv`. `llm_qwen_preds.csv` also has 40 `?` rows.
- Depends on MedDRA licensing being resolved for any use beyond the existing unofficial map.
