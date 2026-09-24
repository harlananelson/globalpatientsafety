# Pharma pipeline tracker + report

Handshake / design. **Protocol first** — Linux implements only after Career opens a thin faers-mobi (or sibling GPS) slice and Harlan confirms the host. Not pay gate. Not leftover docs.

Harlan (2026-09-24): develop a **pipeline tracker and report for each pharma**, and fold ClinicalTrials.gov in (API confirmed live).

## Product

For a named company (sponsor), show their clinical **pipeline** from ClinicalTrials.gov and produce a shareable **report**.

Primary questions a user (or LLM) should answer in one call:

- What is Sanofi / Novo / Pfizer / … currently studying?
- How many trials by phase and status?
- Which interventions (drug codes / names) and conditions?
- Optional later: which of those names already have FAERS signals on faers.mobi?

## Data source (authoritative)

**ClinicalTrials.gov API v2** — public, no key for ordinary search.

- Docs: https://clinicaltrials.gov/data-api/api  
- Probe (Career 2026-09-24):  
  `GET https://clinicaltrials.gov/api/v2/studies?query.spons=Sanofi&pageSize=1&fields=NCTId,BriefTitle,OverallStatus,Phase,LeadSponsorName,Condition,InterventionName`  
  → 200 JSON with `protocolSection` modules (nctId, briefTitle, overallStatus, phases, leadSponsor, conditions, interventions).

Do **not** scrape the HTML UI. Do **not** invent NCT ids. Soft-fail if CT.gov is down.

## Out of contract

- Causality / efficacy / “will this drug be approved”
- Clinical decision support scores
- EHR / Epic plugins
- VigiBase / EudraVigilance merges in v1
- Stripe / API keys (pay gate parked — #68)
- Training ML on trial text

Hypothesis-only language in every report: trials are registry facts; FAERS (if overlaid) remains spontaneous-report hypotheses.

## Host decision (Harlan)

**Decided 2026-09-24: Host B — globalpatientsafety.com** (marketing site + API). Not faers.mobi. Keep FAERS signal math on faers.mobi; pipeline is a GPS content/API product with optional link-out to `/signals` later.

| Option | Where | Status |
|--------|--------|--------|
| A. faers.mobi sibling path | `GET /pipeline` next to `/signals` | Not chosen |
| **B. globalpatientsafety.com** | Marketing site + API | **Chosen** |
| C. New thin service | Separate host | Not chosen |

## Slice 1 (thin, mergeable)

**Goal:** `GET /pipeline?sponsor=Sanofi` (name TBD) returns structured JSON + `format=brief` markdown.

### Query

| Param | Required | Notes |
|-------|----------|-------|
| `sponsor` | yes | Lead sponsor / company string; pass through to `query.spons` (or CT.gov’s current sponsor field). Normalize case/trim; do not fuzzy-expand to competitors. |
| `status` | no | Optional filter: RECRUITING, ACTIVE_NOT_RECRUITING, COMPLETED, … |
| `phase` | no | PHASE1 … PHASE4, EARLY_PHASE1, NA |
| `limit` | no | Default 50, max 200; paginate with CT.gov `pageToken` if exposed |
| `format` | no | `json` (default) \| `brief` \| `pdf` (pdf can wait for slice 2) |

### JSON shape (illustrative)

```json
{
  "sponsor_query": "Sanofi",
  "sponsor_matched": "Sanofi",
  "retrieved_at": "2026-09-24T21:00:00Z",
  "source": "clinicaltrials.gov/api/v2",
  "n_studies": 120,
  "by_phase": {"PHASE1": 40, "PHASE2": 35, "PHASE3": 20, "PHASE4": 5},
  "by_status": {"RECRUITING": 30, "COMPLETED": 50, "TERMINATED": 10},
  "studies": [
    {
      "nct_id": "NCT05231668",
      "title": "…",
      "status": "TERMINATED",
      "phases": ["PHASE1"],
      "conditions": ["Osteogenesis Imperfecta"],
      "interventions": ["SAR439459", "Placebo"],
      "url": "https://clinicaltrials.gov/study/NCT05231668"
    }
  ],
  "disclaimer": "Registry facts from ClinicalTrials.gov. Not efficacy or safety conclusions."
}
```

### `format=brief`

Markdown `text/plain` (same Content-Type rule as signals briefs): sponsor, counts by phase/status, top N recruiting + late-phase rows, NCT links, disclaimer. No invented efficacy language.

### Acceptance

- Live `sponsor=Sanofi` (or Harlan’s pick) returns 200 with ≥1 real NCT from CT.gov  
- Unknown sponsor → empty studies + clear `n_studies: 0` (not 500)  
- CT.gov timeout/5xx → 502/503 JSON with `source` error; never empty 200 pretending success  
- Documented on globalpatientsafety.com (API page or `/pipeline` docs); link from homepage / llms if present  
- Monitor: one check `pipeline-sponsor-sanofi` (or host equivalent)

## Slice 2 (later)

- `format=pdf` Typst report  
- Pagination / `pageToken` passthrough  
- Intervention rollup (unique drug codes)  
- Optional **FAERS overlay**: for intervention names that resolve on faers.mobi, attach top novel EB05 or link to `GET /signals?drug=` — still hypothesis-only; skip placebos / device-only arms  

## Slice 3 (tracker, not one-shot)

Standing refresh: cache sponsor snapshots nightly (respect CT.gov rate limits), expose `as_of` / freshness. Alert when a late-phase trial flips status (ties to parked paid alerts — do not build billing here).

## Linux / Career roles

- **Career:** this ticket; verify live after deploy; ping Harlan when the first sponsor report is useful  
- **Linux:** implement on chosen host; deploy when green; post deploy note with sample curl  
- **Codex:** skip frozen faers.mobi suite — this is GPS host, not `/signals`  

## Do not from this PR alone

- Merge as site code without a host + slice 1 implement PR in the code repo  
- Start Stripe / accounts  
- Scrape CT.gov HTML  
- Claim pipeline = safety signal  

Refs: GPS #93 (CT.gov maybe enricher), #68 (pay parked). Host = B (Harlan 2026-09-24).
