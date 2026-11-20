# RxNorm ingredient on /signals rows and the export

Handshake only. Do not merge. Implement in `/projects/faers-mobi/`, and in `/projects/faers-pipeline/`
where the mapping is built. Deploy when good.

**Depends on #119 (bulk export), which is built but not deployed.** Live faers.mobi does not run
the #119 code yet. Build this on top of #119 and ship both in one deploy, unless #119 goes out
first on its own.

## Why

Portfolio safety (globalpatientsafety.com/portfolio) groups each company's products by active
ingredient. faers-mobi-7d reported (2026-11-18) that the export's `ingredient` is the DiAna
substance, and it is too coarse for that:

- Lantus, Toujeo, Basaglar and "insulin glargine" all carry `ingredient = "insulin"`, pooled
  with every other insulin. Filtering on `"insulin glargine"` returns 0 rows.
- Entresto carries `"sacubitril;valsartan"`.

So Portfolio cannot join on `ingredient` and has to substring-match reported names client-side
(`row_belongs`, `ingredient_aliases` in `globalpatientsafety/scripts/gps_portfolio.py`). The
data needed for a proper join is already on the workstation.

## Measured on the workstation (2026-11-18)

- `~/data/faers-pipeline/output/drug_dictionary.parquet`: 521,449 reported names, with
  columns `rxcui, rxnorm_name, drug_raw, tier, confidence`. Tier counts: exact 46,118,
  fuzzy 125,306, unmapped 350,025. That is 33% of names mapped, counted by distinct names.
  Coverage by reports has not been measured.
- `~/data/faers-pipeline/raw/rxnorm/RxNorm_full_04062026.zip` (full release, with RXNREL).
- Raw names matching glargine, Lantus, Toujeo, Basaglar, Entresto or sacubitril map to distinct
  concepts: insulin glargine 274783, Lantus 261551, Toujeo 1604540, Basaglar 1736859,
  Semglee 2377130, glargine-yfgn 2563969, glargine-aglr 2589006, Entresto 1656341,
  sacubitril 1656328, sacubitrilat 1860608. These are brand (BN) and ingredient (IN/MIN) concepts
  mixed together, not yet rolled up to ingredient.
- Wrong fuzzy matches in that set: inulin (5924) 24 names, galactose (4626) 1 name.
  973 matching names have no rxcui at all.

## Ask

1. **Mapping table (faers-pipeline):** reported drug string → RxNorm ingredient. Roll brands
   and clinical drugs up to IN via RXNREL (`has_ingredient`, `tradename_of`, `consists_of`).
   Multi-ingredient products get their MIN or the sorted IN set (Entresto → sacubitril +
   valsartan; Soliqua → insulin glargine + lixisenatide).
2. **Fuzzy-tier precision:** drop or flag fuzzy matches whose ingredient shares no token with
   the raw string (inulin and galactose for glargine names). Report how many fuzzy rows that
   removes.
3. **Coverage by reports, not names:** the share of drug-event report counts (`n` / observed)
   whose drug string maps to an ingredient, overall and among rows with `min_n ≥ 10`.
4. **Expose it:** add `rxnorm_ingredient` (name) and `rxnorm_ingredient_rxcui` (sorted,
   `;`-joined for combinations) to `/signals` rows and to `/signals/export`. Keep the DiAna
   `ingredient` column unchanged next to them.

## Keep

- EB05 and every other statistic unchanged. This adds columns; it does not regroup signals.
- The DiAna `ingredient` column and the per-drug `/signals` behaviour.
- Unmapped strings stay in the output with blank RxNorm columns, never dropped.

## Verify (live)

- Lantus, Toujeo, Basaglar and "insulin glargine" rows all carry `rxnorm_ingredient =
  "insulin glargine"` (274783). Insulin lispro rows do not.
- Entresto and "sacubitril valsartan" rows carry both sacubitril and valsartan.
- No glargine-named string maps to inulin or galactose.
- Post the coverage numbers from Ask 3 and the fuzzy-row count from Ask 2 on this PR.
- `/signals?drug=tzield` still returns 200, and its existing fields are unchanged.

## Out of scope

- Re-running signal detection at ingredient level (the substance parquet is separate work).
- Portfolio's switch to joining on `rxnorm_ingredient`. This seat does it after deploy.
- Route/dosage-form pooling (Nasacort nasal vs triamcinolone injection). That is Portfolio's
  open question. The IN rollup will pool routes, which is expected.
