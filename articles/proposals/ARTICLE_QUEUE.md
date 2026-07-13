# Article Queue — Global Patient Safety

A running backlog for the **one-article-per-week** cadence. Top of the queue is next.
When an article is drafted, move it to **Drafted / published** with its date and file.

Weekly cadence: **one article every week, published on MONDAY** (locked 2026-07-13).
Drafted **interactively** with Claude (you ping me, or I remind you) — interactive keeps
data-verification in the loop (a cloud agent can't check numbers against the local FAERS parquet).
The Friday `gps-weekly-research` ideas routine feeds the pick over the weekend.
**Approval gate: every article is sent as a reMarkable Paper Pro PDF *before* publishing**
so Harlan reads and approves it on the device ahead of time; deploy happens only after approval
(`scripts/render_remarkable.sh`, see step 4 below).
Source of new ideas: the `gps-weekly-research` cloud routine (Fridays) → `articles/proposals/YYYY-MM-DD-ideas.md`.

---

## Drafted / published

| Date | Title | File | Status |
|------|-------|------|--------|
| 2026-07-21 | The Liver Is the Limit: Elevidys boxed warning is an AAV class effect | `articles/aav-gene-therapy-liver.qmd` | Drafted — pending review + render/deploy |
| 2026-07-14 | A Moving Target: the GLP-1 alopecia signal won't hold still | `articles/glp1-alopecia.qmd` | Drafted — pending review + render/deploy |
| 2026-07-12 | A Warning Built on 14 Cases: carbidopa/levodopa B6-seizure signal in FAERS | `articles/carbidopa-levodopa-b6-seizures.qmd` | Drafted — pending review + render/deploy |
| 2026-06-13 | Tested Against VAERS: Christine Cotton's Safety Claims | `articles/christine-cotton-vaers.qmd` | Published |
| — | Shingles vaccine analysis | `articles/shingles.md` | Published |

---

## Queue (next up, in order)

Ranked from the 2026-07-10 research batch (see `2026-07-10-ideas.md`), adjusted after the
carbidopa/levodopa piece and the AEMS verification (DECISION_LOG 2026-07-12).

1. **From FAERS to AEMS — a reproducibility check on our data foundation.**
   Explainer + reproducibility harness. Low urgency (verified 2026-07-12: AEMS is a front-end
   consolidation; the bulk quarterly FAERS extract files continue, still public, Q1 2026 posted
   2026-04-28 — no pipeline crisis). Recompute a known EB05 (e.g. the Cotton myocarditis result)
   from AEMS-era files. Source: `2026-07-10-ideas.md` #5.

2. **Trop-2 ADC neutropenia/diarrhea class check as Trodelvy goes first-line.**
   FAERS. Head-to-head sacituzumab govitecan vs. datopotamab deruxtecan. *Watch:* boxed-warning
   toxicities are expected cytotoxic-ADC effects, so vs.-background disproportionality is trivial;
   only the head-to-head + pre-first-line baseline is novel. Drop the tangential CD3×CD20
   citation. Lowest novelty of the batch. Source: `2026-07-10-ideas.md` #4.

### Also available (2026-07-03 batch, `2026-07-03-ideas.md`)

- Orlistat / kidney (oxalate nephropathy) — small case series → full-DB test.
- Compounded GLP-1 **dosing errors** (distinct from the alopecia endpoint above).
- Teplizumab pediatric baseline (pre-exposure single-drug baseline).
- Confounding-aware ICI endocrine methods piece.
- COVID-vaccine myocarditis resolution across eras.

---

## How a weekly article gets made

1. Pick the top queue item (or a fresher idea from the latest `gps-weekly-research` PR).
2. **Verify the data exists** in the FAERS/VAERS signals parquet before drafting — confirm the
   drug strings and PT cluster are present and carry enough reports (observed counts), so no
   number is invented. Use the latest-quarter snapshot + trajectory; show observed counts
   beside every EB05; do **not** cherry-pick max-EB05 across quarters.
3. Draft as a `.qmd` modeled on `christine-cotton-vaers.qmd`: inline R helpers so prose numbers
   can't drift from the tables; fixed rule EB05 ≥ 2.0 with ≥2 of 4 methods; explicit
   what-this-can/cannot-show + limitations callouts; confounding-by-indication stated plainly.
4. **Send the reMarkable PDF for review — BEFORE publishing** (this is the approval gate).
   Add the article's id + title to the `ARTICLE_IDS`/`TITLES` arrays in
   `scripts/render_remarkable.sh`, then
   `nix develop --command bash scripts/render_remarkable.sh --upload` renders it to a
   179.6×239.6 mm Paper Pro PDF and uploads it to the device `/globalpatientsafety` folder.
   Harlan reads + approves on the reMarkable ahead of time.
5. **On Harlan's approval:** move the item to **Drafted / published** here, then render
   (`build_static_site.R`) → deploy. **Publishing stays a manual step gated on approval**
   (autonomy stops at the PR boundary — nothing self-deploys to the live public-health site).
