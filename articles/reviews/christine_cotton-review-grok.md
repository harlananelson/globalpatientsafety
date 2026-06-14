

**Rigorous Skeptical Review of "Tested Against VAERS: Christine Cotton’s Safety Claims and the Post-Market Record"**

**Overall Assessment**  
The piece is a polished, caveat-laden advocacy document rather than a neutral pharmacovigilance analysis. It uses the recent death of Christine Cotton (framed as a heroic, non-ideological biostatistician) to revive contested criticisms of the Pfizer C4591001 trial and retrofits well-known VAERS signals to her categories. While the methodological callouts are stronger than typical "VAERS proves harm" content, the structure, selective thresholds, tone, and attribution failures create a document that implies the original authorization was based on unreliable data. This carries legal/reputational risk for a public-facing site.

### 1. SCIENTIFIC ACCURACY

**EB05 description is mostly correct but incomplete.** The callout box states:  
> "**What disproportionality measures.** EB05 quantifies how often an event is reported *for this vaccine relative to all other products in VAERS* — it is a within-database comparison, **not** a comparison against the rate of the event in the general population. A high EB05 says “reported disproportionately often within the reporting system,” not “occurs more often than background incidence.”"

This is accurate. EB05 is the lower 5th percentile of the empirical Bayesian geometric mean posterior (Gamma-Poisson Shrinker). It is *not* an incidence rate, *not* a population comparison, and does *not* equal causation. The piece correctly repeats this several times.

**However, there is statistical overreach in implementation and interpretation:**

- **Inconsistent thresholds.** Cardiac, thrombotic, and stroke tables use EB05 ≥ 2.0. The menstrual table drops to EB05 ≥ 1.5 "with ≥2 methods." No justification is given. This is classic outcome-dependent threshold adjustment. A skeptical reader sees p-hacking.
- Many listed "signals" are not clinical adverse events but procedural/diagnostic codes: "Magnetic resonance imaging heart" (EB05 3.00), "Cardiac stress test," "Cardiac function test," "Catheterisation cardiac," "Coagulation test." These likely reflect stimulated *investigation* of publicized concerns rather than novel pathology. Including them inflates the "cardiac signals" narrative.
- The claim "They are not artifacts" (referring to Cotton’s categories) overreaches. VAERS signals for myocarditis, pericarditis, and menstrual disorders were already publicly discussed and investigated by 2021–2022 by FDA/CDC, EMA, and in the literature. The article is not discovering new correspondences; it is mapping known signals onto Cotton’s prior list.
- **Consensus rule (≥2 of 4 methods)** is reasonable but the piece presents "4 methods flagged" for almost every row, suggesting the methods are highly correlated here rather than providing robust independent confirmation.

The interpretation of EB05 as a *within-database* measure is correct; the implication that this validates Cotton’s trial critique is not.

### 2. VAERS LIMITATIONS

The dedicated callout and methodology note are the strongest part of the document. They explicitly note:
- Passive/spontaneous reporting
- Stimulated/notoriety bias ("Myocarditis and menstrual changes after COVID-19 vaccination both received intense media and clinical attention")
- No denominator, no causality assessment
- "VAERS cannot, by design, separate the two" (signal vs. reporting artifact)
- "A VAERS signal does not prove causation. It identifies a statistical excess within the reporting system that warrants investigation."

**Caveats are still too weak in context.** The piece never quantifies the extreme stimulated reporting volume for COVID vaccines in VAERS (hundreds of thousands of reports in 2021 alone). It does not mention that notoriety bias was exceptionally strong for exactly the categories chosen (myocarditis/pericarditis after FDA/CDC alerts, menstrual changes after social media amplification). The repeated phrase "the categories Cotton singled out... surface as real disproportionality signals" subtly upgrades statistical reporting anomalies into validation of her substantive safety critique. The limitations are stated but not weighted proportionally to the rhetorical thrust.

### 3. FAIR ATTRIBUTION & LIABILITY (Highest Risk Area)

This is the most serious flaw. The site frequently slips from reporting Cotton’s views into asserting them in its own voice.

**Problematic sentences (quoted):**
- "Cotton’s central argument... was that Pfizer’s clinical trial **systematically obscured the safety picture**."
- "serious and severe (Grade ≥3) adverse events were more frequent in the vaccine arm than in placebo, and — her central point — that this net safety burden was never presented to regulators or the public with anything like the prominence given to the efficacy benefit."
- "**the safety data from the trial was not reliable enough to inform the benefit-risk decision that regulators made.**"
- "the instruments we used to clear these products were not built to see the events that mattered most. She was looking in the right direction."

