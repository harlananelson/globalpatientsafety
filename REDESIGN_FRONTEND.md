# globalpatientsafety.com — Product Design Specification

**Status:** Draft — 2026-05-03  
**Author:** Harlan A. Nelson

---

## 1. Brand

**Global Patient Safety** is the top-level brand. Sub-products (faers.mobi, aers.mobi, vaers.globalpatientsafety.com) are delivery mechanisms, not independent identities. All public-facing presence lives under globalpatientsafety.com.

**Tagline:** "Know before it becomes a headline."

**Repos:** faers-pipeline, signal-compute, faers-mobi, aers-mobi are now **private**. `safetysignal` (R package) stays public as a methodology trust signal. `globalpatientsafety` (portal) stays public as the marketing face.

---

## 2. Three Audiences, Three Landing Pages

The site serves three distinct audiences. Each gets its own landing page reachable from the top nav. The root `/` defaults to the patient page — widest audience, lowest technical bar.

| URL | Audience | Headline |
|---|---|---|
| `/` (or `/for/patients`) | Patients / caregivers | "Understand the safety signals in your medications" |
| `/for/researchers` | Pharmacovigilance researchers, clinicians, data scientists | "35 years of FDA and CDC adverse-event signals, precomputed" |
| `/for/pharma` | Pharmaceutical companies, CROs, regulatory affairs | "Automated portfolio signal surveillance" |

Each page has the same nav and footer but a completely different hero, body, and CTA.

---

## 3. Patient Landing Page (Build First)

### Goal

A patient enters their medication list and receives a plain-English signal report — free, no account, no stored history.

### Free tier constraints

- **No account required.** Zero friction to first value.
- **No query history stored.** The drug list is used only to generate the report in the current session and then discarded. This is not a HIPAA-relevant interaction (a drug name alone is not PHI), but avoiding storage keeps the privacy posture simple and honest.
- **No tracking of the user's drug list** beyond the session. Standard anonymous analytics (page views, button clicks) are fine; linking drug lists to sessions is not.
- **Future:** if HIPAA-compliant account storage becomes feasible, offer opt-in history as a free feature for registered users. Paid tier adds functionality on top of the free tier, not a paywall on the core report.

### Page structure

```
Nav
  Global Patient Safety | For Researchers | For Pharma | [GitHub: safetysignal]

Hero
  ┌────────────────────────────────────────────────────────┐
  │                                                        │
  │  Understand the safety          What is this?          │
  │  signals in your medications.                          │
  │                                 We analyze 35 years    │
  │  Free. No account. No           of FDA adverse-event   │
  │  stored history.                reports using          │
  │                                 Bayesian statistics    │
  │  [Enter your medications ↓]     to find drug–event     │
  │                                 patterns your doctor   │
  │                                 may want to know about.│
  └────────────────────────────────────────────────────────┘

Medication input
  ┌────────────────────────────────────────────────────────┐
  │  Your medications                                      │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │  Start typing a drug name...                  🔍 │  │
  │  └──────────────────────────────────────────────────┘  │
  │  [+ Add another medication]                            │
  │                                                        │
  │  [See safety signals →]                                │
  └────────────────────────────────────────────────────────┘

Results (shown after submit, same page)
  ┌────────────────────────────────────────────────────────┐
  │  Safety signals for: metformin, lisinopril             │
  │                                                        │
  │  metformin                                             │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │ ● Vitamin B12 deficiency    Known on label        │  │
  │  │ ● Lactic acidosis           Known on label        │  │
  │  │ ● Diarrhea                  Known on label        │  │
  │  └──────────────────────────────────────────────────┘  │
  │  lisinopril                                            │
  │  ┌──────────────────────────────────────────────────┐  │
  │  │ ● Angioedema                Known on label  ⚠     │  │
  │  │ ● Cough                     Known on label        │  │
  │  └──────────────────────────────────────────────────┘  │
  │                                                        │
  │  [Download AI prompt]  [Get AI report — $X.XX]         │
  │                                                        │
  │  ℹ These are statistical patterns in spontaneous       │
  │    reporting data, not evidence of causation.          │
  └────────────────────────────────────────────────────────┘

How it works (below the fold)
  Step 1  Enter your medications
  Step 2  We search 2.2 million drug–event signal pairs
  Step 3  You get a plain-English summary — free, no account

Trust section
  Data source: FDA FAERS (2018–2024) + CDC VAERS (1990–2025) + AERS (2004–2012)
  Method: Bayesian disproportionality (GPS/EBGM) — same method used by FDA and EMA
  Updated: quarterly
  Code: safetysignal R package (open source)

Disclaimer strip
Footer
```

