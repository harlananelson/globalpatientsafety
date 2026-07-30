# Agent review: 2026-07-22

Weekly reflection on the globalpatientsafety.com portal (Rhino/Shiny). Report-only —
no code changed. Scope is the **portal repo**; the two existing `issues/*.md`
(`ajax-error.md`, `signal-disconnection.md`) concern `aers-mobi`/`faers-mobi` and are
not re-litigated here.

All three findings are concrete, portal-local, and independently fixable. They share a
theme worth calling out up front: **the article/tool registries have drifted out of sync
with the code and static assets that back them**, and the portal renders those registries
without guarding against the drift. The result is that finished, deployed content is
currently unreachable or dead-clicks in the live app.

---

## 1. The featured article (`christine_cotton`) is completely unreachable — its "Read article →" button is a dead click

### Evidence

`app/logic/articles.R:27-30` marks the Christine Cotton piece `status = "published",
featured = TRUE`:

```r
"christine_cotton",
"Tested Against VAERS: Christine Cotton's Safety Claims and the Post-Market Record",
... "2026-06-13", "published", TRUE,
```

Being the sole `published & featured` row, it is what `.featured_article_card()` renders
on the Home tab (`app/main.R:70-97`) — the single most prominent call-to-action on the
landing page. Its button calls `nav_to_article("christine_cotton")`
(`app/main.R:87-94`, `299-302`), which runs
`updateNavbarPage(session, "nav", selected = "article_christine_cotton")`.

But there is **no tab with that value**. `.build_articles_menu()` only emits a tab when a
matching view module exists (`app/main.R:39-42`: `mod <- .ARTICLE_MODULES[[row$id]]; if
(is.null(mod)) return(NULL)`), and `.ARTICLE_MODULES` registers only `shingles` and
`covid_vaccine` (`app/main.R:25-28`). There is no `app/view/article_christine_cotton.R`
on disk (confirmed: `ls app/view/` shows only `article_covid_vaccine.R` and
`article_shingles.R`). `updateNavbarPage` to a non-existent tab value silently does
nothing, so the button is inert.

The content is not missing — it is **fully rendered and shipped**:
`app/static/christine_cotton.html` (1.56 MB) exists and is served at
`static/christine_cotton.html` (same mechanism the working shingles/covid articles use,
e.g. `app/view/article_shingles.R:29`). The article also dead-clicks from the "View all
articles" index (see Finding 3). Net effect: a finished, featured article is 100%
unreachable in the running app.

### Proposed change

Add `app/view/article_christine_cotton.R` mirroring `app/view/article_shingles.R`
(iframe → `src = "static/christine_cotton.html"`, plus the same share bar), and add one
line to `.ARTICLE_MODULES` in `app/main.R:25-28`:

```r
.ARTICLE_MODULES <- list(
  shingles         = article_shingles,
  covid_vaccine    = article_covid_vaccine,
  christine_cotton = article_christine_cotton   # NEW
)
```

Also add the `box::use(app/view/article_christine_cotton, ...)` import at
`app/main.R:14-20`. No new content, data, or styling required — the static asset already
exists.

### Effort estimate

~20 minutes. One new ~30-line module (copy of `article_shingles.R` with the title and
`src` swapped) plus two one-line registry edits. No data or Sass involved.

### Risk

Very low. Purely additive; follows the established, working shingles/covid pattern. Worst
case is a title-text mismatch in the iframe `title` attribute. Verify by launching the app
and clicking the Home-tab featured button.

---

## 2. The "Signal methods" tool card says "Coming soon", but `methods.html` is built, deployed, and orphaned

### Evidence

`app/logic/tools.R:24-25` still lists:

```r
"Signal methods", "coming_soon", NA_character_,
"Reference documentation for the four disproportionality methods ... GPS/EBGM, PRR, ROR, BCPNN/IC.",
```

So `portal.R` renders it as a greyed-out, unclickable "Coming soon" card
(`app/view/portal.R:30-32`).

