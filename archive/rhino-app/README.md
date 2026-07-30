# Retired Rhino/Shiny portal (archived 2026-07-30)

The interactive Rhino/Shiny portal that once served globalpatientsafety.com. It is
**not deployed and not maintained**. Production for this domain is the static site
built by `scripts/build_static_site.R` and served from disk by nginx at
`/var/www/globalpatientsafety/`.

## Why it was archived

Between 2026-07-08 and 2026-07-29 four consecutive weekly agent reviews (PRs #2, #4,
#6, #8) re-reported bugs in this app — a featured article with no view module, tool
cards out of sync with shipped HTML — while the app itself served no traffic. PR #9
repaired them in place, which fixed the symptom and left the cause: a dead surface
that still looked live to any reviewer, human or agent. Archiving it removes the
surface rather than repairing it again.

See `DECISION_LOG.md`, entries dated 2026-07-30.

## What is here

| Path | Was |
|------|-----|
| `app/main.R` | Shiny entry point — hero, tool cards, article tabs, `.ARTICLE_MODULES` |
| `app/view/*.R` | `box` view modules: portal cards, article index, per-article iframes |
| `app/js/`, `app/styles/` | Rhino-managed JS and Sass sources |
| `app.R`, `rhino.yml`, `config.yml` | Rhino/shinyApp entry and config |
| `dependencies.R` | packrat/rsconnect dependency shim (`rhino`, `treesitter`) |
| `tests/` | testthat unit tests and the Cypress end-to-end suite |

## What deliberately stayed in the live tree

These live under `app/` but belong to the **static site**, not to this app:

- `app/logic/articles.R` (`ARTICLES`) and `app/logic/tools.R` (`TOOLS`) — the
  registries `build_static_site.R` reads as its single source of truth.
- `app/static/*.html` — Quarto-rendered article and standalone-page HTML, the
  builder's input.

Do not move these into the archive; the production build reads them by path.

## Restoring it

`git mv` the contents back to the repo root (`app/view/`, `app/main.R`, `app.R`,
`rhino.yml`, `config.yml`, `dependencies.R`, `tests/`), restore the `main` job that
was removed from `.github/workflows/site-checks.yml` (see the pre-2026-07-30 version
of `rhino-test.yml` in history), and revert `.renvignore` to `!dependencies.R`.

Note that the CI job was already failing for weeks before it was removed: `renv.lock`
pins versions Posit PPM's rolling `jammy/latest` no longer serves, which is why the
old job pinned a dated PPM snapshot. Expect to re-pin that date if you revive it.
