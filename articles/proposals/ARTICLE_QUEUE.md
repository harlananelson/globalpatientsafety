# Article Queue — Global Patient Safety

A running backlog for the **one-article-per-week** cadence. Top of the queue is next.
When an article is drafted, move it to **Drafted / published** with its date and file.

Weekly cadence: **one article every week, published on MONDAY** (locked 2026-07-13).
**First publish: Monday 2026-07-20.** Each article gets ~one week of review on the reMarkable
before it goes live; today (2026-07-13) we hold. Drafted **interactively** with Claude —
interactive keeps data-verification in the loop (a cloud agent can't check numbers against the
local FAERS parquet). The Friday `gps-weekly-research` ideas routine feeds future picks.

**Current review backlog (4 drafts already delivered to the reMarkable `/globalpatientsafety`
folder, awaiting Harlan's approval — do NOT draft new articles until this clears):**
Carbidopa-Levodopa B6 Seizures · GLP-1 Alopecia Signal · AAV Gene Therapy Liver · Inside the AEMS
Data. Publish ~one per Monday as approved, starting 2026-07-20.
**Approval gate: every article is sent as a reMarkable Paper Pro PDF *before* publishing**
so Harlan reads and approves it on the device ahead of time; deploy happens only after approval
(`scripts/render_remarkable.sh`, see step 4 below).
Source of new ideas: the `gps-weekly-research` cloud routine (Fridays) → `articles/proposals/YYYY-MM-DD-ideas.md`.

---

## Editorial direction — methodology first (the site's distinctive lane)

Harlan is a statistician / clinical data scientist, **not an MD**, so the durable value he adds is
**pharmacovigilance methodology — how to use FDA adverse-event data correctly, and the gotchas that
trip people up** — anchored by a concrete drug/vaccine example but *not* making clinical causation
claims. Frame pieces as transferable "reading FDA data" lessons, not "drug X causes event Y."

The gotchas already surfaced (a running catalogue for a possible **"Reading FDA Adverse-Event Data"
series**):
- **Survivability ≠ causation / notoriety bias** — a signal can "survive" a whole drug class purely
  because publicity for one member spreads reporting to all; the emergence-*timing* check refutes it
  (NAION/GLP-1, queue #2). A known publication/label date is a natural experiment.
- **The raw leaderboard lies** — top-EB05 pairs are dominated by confounding-by-indication, route,
  litigation clusters, and definitional/known effects (AEMS page).
- **Signals are non-stationary** — single-quarter claims move with prescribing volume + attention;
  plot the trajectory (GLP-1 alopecia).
- **The rare severe outcome is invisible; the mechanism is loud** — look upstream of the fatal
  endpoint (carbidopa/levodopa B6; AAV liver).
- **Cherry-picking the max quarter** across a panel manufactures signals for rare-event drugs (use
  latest-quarter snapshot + trajectory, show observed counts).
- **Protopathic / reverse-causation bias** — e.g. pancreatic carcinoma on a weight-loss drug.
- **Coding/step-change artifacts** — a 1→175 single-quarter jump (Ozempic "cyclic vomiting
  syndrome") is a coding/reporting artifact, not biology.
- **Passive reports ≠ incidence; small-N EB05 needs the trajectory** before it means anything.

Most pieces already carry a methodology thread; lean into it explicitly as the through-line.

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

1. **Shingles vaccine → shingles: live (Zostavax) vs recombinant (Shingrix).** ★ verified, from
   the Attkisson monitor. VAERS. The live vaccine flags far harder for the very disease it
   prevents: **Zostavax (live) → Herpes zoster EB05 11.4 (4/4)** vs Shingrix (recombinant) EB05
   3.8 on 371 reports (4/4), latest quarter. Mechanistically clean (live-attenuated virus can
   reactivate) and a strong contrast piece. *Before drafting:* confirm no overlap with
   `articles/shingles.md` (that one did cardiac/neuro/thrombotic signals across shingles products,
   NOT zoster-as-the-outcome, so this is almost certainly new ground). *Watch:* Zostavax is largely
   phased out (older/sparser reports — pool quarters or note the era); confounding by indication
   (both given to older adults already at shingles risk). Source: Attkisson 2026-07-06 Substack →
   `attkisson-monitor.md`.

2. **When a signal "survives" the class but the calendar says notoriety — GLP-1s → NAION.**
   ★ methodology piece, analysis run + verified 2026-07-13 (full write-up:
   `naion-glp1-survivability.md`). The survivability/class check *looks* like it confirms a class
   effect (every GLP-1 but exenatide flags NAION 4/4), but the per-agent emergence timing shows
   every non-semaglutide agent ignites only *after* the July-2024 semaglutide NAION study — a
   notoriety-bias signature, not four discoveries. Transferable gotcha: survivability ≠ causation;
   always check the trajectory + a known publication/label date as a natural experiment. Absorbs the
   earlier single-drug Ozempic-NAION idea. FAERS.

3. **From FAERS to AEMS — a reproducibility check on our data foundation.**
   Explainer + reproducibility harness. Low urgency (verified 2026-07-12: AEMS is a front-end
   consolidation; the bulk quarterly FAERS extract files continue, still public, Q1 2026 posted
   2026-04-28 — no pipeline crisis). Recompute a known EB05 (e.g. the Cotton myocarditis result)
   from AEMS-era files. Source: `2026-07-10-ideas.md` #5.

4. **Trop-2 ADC neutropenia/diarrhea class check as Trodelvy goes first-line.**
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
