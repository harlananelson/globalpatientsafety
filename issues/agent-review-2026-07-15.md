# Agent review — 2026-07-15

Weekly reflection on globalpatientsafety.com (the portal / clearing-house repo).
Scope note: this repo's **live** front end is the static site produced by
`scripts/build_static_site.R` (deployed to `/var/www/globalpatientsafety/`), **not**
the Rhino/Shiny app under `app/`. The builder's own header records this:

> "Why static: each page is served from disk by nginx with zero R worker cost.
> The interactive Shiny app at this domain is retired in favour of the tool
> subdomains, which remain Shiny." — `scripts/build_static_site.R:17-19`

All three findings below are correctness/consistency drift between what has actually
shipped and what the code/docs claim. None are sibling-repo (faers-mobi / signal-compute)
items, which this review cannot verify from here.

No prior `issues/agent-review-*.md` files exist, so nothing is re-proposed.

---

## 1. The "Signal methods" portal card is stuck on *Coming soon*, but the page it describes (`/methods`, "Signal & Noise") is built, wired, and already in the top nav

### Evidence
- `app/logic/tools.R:24-25` — the tool registry still lists:
  ```r
  "Signal methods", "coming_soon", NA_character_,
  "Reference documentation for the four disproportionality methods implemented
   across the apps: GPS/EBGM, PRR, ROR, BCPNN/IC.",
  ```
  Because `status == "coming_soon"`, `build_static_site.R:172-174` renders this card
  greyed out (`opacity:0.55; cursor:not-allowed; onclick="return false;"`) with a
  "Coming soon" badge — un-clickable.
- That same page already exists and is live in the nav:
  - `scripts/build_static_site.R:114` — the top nav unconditionally links
    `<a class="nav-link" href="/methods">Signal &amp; Noise</a>`.
  - `scripts/build_static_site.R:348-352` — `STANDALONE_PAGES` includes
    `"methods", "Signal & Noise"`, and `build_standalone_pages()` publishes it.
  - `app/static/methods.html` exists (1.5 MB, rendered 2026-07-15) with
    `<title>Signal &amp; Noise — Reading FDA Adverse-Event Data</title>`.
  - Commit `4b923c4` — "Build /methods (Signal & Noise) landing page".
- Net effect for a visitor on the home page: the Tools grid shows a dead
  "Signal methods — Coming soon" card while the nav bar one row above links the
  very same content as a working page. The homepage actively hides shipped work.

### Proposed change
Update the `tools.R` row so the portal card and the nav agree — e.g.
`"Signal methods", "live", "/methods"` (and consider renaming to "Signal & Noise"
to match the page/nav label, or keep the descriptive name and let the tagline stand).
`tool_card_html()` already renders a live internal URL correctly, so no builder change
is needed. Rebuild + redeploy the static site.

### Effort estimate
~10 minutes (one tribble row) + a static-site rebuild.

### Risk
Low. Confirm `/methods` is intended as the public "methods reference" the card
promises (the page is the Signal & Noise methodology series — a match). If it is
meant to stay staged until the Monday cadence gate, leave the card `coming_soon`
but then also drop the `/methods` link from `site_nav()` so the two stop contradicting.

---

## 2. CLAUDE.md and the entire `app/` Rhino layer misrepresent the deployed architecture; the retired Shiny portal still carries a live-looking bug on its featured article

### Evidence
- The live front end is `scripts/build_static_site.R` (see the retirement note quoted
  at the top of this file). Yet `CLAUDE.md`'s **Architecture → Key Files** table still
  presents the Shiny app as the portal:
  - `app/main.R` — "App entry point — hero banner + portal cards + about section"
  - `app/view/portal.R` — "Renders tool cards from `TOOLS` tribble"
  - No row for `scripts/build_static_site.R`, and no mention that `app/` is retired.
  A contributor (or a future agent) following CLAUDE.md would edit `main.R` / `portal.R`
  expecting the change to reach production — it never will.
- The drift is not cosmetic: the retired app carries a real navigation bug on its most
  promoted element. `app/logic/articles.R:27-30` marks `christine_cotton` as
  `status = "published", featured = TRUE`, so it is the Home "★ Featured Article"
  (`app/main.R:70-97`). But:
  - `app/main.R:25-28` — `.ARTICLE_MODULES` only registers `shingles` and
    `covid_vaccine`; `christine_cotton` is absent.
  - There is no `app/view/article_christine_cotton.R` (only `article_shingles.R` and
    `article_covid_vaccine.R` exist).
  - Therefore `.build_articles_menu()` (`app/main.R:35-66`) skips it (`mod` is `NULL`),
    so **no tabPanel with value `article_christine_cotton` is ever created**. Clicking
    "Read article →" fires `nav_to_article("christine_cotton")` →
    `updateNavbarPage(selected = "article_christine_cotton")` against a tab that
    doesn't exist (silent no-op). The `?article=christine_cotton` deep-link
    (`app/main.R:318-332`) fails the same way — it passes the `pub$id` membership check
    because the article *is* published, then navigates nowhere.
  - Separately, `app/view/articles.R:41-51` renders a card for **every** row regardless
    of `status`, unlike the builder's `published`-only filter — so the retired index
    would also leak the three current drafts (aav / glp1 / carbidopa) as broken links.
