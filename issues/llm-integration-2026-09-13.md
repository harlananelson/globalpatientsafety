# faers.mobi LLM integration

Design note. **Do not implement new `/signals` filters from this file.** Not a faers-mobi slice. Do not merge this GPS PR as site code.

Parked from Harlan’s 2026-09-13 memo (after ChatGPT still treated the Shiny table as the only interface).

## Current state

faers.mobi is already an LLM-accessible pharmacovigilance API. It does not require a new REST API or MCP layer to make the FAERS signal data available to LLMs.

The Shiny interface is only one presentation layer. The underlying signal rows are directly accessible through `GET /signals`.

Key resources:

- ChatGPT integration: https://faers.mobi/chatgpt.md
- OpenAPI: https://faers.mobi/openapi.json
- REST: https://faers.mobi/signals
- Hosted MCP: `POST https://faers.mobi/mcp`
- MCP stdio: https://faers.mobi/mcp/server.py
- Machine index: https://faers.mobi/llms.txt

## Architecture

```
ChatGPT / Claude / other LLM
        │
        ├── OpenAPI / REST
        │
        └── MCP
              │
              ▼
    faers.mobi GET /signals
              │
              ▼
    FAERS signal engine (authoritative)
```

The LLM should use these structured interfaces rather than scraping or driving the Shiny table.

## Existing query capabilities

| Need | Live |
|------|------|
| Drug signals | `GET /signals?drug=apixaban` |
| Isolated pair (AND) | `GET /signals?drug=apixaban&event=Haemorrhage` |
| Novel + thresholds | `novel=novel&min_eb05=2` (also `trend=`, `min_n=`, sort, pagination) |
| Class | `format=class` (needs drug) |
| Quarterly history | `format=series` (needs drug AND event) |
| Label / Novel cache | `format=label` (needs drug AND event) |
| Profile / brief / PDF | `format=profile` / `brief` / `pdf` (drug or event) |

## Do not grow `/signals` into a query language

Do not add query parameters merely because an LLM could use them.

A new filter should generally be exposed when:

1. The underlying attribute is stable and well-defined.
2. Filtering it server-side materially reduces data transfer or multi-call reasoning.
3. It represents a common pharmacovigilance question rather than an arbitrary analytical operation.
4. Its semantics can be represented unambiguously in OpenAPI.
5. The result remains deterministic and reproducible independently of the LLM.

Candidates **only if usage recurs** (do not implement from this note):

- `soc=`
- `min_signal_quarters=`
- `indication_confounded=`
- `max_class_coflags=`

These attributes exist in the broader engine but are not first-class `/signals` params today. A request such as “neurological semaglutide events, EB05 > 2, novel, ≥4 quarters, not indication-confounded, &lt;3 ATC4 co-flags” can already do EB05, novel/label, class, and series. The rest is not one GET.

## Design principle

The statistical engine stays authoritative. The LLM translates questions into API calls, composes results, explains them, and does not invent signals or treat them as causation.

## Bottom line

faers.mobi has already crossed from an interactive FAERS website to a machine-accessible pharmacovigilance service. The next decision is not “how do we make it LLM-usable.” It is which additional analytical dimensions earn a first-class filter while keeping `/signals` small, deterministic, and PV-focused.
