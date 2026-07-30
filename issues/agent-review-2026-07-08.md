# Agent Review — 2026-07-08

Weekly reflection on globalpatientsafety.com (Rhino/Shiny portal). Report-only:
each proposal cites specific files/lines or DECISION_LOG entries. No files other
than this one were modified.

Context: this is the first `agent-review-*.md` (the reflection routine described
in DECISION_LOG 2026-07-02 opened no prior review file). The other two `issues/`
files (`ajax-error.md`, `signal-disconnection.md`) are triage docs for
**aers-mobi** and the signal pipeline, not the portal — not re-proposed here.

---

## 1. The featured article ("Christine Cotton") is unreachable in the portal — every "Read" path is a dead link

**Severity: high (user-facing, correctness). Highest priority this week.**

### Evidence

The Cotton article is the site's most prominent content — it is the **Featured
Article card on the Home tab** — but it was never wired into the portal app's
article-module registry. It renders only in the separately-built static site.

- `app/logic/articles.R:15-18` — `christine_cotton` is in `ARTICLES` with
  `status = "published"` and `featured = TRUE`.
- `app/main.R:31-34` — `.ARTICLE_MODULES` registers **only** `shingles` and
  `covid_vaccine`. There is no `christine_cotton` entry.
- `app/view/` contains `article_shingles.R` and `article_covid_vaccine.R` but
  **no `article_christine_cotton.R`** — the view module was never created.
- The static HTML the module would embed already exists:
  `app/static/christine_cotton.html` (1.56 MB, per DECISION_LOG 2026-06-13).
- `git show f97f343` ("Add Christine Cotton VAERS article, featured; …") added
  the `ARTICLES` row + static HTML but not the view module or the registry entry.
  The static-site build path (`build_static_site.R`) was updated; the Rhino
  portal path was not.

Runtime consequence — three dead paths:

1. **Home → "★ Featured Article" card.** `.featured_article_card()`
   (`app/main.R:74-97`) selects the featured row (= Cotton) and renders a
   "Read article →" button that fires `open_featured = "christine_cotton"`. The
   handler `observeEvent(input$open_featured, …)` (`app/main.R:279-281`) calls
   `nav_to_article("christine_cotton")` → `updateNavbarPage(…, selected =
   "article_christine_cotton")` (`app/main.R:271-274`). No tab with that value
   exists — `.build_articles_menu()` (`app/main.R:41-53`) skips the article
   because its module is `NULL` (`if (is.null(mod)) return(NULL)`). Clicking the
   featured button does nothing.
2. **Articles dropdown.** Same skip → Cotton never appears in the nav menu.
3. **"View all articles" index.** `app/view/articles.R:48` iterates over *all*
   `ARTICLES` rows, so a Cotton card *does* render, but its "Read →" button hits
   the same dead `switch_to_article("christine_cotton")` navigation.

So the single most-promoted article on the landing page is a link to nowhere in
the live Shiny app.

### Proposed change

Mirror the existing pattern exactly:

1. Add `app/view/article_christine_cotton.R` — copy `app/view/article_shingles.R`
   verbatim, changing the iframe `src` to `"static/christine_cotton.html"` and the
   `title`/`box::use` to match.
2. Register it in `.ARTICLE_MODULES` (`app/main.R:33`):
   `christine_cotton = article_christine_cotton`, and add the matching
   `box::use(app/view/article_christine_cotton, …)` import at `app/main.R:20-26`.

No changes to `ARTICLES` or the server loop are needed — both already handle the
row generically once the module exists.

### Effort estimate

~20 minutes. One new ~30-line file + two lines in `main.R`. Verify locally with
`Rscript -e 'shiny::runApp()'` and click the Home featured button.

### Risk

Very low. Additive; follows the shingles/covid_vaccine template. The only failure
mode is a wrong `src` path, caught immediately on first click. Note: this review
does not modify these files (hard rule) — this is the proposal for the follow-up PR.

---

## 2. CI ("Rhino Test") is red on every push — including the PRs the review/research routines open

**Severity: medium-high (process/trust). Stalled with a diagnosed next step.**

### Evidence

- DECISION_LOG 2026-07-07 ("Work queue") item #2: *"CI fix — Rhino Test red on
  EVERY push since ~2026-04-24 (pre-existing…). Causes: (a) CI renv restore not
  installing `rhino` (renv.lock DOES pin it), (b) `.rhino/` dir absent → Cypress
  step fails on missing `.rhino/package-lock.json`."*
- Confirmed live this session via the Actions API — the **last 8 `main` pushes
  all `conclusion=failure`**, most recent `c201da5` at 2026-07-08T02:40Z, back
  through `1704988` on 2026-07-03. Not a flake; a persistent break.
