# Mistral improvement plan — triage (shipped / parked / maybe)

Protocol only. **Not a faers-mobi product slice.** Do not merge this GPS PR as site code. Do not implement Stripe, EHR plugins, new ML signal math, or VigiBase from this file. Pay gate stays parked until Harlan asks.

Source: Mistral comprehensive improvement plan + recursive LLM rubric, pasted into Career chat 2026-09-20. Career cut was: rubric useful as brainstorm; “current state” section is stale.

## How to read this

| Tag | Meaning |
|-----|---------|
| **shipped** | Already live on faers.mobi (or sibling GPS surface). Do not rebuild. |
| **parked** | Intentionally deferred (often monetization). Wait for Harlan. |
| **maybe** | Real product work later; one thin handshake when chosen. |
| **don't** | Wrong physics, out of contract, or leftover churn. |

Counts below are the Mistral idea table, not a roadmap commitment.

---

## 1. Data quality and coverage

| Idea | Tag | Note |
|------|-----|------|
| Real-time / daily FAERS pulls | **don't** | FDA FAERS is quarterly. “Daily” is not available honestly. Keep `Data through YYYYQn` / `X-FAERS-Through`. |
| EudraVigilance / VigiBase / Health Canada | **don't** (now) | Partnership / license / different dictionaries. Not a free API bolt-on. |
| EHR / claims (TriNetX, etc.) | **don't** | HIPAA + contracts. Wrong product shape for public `/signals`. |
| VAERS / vaccine signals | **shipped** (elsewhere) | Sibling GPS / aers.mobi lane — not a faers.mobi merge. |
| Historical pre-2012 AERS archive | **maybe** | Useful for long trends; engine + storage cost. Not next. |

---

## 2. Signal detection and analysis

| Idea | Tag | Note |
|------|-----|------|
| More stats (hierarchical Bayes, neural nets, Mendelian randomization) | **don't** | safetysignal stays authoritative. LLM explains; does not invent new math. |
| Time-stratified / quarterly trends | **shipped** | `format=series`, EWMA, trend labels, UI pair series. |
| Subgroup (age / sex / comorbidity) | **maybe** | Needs FAERS demo fields in the pipeline. Real engine work. |
| Drug–drug interaction signals | **maybe** | Co-med from FAERS; sparse and confounded. One slice when chosen. |
| Novelty score 0–100 + literature mining | **don't** (score); **shipped** (binary) | `novel` + `format=label` already. Continuous “unexpectedness” invites overclaim. |
| Class-effect analysis | **shipped** | `format=class`, `class_wide`, ATC4 peers. |

---

## 3. User experience and accessibility

| Idea | Tag | Note |
|------|-----|------|
| Interactive dashboards (Plotly/Tableau) | **shipped** (enough) | Shiny + table + series. Extra dashboard chrome is leftover UX. |
| Natural-language query UI on the site | **parked** / **don't** (v1) | External LLMs + MCP / OpenAPI is the NL layer. In-app chat is a second product. |
| Custom alert system (email on novel+rising) | **parked** | Fits paid tier (#68). Not free public spam. |
| Mobile-friendly redesign | **maybe** | Nice; not blocking LLM usefulness. |
| API batch / history / subgroup endpoints | **partial** | `/signals` + formats already; batch + subgroup wait on engine. |
| Export PDF / CSV / JSON | **shipped** | `format=pdf`, brief, JSON list/profile. |
| Multi-language UI | **don't** (now) | MedDRA / substance names are the hard part. |

---

## 4. Clinical and regulatory utility

| Idea | Tag | Note |
|------|-----|------|
| Clinical relevance score 1–10 | **don't** | Sounds like CDS. Contract is hypothesis-only; no actionability theater. |
| FDA label cross-check | **shipped** | `novel`, `format=label`, synonym guard (#85). |
| Regulatory submission templates (ICSR/PSUR) | **don't** | Wrong product; liability + format churn. |
| EHR plugin (Epic/Cerner) | **don't** | Partnership / FHIR years, not a handshake. |
| Submit FAERS reports from the site | **don't** | Out of scope; use FDA MedWatch. |
| Drug safety scorecards (drug vs drug) | **maybe** | Could be a thin brief/profile compare later; keep non-causal. |

---

## 5. Transparency and trust

| Idea | Tag | Note |
|------|-----|------|
| Methodology whitepaper | **shipped** (enough) | api.md, methods on site, evaluation rubric. Formal paper = human project. |
| Open-source pipeline | **shipped** | faers-mobi + safetysignal on GitHub. |
| User feedback button | **maybe** | Low cost; not a usefulness bar. |
| Data provenance / last-updated | **shipped** | Through-quarter in UI + API headers. |
| COI / funding page | **maybe** | One static page when monetizing. |
| Peer-reviewed validation paper | **parked** (human) | Not an agent slice. |

---

## 6. Advanced features for power users

| Idea | Tag | Note |
|------|-----|------|
| Jupyter / Binder on the site | **don't** | Hosting + abuse. Users pull JSON and use their own notebook. |
| Custom cohort builder | **maybe** | Same as subgroup / co-med. |
| Signal comparison tool | **maybe** | Thin compare of two drugs or two windows on existing formats. |
| Collaborative workspaces / accounts | **parked** | Needs auth; rides with pay gate. |
| Train custom ML on FAERS in-product | **don't** | Compute + liability + not our wedge. |
| Literature links (PubMed, etc.) | **maybe** | Optional enrich in brief; never invent citations. |

---

## 7. Performance and scalability

| Idea | Tag | Note |
|------|-----|------|
| Cache frequent queries | **maybe** | Especially brief/pdf on heavy worker (:3843). |
| Dask/Spark rewrite | **don't** | 3090 + current pipeline already computes. |
| Microservices split | **partial** | Cheap JSON (:3841) vs heavy brief/pdf already split; full k8s is premature. |
| Load testing | **maybe** | Ops, not product bar. |
| CDN for static | **maybe** | Easy win for docs/assets. |
| Monitor brief↔json agree | **shipped** (PR open) | GPS #91 — merge when ready. |

---

## 8. Monetization (from Mistral + #68)

| Idea | Tag | Note |
|------|-----|------|
| Freemium / API keys / rate limits | **parked** | See #68. Free public `/signals` + brief stay acquisition. |
| Sponsorships / grants / consulting | **parked** (human BD) | Not Linux/Career code. |
| Donations button | **don't** (priority) | Noise vs a real key. |
| Alerts as paid feature | **parked** | Same as §3 alerts. |

---

## Rubric misuse note

Mistral’s example scored Clinical Utility 2, Collaboration 1, Advanced Features 2, and claimed missing class effects / novelty / API docs. Against live faers.mobi that is wrong: class, novel/label, series, OpenAPI, MCP, and docs are up. Recalibrate any LLM rubric against **live** `GET /signals` + `api.md`, not a truncated homepage scrape.

Do **not** automate this rubric as a standing “improve the site” loop — it regenerates mega-plans and leftover PRs. Use GPS #83 three-seat loop + thin handshakes instead.

---

## What Career would open next (only if Harlan picks)

1. **Alerts** (parked with pay) — watch drug×event, email on novel+rising flip.  
2. **Subgroup or co-med** — one engine slice, not both at once.  
3. **Ops** — merge #91; optional brief cache.  
4. **Pay gate** — only when Harlan says go (#68).

Everything else stays **don't** or waits.

## Do not do from this note

- Implement any row tagged parked / don't  
- Open leftover-docs or “clinical score” handshakes  
- Start Stripe / API keys / EHR / VigiBase  
- Treat this PR as a deploy ticket for Linux