### Signals display — plain-language design

MedDRA Preferred Terms are clinical jargon. The patient display layer should translate:

| MedDRA PT | Plain-language label |
|---|---|
| Angioedema | Severe swelling (angioedema) |
| Acute myocardial infarction | Heart attack |
| Renal failure | Kidney failure |
| Haemorrhage | Bleeding |
| Rhabdomyolysis | Muscle breakdown (rhabdomyolysis) |

Strategy: maintain a small curated translation table for the 500 most common signal PTs. Where no translation exists, show the MedDRA PT as-is with a tooltip. Build the table incrementally — don't block launch on completing it.

### Result severity indicators

Three visual tiers in the results list, communicated by color dot and label (no numbers — patients don't have the context to interpret EB05):

| Tier | Condition | Display |
|---|---|---|
| Known | On the drug's FDA label | Grey dot, "Known side effect" |
| Watch | Novel signal, EB05 2–4 | Amber dot, "Flagged — ask your doctor" |
| Strong | Novel signal, EB05 > 4 | Red dot, "Strong signal — discuss with your doctor" |

The "novel" distinction (not on label) is the key value the platform adds over reading the drug package insert. Make it visible.

---

## 4. Researcher Landing Page

### Goal

Convince a pharmacovigilance researcher or clinician that the platform's methodology is sound, give them direct access to the tools, and surface the depth of the data.

### Page structure

```
Hero (data-forward)
  "35 years of adverse-event signals, precomputed and searchable"
  2.2M drug–event pairs · GPS/EBGM · PRR · ROR · IC · Updated quarterly
  [Open faers.mobi →]  [Open VAERS signals →]

Tool cards (live tools only — no coming-soon cards here)
  faers.mobi      aers.mobi      vaers.gps

Methodology section
  GPS/EBGM (DuMouchel 1999) · PRR (Evans 2001) · ROR · BCPNN/IC (Bate 1998)
  4-quarter rolling window · cumulative prior · EWMA smoothing
  [Read the methods →]

Pipeline transparency section
  FDA FAERS XML → faers-pipeline (R/targets) → contingency parquet
  → signal-compute (safetysignal) → signals.parquet → apps
  Updated within 48 hours of each FDA quarterly release

Data coverage table
  Source        | Years      | Reports   | Signal pairs
  FDA FAERS     | 2018–2024  | ~18M      | 2.2M
  CDC VAERS     | 1990–2025  | ~1.8M     | TBD (in progress)
  FDA AERS      | 2004–2012  | ~3M       | 995k
```

---

## 5. Pharma / Corporate Landing Page

### Goal

Establish credibility with a procurement audience and drive demo requests.

### Page structure

```
Hero
  "Automated pharmacovigilance signal surveillance for your drug portfolio"
  Know when a signal strengthens. Before the FDA does.
  [Request a demo →]

Pain point section
  Your team spends X hours per drug per quarter manually monitoring FAERS.
  We do it automatically, with peer-reviewed Bayesian methods, delivered
  to your inbox the day new data is released.

Features
  Portfolio definition    Track any combination of drugs, substances, or ATC classes
  Quarter delta reports   Signals that emerged, strengthened, or attenuated this quarter
  Novel signal alert      Events not on any label in your portfolio — high priority
  Export                  CSV, PDF quarterly summary, JSON for regulatory submissions
  Multi-user              Admin + analyst roles

Pricing (placeholder)
  Contact us for enterprise pricing.
  [Request a demo →]

Trust signals
  Same methods used in regulatory submissions worldwide
  Open-source safetysignal R package (auditable)
  Data: FDA public domain (FAERS, VAERS)
```

---

## 6. Navigation

All three pages share one nav bar:

```
[GPS logo]  Global Patient Safety
                                   For Patients | For Researchers | For Pharma | [Sign in]
```

- Logo links to `/` (patient page)
- "For Patients / Researchers / Pharma" are the three landing pages
- "Sign in" is a placeholder until accounts exist — can be hidden until Phase 2

---

## 7. Monetization Sequence

Build in this order. Each phase is shippable independently.

### Phase 0 — Now (this week)
- Three-page nav structure
- Patient page with medication input widget and signal results (no AI, no payment)
- Free, no account, no stored history
- Researcher page with direct links to the tool apps
- Pharma page as a "coming soon" contact form

### Phase 1 — Free AI prompt download
- After signal results are shown, offer "Download as AI prompt"
- Output: a structured `.txt` file the user loads into their own LLM
- Free, no account, no payment
- This is zero cost to operate and demonstrates AI-report value

### Phase 2 — Paid AI report
- Anthropic API call, formatted HTML report delivered on-page or by email
- Stripe one-time charge (~$4.99)
- Still no account required — Stripe handles the transaction, no persistent user data

### Phase 3 — Free accounts + history (HIPAA-compliant)
- Optional account creation
- Users can save their medication list and see how signals changed across quarters
- Free feature — the value is retention, not revenue
- Requires a data retention policy and privacy review before launch

### Phase 4 — Paid tier
- Add functionality on top of the free tier (not a paywall on the core report)
- Options: higher signal count, quarterly alert emails, access to full time-course data
- Stripe subscription

### Phase 5 — Corporate tier
- Portfolio dashboard, quarterly delta reports, multi-user, export
- Annual subscription, contact-us pricing

---

## 8. Technical Architecture for Patient Tool

The patient medication-input tool is a new piece of work — it doesn't exist yet. It needs:

| Component | What it does | Implementation |
|---|---|---|
| Drug autocomplete | Fuzzy match against DiAna vocabulary + rxnorm_name | Shiny `textInput` + server-side `updateSelectizeInput`, or a static JSON vocabulary file served to the browser |
| Signal lookup | Given drug names, query signals.parquet for matching pairs | Arrow `open_dataset()` + dplyr filter, same as faers.mobi internals |
| Results display | Plain-language signal table per drug | Shiny `renderUI` with custom HTML, not DT |
| PT translation | MedDRA PT → plain English | Small R named vector or lookup CSV |
| Session isolation | Drug list not persisted | Default Shiny behavior — no database write |
| AI prompt download | Format results as a structured `.txt` file | `downloadButton` + `downloadHandler` |

The patient tool can be built as a new tab in the globalpatientsafety Rhino app or as a standalone Shiny module deployed at `globalpatientsafety.com/check` (a second Shiny app on the same VPS).

---

## 9. Open Questions (Deferred)

1. **Plain-language PT table:** who builds the 500-term translation table? Can an LLM pre-generate it from the top signal PTs? (Likely yes — one-time batch job.)
2. **AI report format:** HTML page delivered on-screen, or `.txt` the user downloads? Start with downloadable `.txt` (simpler); upgrade to rendered HTML in Phase 2.
3. **Pharma page timing:** launch placeholder with contact form now, or wait until the product can actually serve corporate customers? Recommendation: launch the placeholder. It costs nothing and may generate inbound leads.
4. **VAERS integration in patient tool:** VAERS signals will be ready when signal-compute finishes. Include vaccine signals in the patient tool from day one? Yes — a patient may be asking about flu shots or COVID vaccines, not just drugs.
