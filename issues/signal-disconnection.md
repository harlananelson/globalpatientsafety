# Signal disappearance from class-label drift across MedDRA / ATC / DiAna / UMLS versions

## Summary

Substance-level signals (e.g. `gatifloxacin;prednisolone` + corneal infiltrates) appear to terminate at specific quarter boundaries even when the underlying drug-event co-reporting pattern is unchanged. Investigation suggests these are not real signal attenuation events but classification drift: the class assigned to a (drug, event) pair changes across quarters because an upstream vocabulary or model version changed, not because the world changed.

The current pipeline normalizes drug strings (DiAna substance-level rollup is the default view) but does not track or bridge class assignments across vocabulary versions. This produces phantom signal disappearances and undermines the time-course interpretation.

## Scope

This affects both sides of the pair:

- **Event side**: MedDRA PT / HLGT / HLT / SOC assignments
- **Drug side**: ATC codes, DiAna substance resolution, UMLS CUI synonym expansion, internal classifiers (ATC4-class flag, novel-flag, class co-flags)

## Root causes (class-label drift sources)

| Source | Cadence | Bridge available? | Notes |
|---|---|---|---|
| MedDRA version bump | Twice yearly (March, September) | Yes — MSSO publishes change documentation | PT can stay identical by name/code but move under a different HLGT/SOC. Class derived from higher hierarchy levels will miss this. |
| ATC reclassification | Annual (January, WHOCC) | Yes — WHOCC publishes changes | Substance can sit under multiple ATC codes; resolver tiebreaker changes flip assignment. |
| UMLS release | Twice yearly (May, November) | Yes — published change files | CUI merges, splits, retirements affect synonym-expansion equivalence classes. |
| DiAna version | Pipeline-controlled | Self-managed | Must pin per quarter or recompute historical quarters under current version. Unpinned → version boundary becomes a phantom discontinuity. |
| Internal classifiers (ATC4-class, novel-flag, class co-flags) | Whenever retrained | None — must build | Decision boundary moves; same input → different class. Hardest case. |

## Why this matters

- Disproportionality output is consumed as a time series. Phantom discontinuities mislead users into investigating market events that didn't happen.
- The "No label cached for X — can't determine if this signal is known" path will mis-route any pair whose class assignment moved.
- Consumers of the app (clinical / regulatory) need a defensible answer to "did this signal go away or did your pipeline change?"

## Proposed work

### 1. Instrument first

Before building any bridges, add a **version delta at boundary** view to the signal-disappearance path. For each pair where signal drops below threshold between quarter N and N+1, surface:

- MedDRA version at N vs N+1
- ATC version at N vs N+1
- UMLS version at N vs N+1
- DiAna version at N vs N+1
- Internal classifier version(s) at N vs N+1

Expected outcome: disappearances cluster on release boundaries. This both confirms the diagnosis and tells us which bridge gives the most lift per unit of work.

**Acceptance**: signal-disappearance view shows version stamps for both sides of the boundary; SQL/R reproducible.

### 2. Persist version stamps on every classification

One row per classification, versioned. No classification stored without:

- `meddra_version`
- `atc_version`
- `umls_version`
- `diana_version`
- `internal_classifier_version`
- `classified_at` timestamp

This is a precondition for both bridge work and reproducibility. Without it, we can't reconstruct what a quarter "looked like" under a given version regime.

**Acceptance**: schema migration applied; backfill plan documented (may not be possible for historical classifications — flag those as `version_unknown`).

### 3. Event-side bridge (do this first)

MedDRA changes affect more pairs per release than ATC changes, change documentation is better, and the fix is mechanical.

- Ingest MSSO version-to-version change files for each MedDRA release covering the data window.
- Build a PT-level bridge table: `(meddra_version_from, pt_code, meddra_version_to, pt_code_to, change_type)` where `change_type ∈ {unchanged, renamed, demoted, promoted, hierarchy_moved, retired, replaced_by}`.
- Build hierarchy-level bridges for HLGT/SOC where the PT identity is preserved but the parent moved.
- Apply bridges when computing cross-quarter signal continuity.

**Acceptance**: given a known MedDRA-version-driven disappearance from the screenshots, the bridged view shows continuous signal; the unbridged view shows the discontinuity. Side-by-side comparison committed as a regression test.