But that page is done. DECISION_LOG (2026-07-13, "Signal & Noise: named series + /methods
page") records: *"Built `/methods` static landing page (`articles/methods.qmd` →
`app/static/methods.html`)... Also rendered the AEMS page to `app/static/aems.html`."*
Both files are present and served: `app/static/methods.html` (1.51 MB) and
`app/static/aems.html` (1.54 MB). They are reachable at `static/methods.html` /
`static/aems.html` (same static route the article iframes rely on), yet **nothing in the
portal links to either** — `grep -rn "methods\|aems\|static/" app/main.R app/view/portal.R`
finds no reference. The DECISION_LOG note that they were "wired into top nav" did not land
in this repo's `app/main.R`.

So the portal simultaneously (a) tells visitors the methods reference is "Coming soon" and
(b) ships the finished reference as dead weight in the deploy. This is the highest-leverage
inconsistency here: a flagship methodology page (the site's stated editorial lane — see
DECISION_LOG 2026-07-13 "methodology-first editorial direction") is invisible to users.

### Proposed change

Flip the Tools registry row to point at the built page:

```r
"Signal methods", "live", "static/methods.html",
"Reference documentation for the four disproportionality methods ... GPS/EBGM, PRR, ROR, BCPNN/IC.",
```

`portal.R:31-40` already renders a live card with an `Open ... →` link for any row whose
`url` is non-`NA`, so no view change is needed. Consider whether the methods page should
open in the same tab or `target="_blank"` (portal links currently force `_blank`,
`portal.R:36`) — an internal static page may read better in-tab. Separately, decide whether
`aems.html` warrants its own card/link or should stay an internal artifact; if it is meant
to be public, it needs a surface too.

### Effort estimate

~10 minutes for the one-row edit and a click-through check. Add ~10 more minutes if you also
surface `aems.html` and/or special-case in-tab opening for internal static pages.

### Risk

Low. If `methods.html` should NOT yet be public (deploy still gated per DECISION_LOG
2026-07-13: "Deploy still gated on user"), do not flip the card — instead this finding
stands as: **decide the methods page's public status and make the card reflect it**, because
today the card and the shipped asset disagree. Confirm the static route resolves in the
deployed environment before flipping (local `rhino::app()` serves `app/static` at
`/static/`; verify the VPS deploy does too).

---

## 3. The "View all articles" index renders drafts and moduleless articles as dead-click cards

### Evidence

`app/view/articles.R:49` renders a card for **every** row of `ARTICLES` with no status or
module filter:

```r
!!!lapply(seq_len(nrow(ARTICLES)), function(i) .article_card(ARTICLES[i, ], ns))
```

This is inconsistent with the rest of the app, which everywhere filters to published:
the navbar menu (`app/main.R:36`), the featured card (`app/main.R:71`), and the server-side
article mounts (`app/main.R:289`) all use `ARTICLES[ARTICLES$status == "published", ]`.

`ARTICLES` currently contains three `status = "draft"` rows (`app/logic/articles.R:15-26`):
`aav_gene_therapy_liver`, `glp1_alopecia`, `carbidopa_levodopa_b6`. Each is drawn in the
public index with a working-looking "Read →" button (`app/view/articles.R:27-36`) that
calls `switch_to_article(id)` → `updateNavbarPage` to a tab that does not exist (drafts have
no module and are excluded from the menu). Every one of them is a dead click. The same is
true of `christine_cotton` until Finding 1 is fixed. So the index advertises unfinished work
and then fails to open it — the opposite of the menu's behavior.

### Proposed change

Make the index agree with the rest of the app. Minimal fix — filter to renderable articles
(published **and** backed by a module):

```r
pub <- ARTICLES[ARTICLES$status == "published", , drop = FALSE]
# ...render pub, not the full ARTICLES...
```

If drafts are meant to be teased publicly, render them as explicitly **disabled**
"Coming soon" cards (mirroring the `coming_soon` treatment in `portal.R:30-32`) rather than
as active buttons that dead-click — but do not emit a live "Read →" for an article the app
cannot open. Whichever path, the index's set of clickable articles must be a subset of the
tabs `.build_articles_menu()` actually creates.

### Effort estimate

~15 minutes for the filter-only version (one `subset` + swap the `lapply` source). ~45
minutes if you add the disabled-card treatment for drafts and a small helper shared with
`portal.R`'s status badge.

### Risk

Low. Removing dead cards only ever removes broken affordances; no working link is lost. The
disabled-card variant touches more markup — verify the grid still lays out correctly with
mixed active/disabled cards. Regression check: after the fix, every "Read →" in the index
must open a real tab (click each one).

---

## Note on the larger stalled roadmap (not proposed this week)

`REDESIGN_FRONTEND.md` (Draft, 2026-05-03) specifies a three-audience landing structure
(`/for/patients`, `/for/researchers`, `/for/pharma`) and the tagline *"Know before it
becomes a headline."* The live portal still ships a single generic hero with a different
tagline (`app/main.R:135-141`: "Open tools for pharmacovigilance signal detection and
clinical research acceleration"). This is a genuine stalled item, but it is a multi-page
build, not a scoped weekly fix, so it is deliberately **not** one of the three above. A
sensible first slice when it is picked up: adopt the spec's tagline and add the patient
landing hero, before the researcher/pharma pages. Flagged here so it is not lost.