These are presented as the site's analytical voice in a "pharmacovigilance tribute," not clearly as "Cotton argued" or "according to Cotton’s unpublished GCP assessment." The Ventavia section does better ("These remain allegations... Pfizer has disputed aspects"), as does the ovarian biodistribution parenthetical ("how to interpret that finding is contested, and it should not be overstated"). However, the overall framing endorses the narrative that the Phase 3 trial was methodologically corrupt/inadequate in ways that invalidated regulatory decisions. This is contested territory. Repeating BMJ Ventavia allegations and the "unblinding problem" without robust, repeated disclaimers exposes the site to claims it is asserting unproven allegations of trial misconduct as fact.

### 4. BALANCE & TONE

The piece avoids crude anti-vaccine rhetoric and correctly notes that the myocarditis signal is "accepted by the FDA and CDC" and that menstrual associations were later acknowledged in literature. It repeatedly says VAERS cannot confirm trial claims.

However, the **framing undermines the caveats**. The title, subtitle ("A pharmacovigilance tribute"), structure ("What Cotton Found in the Trial Data" → "What VAERS Confirms"), and conclusion ("She was looking in the right direction") create a redemption arc implying Cotton was right and regulators/trialists were misleading. The tone is respectful skepticism toward authority, not neutral pharmacovigilance. It does not discuss the broader evidence base (VSD, BEST, UK Yellow Card, Scandinavian registries, etc.) that generally supported the original benefit-risk for most populations despite rare signals.

### 5. FACTUAL CHECKS

- **Absolute risk reduction "about 0.84%"**: Correct citation to Olliaro et al. (*Lancet Microbe* 2021) for the initial short follow-up against symptomatic infection. Needs context that this was never how efficacy was primarily communicated for vaccines, and benefit-risk incorporated severe disease, hospitalization, and transmission effects.
- **Cotton’s death (June 1, 2026)**: Presented as fact. If this is accurate, fine; if relying on unverified sources, it requires citation.
- **"Global Patient Safety VAERS signal database" at faers.mobi**: The site appears to be promoting its own analytical tool. This should be declared as a potential conflict.
- The claim that the trial "did not include menstrual cycle data as a study endpoint" is accurate. The interpretation that this constituted a critical design failure is an opinion, not a fact.
- Thrombotic signals for Pfizer-BioNTech are weaker and less mechanistically supported than for adenoviral vector vaccines; the piece acknowledges this but buries it.

### 6. THE SINGLE BIGGEST PROBLEM and Top 3 Concrete Fixes

**Single Biggest Problem:**  
The article is structured and toned as a *tribute that validates Cotton’s core thesis* ("the safety data from the trial was not reliable enough to inform the benefit-risk decision regulators made") while using VAERS disproportionality signals—many of which were already known and investigated—as seemingly independent corroboration. Despite the disclaimers, the site’s own voice repeatedly endorses contested interpretations of trial misconduct, data integrity failures, and systematic obscuring of safety. This crosses from cautious signal detection into advocacy. For a public-facing "Global Patient Safety" organization, this creates material legal/reputational risk around implied endorsement of unproven claims about Pfizer’s Phase 3 trial.

**Top 3 Concrete Fixes (ranked by importance):**

1. **Rewrite for strict attribution and neutral framing.** Change headings to "Cotton’s Claims About the Trial" and "VAERS Disproportionality in Categories Cotton Highlighted." Replace or heavily qualify every sentence that reads as the site asserting "the trial systematically obscured," "safety data was not reliable enough," or "she was looking in the right direction." Add repeated disclaimers that Cotton’s GCP critique remains her interpretation, disputed by Pfizer and not adopted by major regulators. This is the legal necessity.

2. **Standardize methodology and clean the tables.** Use a single pre-specified EB05 threshold (e.g., ≥2.0) across all categories. Remove or separate procedural/diagnostic terms ("Magnetic resonance imaging heart," cardiac function tests, coagulation test) from clinical event tables. Report actual case counts and proportions alongside EB05. Explicitly state that thresholds were chosen *before* running the analysis for the menstrual section.

3. **Add substantive balance on the broader evidence base.** Include a section noting that multiple active surveillance systems, epidemiological studies, and regulator reviews (beyond VAERS) have characterized the myocarditis risk as rare and usually self-limited in young males, confirmed menstrual changes as transient for most, and generally upheld a positive benefit-risk profile for Comirnaty in prioritized groups during the relevant period. Cite those sources.

The piece shows competence in disproportionality methods and a genuine attempt at caveats. With the above changes it could become a more credible, lower-risk contribution. In its current form, it functions more as memorial advocacy than rigorous pharmacovigilance.