- The live static builder handles `christine_cotton` correctly
  (`build_article_pages()` reads `app/static/christine_cotton.html`, which exists), which
  is exactly why the bug is invisible today — and exactly why the stale CLAUDE.md is a
  trap rather than a harmless nit.

### Proposed change
1. Update `CLAUDE.md` Architecture/Key Files so `scripts/build_static_site.R` is the
   documented front end (inputs: `app/logic/{articles,tools}.R` tribbles +
   `app/static/<id>.html`; output: `static_site/` → nginx), and mark the `app/`
   Rhino view layer as **retired**. Add the one-line deploy command
   (`rsync -av --delete static_site/ …`, already at `build_static_site.R:389-391`).
2. Decide the fate of `app/` — either delete the retired `app/view/*` /
   `app/main.R` presentation layer (keeping only the `app/logic/*` tribbles and
   `app/static/*`, which the builder still sources), or, if it's kept as a fallback,
   register `christine_cotton` (add `app/view/article_christine_cotton.R` mirroring
   `article_shingles.R` and an `.ARTICLE_MODULES` entry) and filter `app/view/articles.R`
   to `status == "published"`.

### Effort estimate
~30 minutes: CLAUDE.md edit is quick; the decision on whether to delete vs. fix the
retired app needs a human call (hence report-only). Either follow-through is small.

### Risk
Low. Documentation-first; no runtime behavior changes on the live site. The only
judgment call is delete-vs-keep the retired Shiny layer.

---

## 3. The static-site top nav hardcodes `/methods` and `/aems` links with no coupling to whether those pages actually built — a skipped Quarto render ships a dead nav link

### Evidence
- `site_nav()` (`scripts/build_static_site.R:104-125`) **always** emits the standalone
  nav items:
  ```html
  <li class="nav-item"><a class="nav-link" href="/methods">Signal &amp; Noise</a></li>
  <li class="nav-item"><a class="nav-link" href="/aems">AEMS</a></li>
  ```
- But `build_standalone_pages()` (`scripts/build_static_site.R:354-369`) only
  `warning()`s and `next`s when the source HTML is missing:
  ```r
  if (!file.exists(src)) {
    warning(sprintf("Skipping standalone %s: %s not found (render the .qmd first)", ...))
    next
  }
  ```
  The article loop (`326-329`) does the same for `published` rows.
- The standalone HTML is not tracked and is regenerated at deploy from manual `.qmd`
  renders. `DECISION_LOG.md` (2026-07-14) explicitly records the intermediate state:
  "Validated: build runs, produces index/articles with the new tab; **warns aems.html
  missing until rendered (expected)**." During that window the nav linked `/aems` while
  no `aems.html` was built → a 404 for any visitor who clicked it. The same hazard
  recurs any time a render is skipped, a filename drifts, or a page is temporarily pulled.
- Root cause: `STANDALONE_PAGES` (`348-352`) is meant to be the single source of truth
  for these nav pages, but `site_nav()` doesn't read from it — the nav and the
  page-build are two independently hardcoded lists that can silently disagree.

### Proposed change
Derive the standalone nav `<li>`s from `STANDALONE_PAGES`, emitting a link only when
`app/static/<id>.html` actually exists at build time (and, symmetrically, gate the
article nav/cards on a present source). Concretely: build the standalone-and-article nav
fragment inside the run block after the file-existence checks, and pass it into
`site_nav()`. This makes "the page is in the nav" and "the page was built" the same
fact and removes the possibility of shipping a dead link.

### Effort estimate
~20-30 minutes (thread a computed nav fragment through `site_nav()`), plus a rebuild
to verify links resolve.

### Risk
Low. Purely additive guarding; when all pages render (the normal case) the nav is
byte-identical to today. Verify by building with a standalone `.qmd` deliberately
un-rendered and confirming its nav item is omitted rather than dangling.

---

### Not re-proposed / noted status
- **Novelty-filter Round 2** (`NOVELTY_FILTER_ROADMAP.md`, §"Round 2 — deferred") and the
  canonical EB / Weber-correction rebuild live in `signal-compute` / `faers-mobi`, not
  this repo, and cannot be verified from here — out of scope for a globalpatientsafety
  review.
- **REDESIGN_FRONTEND.md** three-audience pages (`/for/patients`, `/for/researchers`,
  `/for/pharma`, Phase 0 "this week", dated 2026-05-03) remain unbuilt; the live static
  site is a single landing page. The July work pivoted to a weekly-article + methods-series
  strategy, so this plan reads as **superseded** rather than merely stalled — worth an
  explicit "revive or close" decision, but not proposed as a build item this week.
- The `NAV_INJECTION()` "one argument not used" `sprintf` warning is already logged as a
  known harmless out-of-scope item (`DECISION_LOG.md`, 2026-07-14); not re-raised.
