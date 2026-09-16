# Document format=pdf in llms.txt / chatgpt.md

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#54 PDF/Typst RWE brief is live. Do not pile this onto #54.

## Problem

`format=pdf` is live and in OpenAPI, but `/llms.txt` still lists json/csv/series/profile/class/brief only, and `/chatgpt.md` Instructions/Smoke cover brief but not pdf. LLM clients will miss the download.

## Wanted

1. Update `/llms.txt` to mention `format=pdf` (optional example PDF link).
2. Update `/chatgpt.md` Instructions + Smoke for `format=pdf` (same brief as `format=brief`; needs `drug=`).
3. Touch MCP docs only if a one-liner is cheap (`rwe_brief` stays markdown; PDF is HTTP `format=pdf`).

No new compute. No billing / pay gate.

## Done when

- https://faers.mobi/llms.txt and https://faers.mobi/chatgpt.md mention `format=pdf`.
- Smoke URL example present. Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, site chat box, new `/signals` compute, merging this GPS PR.
