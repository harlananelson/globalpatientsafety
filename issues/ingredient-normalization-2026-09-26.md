# Ingredient grouping + medication-error flag on `GET /signals`

Handshake only. Do not merge. Implement in `harlananelson/faers-mobi` (`/projects/faers-mobi/`). Deploy under standing permission when green, then post a deploy note with `<!-- role:linux -->` and sample curls. No pay gate (parked, #68): no keys, no billing.

Stats stay the authoritative layer. Every output remains a hypothesis from spontaneous reports, not causation. **Do not re-derive or invent new math in the API layer** (see "Statistical rules" below).

Motivation: an LLM-generated GLP-1 report built on these rows attributed blinded-trial and compounded buckets to the drugs themselves. The API made that easy: the raw FAERS string is not labeled, and the top rows by EB05 are tiny odd groups.

## Evidence (Career, live 2026-09-26 ~9 PM ET)

Build `api-db887b090897 src-c188e2e`, `X-FAERS-Through: 2025Q4`.

Query: `GET https://faers.mobi/signals?drug=<d>&indication=hide&low_info=hide&sort=eb05&order=desc&limit=8`

### Problem 1: `drug=` substring-matches raw FAERS strings

One ingredient splits into many rows, and tiny odd groups (blinded trial products, compounded combinations, pen/strength variants) rank first by EB05. Variant strings also get `novel="?"` because the label lookup fails on them, even when the ingredient label exists.

**semaglutide** (`X-Total-Count: 2541`)

| # | drug (raw FAERS string) | event | n | EB05 | novel |
|---|---|---|---|---|---|
| 1 | `semaglutide b ml pds290` | Cholecystitis chronic | 24 | 2611 | ? |
| 2 | `semaglutide b ml pds290` | Bile duct stone | 40 | 2557.6 | ? |
| 3 | `semaglutide semaglutide inj soln pen` | Pancreatic mass | 8 | 1734.3 | ? |
| 4 | `semaglutide b ml pds290` | Cholecystitis acute | 68 | 1506.2 | ? |
| 5 | `methylcobalamin semaglutide` | Salivary gland mass | 4 | 875.4 | ? |
| 6 | `methylcobalamin semaglutide` | Noninfective sialoadenitis | 4 | 869 | ? |
| 7 | `semaglutide` | Cholecystitis acute | 147 | 849.9 | known |
| 8 | `semaglutide b ml pds290` | Cholelithiasis migration | 4 | 838.6 | ? |

Plain `semaglutide` first appears at row 7. `b ml pds290` looks like a blinded trial product; `methylcobalamin semaglutide` is compounded.

**tirzepatide** (`X-Total-Count: 1015`)

| # | drug (raw FAERS string) | event | n | EB05 | novel |
|---|---|---|---|---|---|
| 1 | `tirzepatide` | Starvation ketoacidosis | 28 | 822.8 | novel |
| 2 | `tirzepatide` | Thrombotic thrombocytopenic purpura | 8 | 665 | novel |
| 3 | `methylcobalamin tirzepatide` | Allodynia | 4 | 319.6 | ? |
| 4 | `mounjaro` | Product name confusion | 1 | 263.2 | novel |
| 5 | `zepbound` | Accidental underdose | 7741 | 189.8 | novel |
| 6 | `tirzepatide` | Varices oesophageal | 8 | 145.7 | novel |
| 7 | `levocarnitine tirzepatide` | Saliva altered | 3 | 140.7 | ? |
| 8 | `tirzepatide` | Euglycaemic diabetic ketoacidosis | 36 | 134 | novel |

**liraglutide** (`X-Total-Count: 1488`)

| # | drug (raw FAERS string) | event | n | EB05 | novel |
|---|---|---|---|---|---|
| 1 | `liraglutide flexpen` | Medullary thyroid cancer | 4 | 767.7 | ? |
| 2 | `liraglutide` | Breast necrosis | 8 | 674 | ? |
| 3 | `saxenda` | Lack of satiety | 32 | 601.8 | ? |
| 4 | `saxenda` | Weight loss poor | 721 | 534.9 | ? |
| 5 | `saxenda` | Perforation bile duct | 8 | 448.2 | ? |
| 6 | `blinded liraglutide ml pds290` | Biliary colic | 4 | 406.8 | ? |
| 7 | `victoza` | Pancreatic carcinoma metastatic | 276 | 375 | ? |
| 8 | `liraglutide` | Peripheral artery dissection | 4 | 322.9 | ? |

Note: here even plain `liraglutide` rows are `?`, so the label lookup for liraglutide needs checking too.

**dulaglutide** (`X-Total-Count: 838`)

| # | drug (raw FAERS string) | event | n | EB05 | novel |
|---|---|---|---|---|---|
| 1 | `dulaglutide` | Hepatobiliary cancer | 4 | 211.2 | novel |
| 2 | `dulaglutide` | Ketoacidosis | 16 | 122.5 | novel |
| 3 | `dulaglutide` | Pancreatitis necrotising | 20 | 121.1 | known |
| 4 | `trulicity` | Accidental underdose | 8850 | 120.3 | novel |
| 5 | `dulaglutide` | Euglycaemic diabetic ketoacidosis | 25 | 98.8 | novel |
| 6 | `trulicity` | Impaired gastric emptying | 2513 | 98.8 | novel |
| 7 | `trulicity` | Accidental overdose | 6917 | 70.8 | novel |
| 8 | `trulicity` | Extra dose administered | 11598 | 69.7 | novel |

Brand queries already partly resolve: `drug=ozempic` returns rows labeled `semaglutide` (Cholecystitis acute n=147 EB05 849.9 known). Keep that as a regression check.

### Problem 2: medication-error / product-use terms are unflagged

They rank among the pharmacological signals, all `novel`, `low_info=false`. Examples from the same query at `limit=100`:

- dulaglutide: `trulicity` Accidental underdose n=8850 (#4), Accidental overdose n=6917 (#7), Extra dose administered n=11598 (#8), Incorrect dose administered n=18223 (#29), Wrong patient received product n=359 (#50)
- tirzepatide: `mounjaro` Product name confusion n=1 (#4), `zepbound` Accidental underdose n=7741 (#5), `zepbound` Intercepted product dispensing error n=553 (#11), `mounjaro` Incorrect dose administered n=57036 (#23)
- semaglutide: `semaglutide` Counterfeit product administered n=400 (#9), `wegovy` Product communication issue n=795 (#23), `ozempic` Product dose confusion n=130 (#66)

### Related: `format=class` and `format=brief` inherit the string problem

- `GET /signals?drug=semaglutide&format=class` → `n_class_substances: 6`, `n_peer_drugs: 14`, `class_wide_hint: "14 drugs in Glucagon-like peptide-1 (GLP-1) analogues flag top events (threshold 5)"`. The peers list contains raw strings `bydureon, bydureon bcise, byetta, dulaglutide, liraglutide, liraglutide flexpen, lixisenatide, ozempic, rybelsus, saxenda, trulicity, victoza`. That is 5 distinct ingredients, and **`ozempic` and `rybelsus` (semaglutide itself) are counted as peers of semaglutide**. Focal rows are the `b ml pds290` / `inj soln pen` strings.
- `GET /signals?drug=semaglutide&indication=hide&low_info=hide&format=brief` → "3,272 pairs · 21 drugs … Top EWMA EB05: Cholecystitis chronic (2611.0)". "21 drugs" counts raw strings, the top EB05 is the blinded `b ml pds290` row shown without its string, and the brief does not say which filters were applied or what was omitted.

## Asks (acceptance bars, all checkable live)

### 1. Ingredient labeling, `product_type`, and an explicit ingredient view

Map raw drug strings to active ingredient(s): brand → ingredient (Ozempic/Wegovy/Rybelsus → semaglutide, Mounjaro/Zepbound → tirzepatide, Victoza/Saxenda → liraglutide, Trulicity → dulaglutide), strip device/pen/strength suffixes. Use RxNorm/RxNav or an existing normalization table on the box; implementer's choice.

Every row (list, class focal/peers, brief source rows) carries:

| field | meaning |
|---|---|
| `reported_drug` | the raw FAERS string, unchanged. Shown prominently in top results (brief, class, UI), not only in JSON. Keep `drug` as-is for backward compatibility. |
| `ingredient` | normalized active ingredient(s); for combinations, all ingredients (e.g. `methylcobalamin+semaglutide`) |
| `product_type` | `single` \| `combination` \| `trial_uncertain` |

- `single`: one active ingredient (brand, generic, pen/strength variants).
- `combination`: more than one ingredient, including compounded mixes (`methylcobalamin semaglutide`, `levocarnitine tirzepatide`).
- `trial_uncertain`: blinded/trial product codes or strings that cannot be mapped with confidence (`semaglutide b ml pds290`, `blinded liraglutide ml pds290`).

**Combination and trial/uncertain strings stay separately identified and are never counted as ordinary semaglutide or tirzepatide**, in any view, count, or brief.

Filter: `product_type=single` (or `product_type=` accepting a comma list), consistent with the existing opt-in `indication=hide` / `low_info=hide` pattern. Default ranking/order unchanged in slice 1. Add the new params to the unknown-param/format validation (#86) if relevant.

Ingredient-level results are an **explicit view**, e.g. `group=ingredient`, not a silent merge. Default stays the raw-string rows (`group=raw` behavior) for backward compatibility. `group=ingredient` only lands with slice 2 (below).

Label/novel lookup uses `ingredient` for `single` rows, so plain-ingredient and brand/variant rows get `known`/`novel` instead of `?` when a label exists.

**Bar (slice 1):**
- `drug=semaglutide&indication=hide&low_info=hide&product_type=single&sort=eb05&order=desc&limit=8` shows no `b ml pds290` or `methylcobalamin` rows.
- Unfiltered, those rows are still present and carry `product_type: trial_uncertain` / `combination` and their `reported_drug`.
- `drug=ozempic` still resolves to semaglutide rows (`ingredient: semaglutide`).
- `novel` is `known`/`novel`, not `?`, for `single` rows when an ingredient label exists (check semaglutide, liraglutide, `saxenda`, `victoza`).

### Statistical rules (forbidden shortcuts)

- Ingredient-level `n`, EB05/EBGM, and trend **must be recomputed from deduplicated underlying cases and quarterly counts** on the stats pipeline (3090). Say so in the deploy note.
- **Summing existing `n` across strings, or averaging/maxing EB05 across strings, is invalid and forbidden.** The same case can appear under several strings, and EB05 is not additive.
- Until the recompute lands, **slice 1 = the labeled fields (`reported_drug`, `ingredient`, `product_type`) + the `product_type` filter**. Slice 2 = recomputed ingredient-level stats behind `group=ingredient`.

### 2. `medication_error` flag

Boolean `medication_error` on every row: MedDRA medication-error / product-issue PTs (e.g. HLGT "Medication errors and other product use errors and issues" and HLGT "Product issues"; use the MedDRA hierarchy already on the box, don't hand-list). Filter `medication_error=hide`, same opt-in pattern. These rows **stay in the unfiltered API**; the flag does not change default ranking.

**Bar:**
- `drug=dulaglutide&indication=hide&low_info=hide&medication_error=hide&sort=eb05&order=desc` has no Accidental underdose, Accidental overdose, Extra dose administered, or Incorrect dose administered rows.
- `drug=tirzepatide&…&medication_error=hide` has no Product name confusion / Intercepted product dispensing error rows.
- Without the filter, `trulicity` Accidental underdose n=8850 is still there with `medication_error: true`.

### 3. Briefs state filters and omissions

`format=brief` and `format=pdf` state every filter applied (`indication`, `low_info`, `product_type`, `medication_error`, `group`) and every row omitted, or the count of omitted rows by reason (e.g. "omitted: 12 trial_uncertain, 4 combination, 31 medication_error"). The brief's drug/pair counts say whether they count raw strings or ingredients, and top rows show `reported_drug` when it differs from the ingredient.

**Bar:** the semaglutide brief with filters names them and gives omitted counts; it no longer reports "21 drugs" unqualified or attributes the `b ml pds290` EB05 2611 to semaglutide without the string.

### 4. `format=class` wording and threshold

The class-wide count counts **distinct ingredients**, not brand or variant strings. The focal ingredient's own brands (`ozempic`, `rybelsus` for semaglutide) are never peers. Re-check the threshold ("threshold 5") against distinct-ingredient counts (the class has 6 substances), and make the hint wording say what is counted.

**Bar:** `drug=semaglutide&format=class` has no semaglutide brands in `peers`, and `n_peer_drugs` / hint count ingredients (or a new `n_peer_ingredients` field is added and the hint uses it).

### 5. Docs

`/api.md`, `openapi.json`, `/mcp.md`, and `llms.txt` get one short paragraph each for `reported_drug`, `ingredient`, `product_type`, and `medication_error`, plus the `product_type=`, `medication_error=hide`, and `group=` params, and the statistical rule (no summing n / averaging EB05 across strings).

### 6. Monitor

Add one check to `scripts/monitor_faers_mobi.sh` (faers-mobi), or suggest one, e.g.:
- `semaglutide&…&product_type=single` top row has `product_type: single`, and
- `dulaglutide&…&medication_error=hide` top 8 has no `medication_error: true` rows.

## Keep

- Default `GET /signals?drug=` order and raw-string rows (backward compatible)
- Existing `indication=hide` / `low_info=hide`
- tzield×Nausea default n=319
- No pay gate, no new statistics computed in the API layer

## Out of scope

- Causality claims; outputs stay hypotheses
- Summing/averaging stats across strings (forbidden, see above)
- Stripe / API keys
- Rewriting the external GLP-1 report

## Roles

- **Career:** this ticket; re-run the live bars after deploy.
- **Linux:** implement in `harlananelson/faers-mobi`, deploy under standing permission, post deploy note with `<!-- role:linux -->` stating which slice landed and whether the 3090 recompute is still pending.

Refs: #81 (indication/low_info flags), #86 (unknown format 400), #68 (pay parked).
