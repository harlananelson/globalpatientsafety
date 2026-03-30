# globalpatientsafety.com — Global Safety Metrics Dashboard

## Overview
Rhino/Shiny app for Bayesian pharmacovigilance signal detection across multiple international adverse event reporting systems. Uses the `safetysignal` R package as its statistical engine.

## Architecture
- **Framework:** Rhino (production Shiny)
- **Engine:** `safetysignal` package (2-component Gamma-Poisson)
- **Data sources:** FAERS, VAERS, MAUDE, EudraVigilance, VigiBase (WHO)
- **Domain:** globalpatientsafety.com

## Key Files
- `app/main.R` — App entry point
- `app/logic/signal_engine.R` — Wraps safetysignal for this app
- `app/view/signal_table.R` — Signal results table module

## Related Projects
- `safetysignal` — Shared Bayesian engine package
- `faers-mobi` — Vaccine-focused app
- `aers-mobi` — Drug/device-focused app
