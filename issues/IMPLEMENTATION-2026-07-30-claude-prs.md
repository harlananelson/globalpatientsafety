# Implementation of Claude weekly PRs (2026-07-30)

Branch: `fix/claude-pr-implementations`  
Source: open Claude Code PRs #2–#8 (report-only agent reviews + research ideas).

## Landed as-is (proposal / review archive)

| PR | File |
|----|------|
| #2 | `issues/agent-review-2026-07-08.md` |
| #3 | `articles/proposals/2026-07-10-ideas.md` |
| #4 | `issues/agent-review-2026-07-15.md` |
| #5 | `articles/proposals/2026-07-17-ideas.md` |
| #6 | `issues/agent-review-2026-07-22.md` |
| #7 | `articles/proposals/2026-07-24-ideas.md` |
| #8 | `issues/agent-review-2026-07-29.md` |

## Implemented fixes (deduped across agent reviews)

| Finding (reviews) | Fix |
|-------------------|-----|
| "Signal methods" card still `coming_soon` while `/methods` ships | `app/logic/tools.R` → `live`, URL `/methods`; portal/static open same-site links in-tab |
| Featured `christine_cotton` unreachable in Shiny | Added `app/view/article_christine_cotton.R` + `.ARTICLE_MODULES` entry in `app/main.R` |
| Articles index listed drafts as dead-click cards | `app/view/articles.R` filters `status == "published"` |
| AEMS page linked to draft articles → 404 | De-linked in `articles/aems-analysis.qmd` and patched `app/static/aems.html` (forthcoming) |
| Nav hardcoded `/methods` + `/aems` even if HTML missing | `build_static_site.R` emits standalone nav only when `app/static/<id>.html` exists |
| No dead-internal-link guard | `check_internal_links()` at end of static build |
| CLAUDE.md documented retired Rhino as production; wrong schema cols; missing VAERS | Rewrote architecture around static builder; schema `drug`/`event`; VAERS live |
| CI only covered retired Rhino app | Added `static-site-consistency` job + `scripts/check_site_consistency.R` (base R, `--vanilla`) |

## Out of scope (left as review notes only)

- Full renv/Cypress green on the retired Rhino job (snapshot pin already present; Cypress still depends on `.rhino/`)
- `REDESIGN_FRONTEND.md` three-audience redesign
- Novelty-filter Round 2 (sibling repos)
- Actually writing the draft FAERS analyses (carbidopa B6, GLP-1 alopecia, etc.) — proposals only

## Verify locally

```bash
Rscript --vanilla scripts/check_site_consistency.R
# optional full static rebuild (needs tibble/dplyr/stringr):
# Rscript scripts/build_static_site.R
```
