# OpenAPI application/pdf for format=pdf

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#55 llms.txt / chatgpt.md document format=pdf. Do not pile this onto #55.

## Problem

Live https://faers.mobi/openapi.json already lists `pdf` in the format enum, but GET /signals 200 `content` is only `application/json`, `text/markdown`, and `text/csv`. Path description and examples omit `format=pdf`. ChatGPT Actions will not offer the PDF.

## Wanted

1. Add `application/pdf` to GET /signals 200 content (binary/Typst PDF; same brief as `format=brief`; needs `drug=`).
2. Update path/operation description + examples to mention `format=pdf` (pair with the existing brief example).
3. Keep the format param description in sync if needed.

No new compute. No billing / pay gate.

## Done when

- https://faers.mobi/openapi.json 200 content includes `application/pdf`.
- Description/examples mention `format=pdf`. Schema still validates. Deploy note with the schema URL.

## Out of scope

Pay gate, Stripe, site chat box, new `/signals` compute, merging this GPS PR.
