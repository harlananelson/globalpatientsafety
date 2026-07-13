# Proposal: When a Signal "Survives" the Class but the Calendar Says Notoriety

**Type:** methodology piece (a "reading FDA adverse-event data" gotcha, anchored by a real signal).
**Anchor example:** GLP-1 receptor agonists → NAION (non-arteritic anterior ischaemic optic neuropathy).
**Status:** analysis run + verified 2026-07-13 (below); ready to draft as a `.qmd`.

## The methodological point (the reason to write it)

A standard move in disproportionality work is the **survivability / class check**: if drug A shows
a signal for event E, test whether the rest of the drug class shows it too. "It survives across the
class" is usually read as evidence the effect is *real* (mechanistic, class-wide) rather than a
one-drug fluke.

This piece shows that **survivability alone can be a trap.** A signal can "survive" across a whole
class purely because of **notoriety bias** — once event E is publicized for drug A, reporters start
attributing E to every drug in the class, and the disproportionality lights up everywhere. The fix
is cheap and decisive: **check the emergence *timing*.** A genuine class effect has independent,
staggered histories; a notoriety artifact has every class member igniting *after* the same
publicity event.

The transferable lessons: (1) survivability ≠ causation; (2) always plot the per-drug signal
*trajectory*, not just the current-quarter cross-section; (3) a known publication/label date is a
natural experiment — signals that all start the quarter after it are reporting-driven; (4) tiny-N
"signals" (EB05 high on <15 reports) need the trajectory before they mean anything.

## The verified analysis (FAERS through 2025Q4, latest-quarter cross-section)

NAION PT cluster (optic ischaemic neuropathy / non-arteritic ischaemic optic neuropathy):

| Agent | Reports | EB05 | Methods | Note |
|---|---|---|---|---|
| **semaglutide** (Ozempic/Wegovy/Rybelsus) | 289 | **39.4** | 4/4 | dominant anchor |
| semaglutide oral (Rybelsus alone) | 20 | 23.1 | 4/4 | |
| liraglutide (Victoza/Saxenda) | 11 | 20.4 | 4/4 | high EB05 on ~2-report top PT — small-N |
| tirzepatide (Mounjaro/Zepbound) | 12 | 8.2 | 4/4 | weak |
| dulaglutide (Trulicity) | 13 | 4.7 | 4/4 | weak |
| exenatide (Byetta/Bydureon) | 0 | — | none | older, low current volume |

**Cross-section verdict:** the signal "survives" — every agent but exenatide flags 4/4. Looks like
a class effect.

**Emergence timing (the refutation).** Per-agent EB05(n) by quarter — all essentially zero before
2024Q3, then igniting 2024Q4+:

- ozempic: 2024Q4 28(44) → 2025Q1 47(85) → Q2 50(140) → Q3 38(229) → Q4 39(287)
- wegovy: 2024Q4 53(27) → 2025Q1 73(41) → Q2 71(65) → Q3 39(79) → Q4 39(98)
- mounjaro: 2024Q4 1(4) → … → 2025Q4 5(55)  (lagging rise)
- trulicity: nothing until 2025Q2 1(2) → Q4 5(13)
- victoza: flat, n1–2 throughout (EB05 20 rides on ~2 reports)

The **July 2024** *JAMA Ophthalmology* study (Hathaway et al.) linked **semaglutide** to NAION.
Every *non-semaglutide* agent's signal appears only **after** that — no independent early history,
tiny counts. That is the notoriety-bias signature, not four discoveries.

**Honest read:** real, semaglutide-anchored signal (EB05 39 on 289 reports); the class-wide
"survival" is largely reporting-attention contamination; a GLP-1 *class* NAION effect is **not
established** by this data. Exenatide's silence (no publicity overlap, low use) fits.

## Draft plan

Model on `christine-cotton-vaers.qmd` (inline R, fixed rule, callouts). Structure: the survivability
move → the cross-section table (looks like a class effect) → the trajectory small-multiples (the
reveal) → the July-2024 study as the natural-experiment date → the general gotcha + the 4 lessons
above. Confounders: exposure-volume differences across agents; NAION baseline higher in the diabetic
population (indication); small-N for the minor agents. Absorbs the earlier single-drug Ozempic-NAION
idea — the class + timing version is strictly better.

## Data provenance

`signals_faers_v2026-07-08.parquet`, drug = brand/INN strings, NAION PT cluster as above. Run from
outside the repo dir (renv shadows the nix arrow). Verify pairs before drafting (queue step 2).
