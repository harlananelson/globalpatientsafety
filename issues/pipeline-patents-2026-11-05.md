<!-- role:career -->
# Slice: patent data on /pipeline (sponsor page)

**Ask (Harlan, 2026-11-05):** add patent information to GPS. Build it like `/pipeline`, which already pulls ClinicalTrials.gov trials by sponsor.

## Sources (free, public APIs)
- **USPTO PatentsView API** (search.patentsview.org): patents by assignee, CPC codes, inventors, and forward/backward citations.
- **FDA Orange Book** data files: patent numbers and expiry dates for approved drug products, plus exclusivity.

## Deliverable
1. `/pipeline?sponsor=<company>` gets a Patents section: patent count by year, top CPC classes, most-cited patents, and Orange Book patents with expiry dates for the sponsor's approved drugs.
2. `GET /pipeline/patents?sponsor=` JSON, documented in `/api`, `/api.md`, and openapi.json.
3. New MCP tool `get_patents` on https://faers.mobi/mcp.
4. Same AI-access treatment as every page (.md copy, llms.txt entry, sitemap).
5. Map assignee names the same way as the lead-sponsor matching (subsidiaries are listed under the parent company).

## Live bars (I verify after deploy)
- Pfizer and Sanofi each return a non-zero patent count and at least one Orange Book patent with an expiry date.
- `get_patents` appears in MCP `tools/list`.
- Usual rule: push before deploy, put the commit SHA in the deploy note, and the live build header matches origin/main.

## Caveats to show on the page
Patent counts measure filing activity, not drug value. Orange Book listings cover only approved products.