### 4. Drug-side bridge

In order of difficulty:

- **DiAna**: pin version per quarter, or recompute all historical quarters under the current version. This is a decision, not research — pick one and document why.
- **ATC**: ingest annual WHOCC change lists. Build `(atc_version_from, atc_code, atc_version_to, atc_code_to, change_type)` table.
- **UMLS**: ingest CUI change files. Track merges, splits, retirements affecting synonym expansion.
- **Internal classifiers**: log every classification with model version + decision boundary metadata. Build a self-bridge by re-scoring historical pairs under the current model and diffing. This is the messiest case and gets done last.

**Acceptance**: each drug-side source has a version-bridge table or a documented "no bridge needed because we pinned/recomputed" decision.

### 5. Signal disappearance classifier

When a pair-level signal drops below threshold, classify the cause:

- `market_withdrawal` — verified against DailyMed / Orange Book
- `class_drift_event_side` — bridged through MedDRA bridge
- `class_drift_drug_side` — bridged through ATC / DiAna / UMLS / classifier bridge
- `system_boundary` — AERS→FAERS Sept 2012, or FAERS schema version changes
- `real_attenuation` — none of the above; signal genuinely weakened

UI surfaces the classification rather than showing a flat "signal ended."

**Acceptance**: every signal-disappearance event in the UI has a classification; "real_attenuation" is the residual category, not the default.

### 6. Similarity-based fallback (last resort)

For residuals where no published bridge exists — primarily internal classifier drift on long-tail labels — use:

- Token-set similarity (Jaro-Winkler or token-set ratio, not raw edit distance) on resolved substance names where partial resolution exists.
- Embedding similarity as a tiebreaker, not a primary signal. Existing self-hosted embedding endpoint pattern from `txtarchive` work is a fit here — keep external API calls out of the surveillance pipeline.

**Acceptance**: fallback only fires when version-bridge tables return no match; every fallback link is logged with similarity score and reviewable.

## Out of scope for this issue

- Replacing EBGM with a different disproportionality method.
- AERS→FAERS 2012 transition handling (separate concern, separate issue).
- Gatifloxacin oral vs ophthalmic route disambiguation (separate concern — pipeline currently collapses route, which is a different data-model issue).

## Sequencing

1. Instrument version-delta-at-boundary view (read-only, no schema changes yet).
2. Confirm the diagnosis from the instrumentation: do disappearances cluster on release boundaries? If no, this whole plan needs rethinking.
3. Schema migration for version stamps.
4. Event-side (MedDRA) bridge.
5. Drug-side bridges in difficulty order.
6. Disappearance classifier wired into UI.
7. Similarity fallback for residuals.

Steps 1–2 are gating. Don't build bridges until the instrumentation confirms the cluster pattern.

## Open questions

- ~~Do we have MedDRA license coverage to ingest version-to-version change files into the repo?~~ **Resolved 2026-05-03:** No MSSO license needed. `meddra_hierarchy.parquet` is built entirely from the UMLS REST API (see `faers-pipeline/scripts/fetch_meddra_hierarchy.R`), not from a licensed MedDRA distribution. UMLS tracks CUI history across releases (retirements, merges, splits), which covers the common bridge case — PT renamed or hierarchy-moved but CUI preserved. Full MSSO change files would give more detail but are not the gating dependency. Build the bridge via UMLS history API first; escalate to MSSO only if Step 2 instrumentation reveals a large class of CUI-level retirements not covered by UMLS.
- For DiAna: pin per quarter, or recompute historical quarters under current version? Tradeoff is reproducibility-of-prior-output vs. consistency-of-current-output. Need to pick one.
- Is the internal classifier (novel-flag, class co-flags) versioned at all currently, or is it implicitly "whatever main was when this row was written"?

## References

- Screenshots showing phantom signal termination at 2012Q2 for `gatifloxacin;prednisolone` + corneal infiltrates.
- Substance-level toggle is the default and is working correctly — this issue is downstream of substance resolution.
- DiAna note in app: "86 ibuprofen brands → 1 row" ~91% of distinct strings, ~5% of report volume unresolved. The unresolved long tail is where similarity fallback (step 6) earns its keep.