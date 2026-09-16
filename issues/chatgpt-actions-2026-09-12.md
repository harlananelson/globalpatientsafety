# ChatGPT Actions / Custom GPT import recipe

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#47 OpenAPI 3 schema is live at https://faers.mobi/openapi.json. Do not pile this onto #47.

## Problem

`/openapi.json` exists so ChatGPT Actions can discover `/signals`. There is still no paste-ready import recipe or short system prompt, so a human has to invent the Custom GPT setup.

## Wanted

A paste-ready Custom GPT / Actions import that points at `https://faers.mobi/openapi.json`.

1. Short instructions: when to use `series` / `profile` / `class` / `brief`; always treat output as hypothesis, not causation.
2. Document the recipe in `API.md`. Optional thin public page (e.g. `/chatgpt.md`) with the same text.
3. No new compute. Schema stays as shipped in #47. No billing / pay gate.

## Done when

- Recipe is live (API.md and/or `/chatgpt.md`) and a Custom GPT can import `https://faers.mobi/openapi.json` from those instructions.
- Deploy note with those URLs.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