- `.github/workflows/rhino-test.yml` runs `rhino::lint_r/js/sass`,
  `rhino::build_js`, `rhino::build_sass`, `rhino::test_r`, then a Cypress e2e job
  with `working-directory: .rhino` — the two steps the log fingers.

Why it matters beyond a red badge: DECISION_LOG 2026-07-02 establishes two
autonomous loops (this reflection routine + the Friday research routine) whose
**entire output is PRs**. Every one of those PRs now shows a failing required-looking
check, which erodes the "human merge + CI is the release valve" model that section
describes. A green baseline is what makes the PR boundary meaningful.

### Proposed change

Land the two-part fix already scoped in the log:

1. **renv restore** — ensure `rhino` actually installs in CI. `renv.lock` pins it,
   so the likely culprit is the `setup-renv` cache or a missing system dependency;
   add `rhino` explicitly / clear the stale cache and confirm `rhino::…` resolves.
2. **Cypress** — the `working-directory: .rhino` job needs `.rhino/` to be
   generated first (`rhino::build_js()`/`build_sass()` create it). Either gate the
   Cypress step on a successful build or add `if: success()` chaining so it doesn't
   run against a missing `.rhino/package-lock.json`. If e2e can't be made reliable
   quickly, split it into a separate non-blocking job so lint/test stays green.

### Effort estimate

Half a day, iterating against the Actions runner (the failure is CI-environment
specific, so it needs live run-and-inspect). Low code volume, mostly YAML +
possibly one line in the renv/system-deps setup.

### Risk

Low for the repo itself (workflow-only changes; the log notes CI "does NOT block
deploy"). The real risk is time-sink: CI failures reproduce only on the runner, so
budget for 3–4 iteration cycles. Scope guard: do not silence tests to force green —
split or fix.

---

## 3. CLAUDE.md has drifted from the actual schema and tool set — it will mis-instruct the next debugging agent

**Severity: medium (correctness/consistency, self-inflicted on future automation).**

CLAUDE.md is the standing brief every routine (including this one) loads first, and
its "Debugging No Results" section is written as copy-paste R for a future agent.
Two of its factual anchors are now wrong per the DECISION_LOG's own corrections.

### Evidence

1. **`signals.parquet` schema table is wrong.** CLAUDE.md ("signals.parquet
   Schema") lists `drug_concept_id`, `drug_name`, `outcome_concept_id`,
   `outcome_name`. But DECISION_LOG 2026-04-27 ("Schema confirmation") states the
   live parquet's 28 columns include **`rxnorm_name`** (not `drug_name`) and
   **no** `*_concept_id` columns. The "Debugging No Results" snippet in CLAUDE.md
   even tells an agent to `filter(grepl(..., drug_name))` — that column does not
   exist; the query would error. `outcome_name` is correct; the drug side is not.
2. **Tool suite table omits a live tool.** CLAUDE.md's "Tool Suite" table lists 5
   entries and no VAERS app, yet `app/logic/tools.R:22-23` ships **"VAERS vaccine
   safety" as `status = "live"`** (`https://vaers.globalpatientsafety.com`), and
   `app/main.R:233-235` links it in the About tab. The canonical doc under-counts
   the live surface by one whole app.
3. **Stale paths/versions (minor).** CLAUDE.md references
   `signals_faers_v2024-12-31.parquet` and `/home/harlan/projects/...`; the
   DECISION_LOG works against `v2026-04-20`. Cosmetic, but compounds the drift.

### Proposed change

A single documentation edit to CLAUDE.md:

- Fix the schema table: `drug_name` → `rxnorm_name`; drop the `*_concept_id`
  rows (or mark them as not-present), matching DECISION_LOG 2026-04-27. Update the
  "Debugging No Results" R snippet to use `rxnorm_name`.
- Add a "VAERS vaccine safety — Live" row to the Tool Suite table so it matches
  `tools.R`.
- Refresh the example parquet version to the current `v2026-04-20` (or make it
  version-agnostic: `signals_faers_v<date>.parquet`).

### Effort estimate

~15 minutes. Docs-only, no code.

### Risk

Minimal. The only hazard is re-introducing a different inaccuracy — cross-check
each edited value against the cited DECISION_LOG entry and `tools.R` before
committing.

---

### Summary ranking

| # | Proposal | Type | Effort | Why now |
|---|----------|------|--------|---------|
| 1 | Wire the featured Cotton article into the portal | Correctness / user-facing | ~20 min | The landing page's headline content is a dead link |
| 2 | Fix red Rhino Test CI | Process / trust | ~½ day | Every autonomous PR ships with a failing check; diagnosis already in the log |
| 3 | Correct CLAUDE.md schema + tool drift | Consistency | ~15 min | The brief that steers every routine mis-names columns and omits a live app |
