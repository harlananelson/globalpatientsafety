# Pay segments and a path to $200k/year

Design note. **Do not implement Stripe, API keys, or a pay gate from this file.** Not a faers-mobi slice. Do not merge this GPS PR as site code. Pay gate stays parked until Harlan asks.

Parked 2026-09-13 after Harlan asked to segment individuals / orphan / mid / large / generic, file it, and sketch how to reach $200k/year with AI doing most engineering and **clinical-type people** as the human seats.

## Who pays (account, not molecule)

Do not discount by orphan designation on the drug. Tzield is orphan; Sanofi is large pharma.

| Account | Year-1 price | What they get |
|---------|--------------|---------------|
| Individuals (people, students, journalists, personal ChatGPT) | $0 | Full public `GET /signals`, brief, PDF. No key. |
| Orphan / rare-disease biotech | $0 public, or ~$100–200/mo named key | Small portfolio. Public-health carve-out on the free API is fine. |
| Generic MAH | ~$250–500/mo | Volume / many SKUs, company key. |
| Mid pharma / CRO | ~$500–2,000/mo | Profiling, class, briefs. Check they can write without a 6-month RFP. |
| Large pharma | ~$2–5k/mo or ~$25–50k/yr | Automated / agent use + SLA. Not a replacement for Argus. |

Gate when it ships: one account/quota tool (`402`, who should pay, upgrade URL). Signal tools stay stats-only. Acting LLMs use the **company’s** key. Do not put an API-key header on every public `/signals` hit on day one. Do not add a 100 req/day cap that punches LLM discovery.

## A mix that adds to ~$200k ARR

These are **target mixes**, not a forecast. Year-1 solo is still more like a few keys (see Career chat 2026-09-13). $200k is the next altitude, not month 12 by default.

**Mix A — balanced (~$196k)**

- 2 large @ $3k/mo → $72k
- 6 mid @ $1k/mo → $72k
- 8 generic @ $350/mo → $33.6k
- 10 orphan keys @ $150/mo → $18k
- **26 paying accounts**

**Mix B — a few large**

- 4 large @ $50k/yr → $200k  
  Slow. Procurement.

**Mix C — mid-heavy**

- 14 mid @ $1,200/mo → $202k  
  More logos, faster if the key is self-serve.

Keep `llms.txt` / public `/signals` / `format=brief` free. That is acquisition, not the $200k.

## How many workers

$200k ARR **cannot** carry a full-time US PV scientist as payroll plus a founder salary. Published US bands (2026): Glassdoor PV scientist about $105–185k total (median ~$139k, n=42); Amgen senior PV scientist posting $141–190k; specialist guides often $70–100k. One FTE eats the year.

Traditional SaaS used to cite ~$200k revenue per employee at much larger scale. At this size, with AI writing the code, the honest headcount is:

| Seat | Count | Role |
|------|-------|------|
| Founder (Harlan) | 1 | Product, first logos, GPS |
| AI engineering | 0 new humans | Career ↔ Linux already shipping faers.mobi |
| Clinical | **1 fractional, not 1 FTE** | Pharmacist / safety scientist / ex-QPPV-adjacent. Outreach to mid/generic/orphan safety teams. Answer “is this a real signal” on sales calls. Maybe 10–20 hrs/month at the start. |
| Medical director / full sales AE | **0** | A safety physician or AE hire is a $200k+ decision. After $200k, not to get there. |

So: **one human clinical contractor + you + the existing agents.** Not a clinical department.

The bottleneck to $200k is conversations with safety teams, not more `/signals` formats.

## Do not do from this note

- Stripe / Checkout / API keys / rate limits
- New Plumber REST layer
- `POST /alerts`
- VigiBase
- Leftover-sentence docs PRs
- Hiring a full-time PV scientist or medical director on a $200k plan
