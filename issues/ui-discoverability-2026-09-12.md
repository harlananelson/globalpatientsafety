# UI discoverability (API / ChatGPT / OpenAPI / MCP)

Handshake for `/projects/faers-mobi/`. Do not merge this GPS PR. Deploy when good. Pay gate / billing is out of scope.

#48 ChatGPT Actions recipe is live at https://faers.mobi/chatgpt.md. Do not pile this onto #48.

## Problem

API.md, chatgpt.md, openapi.json, and the MCP pointer already exist, but a person on faers.mobi has to guess the URLs. The LLM path is hard to find from the UI.

## Wanted

Footer or About links on faers.mobi to:

1. `API.md`
2. `chatgpt.md`
3. `openapi.json`
4. The MCP pointer already documented in API.md

No new compute. No new endpoints. No billing / pay gate.

## Done when

- Isolated drug page (e.g. https://faers.mobi/?drug=tzield) and the home page show those links in footer or About.
- Destinations 200. Deploy note with a screenshot URL or the live page.

## Out of scope

Pay gate, Stripe, PDF/Typst, site chat box, new `/signals` formats, merging this GPS PR.
