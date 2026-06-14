# Deploy Plan — "Christine Cotton Tested Against VAERS" article

**Status:** article written + reviewed + data-wired + **registered**; render deps
(Quarto + gt) added to `flake.nix`. One real blocker remains: SSH to the VPS for the
final rsync. The render is now a local `nix develop` + `quarto render`; nothing requires
"inspecting the live box" — the publication mechanism is fully in this repo.
**Drafted:** 2026-06-13 · **Rewritten:** 2026-06-13 (corrected publication model)
**Article source:** `articles/christine-cotton-vaers.qmd`
**Registry id:** `christine_cotton` (must match `app/static/christine_cotton.html`)

---

## What this article is

A general-public pharmacovigilance post for globalpatientsafety.com. It takes the
French biostatistician Christine Cotton's claims about Pfizer's Comirnaty (BNT162b2)
Phase 3 trial (C4591001) and tests the *categories* of adverse event she flagged
(cardiac, reproductive/menstrual, thrombotic, stroke) against the VAERS signal
database. The framing is deliberately modest: VAERS **cannot confirm** a claim about
how a trial was run; it can only show whether those concern-categories correspond to
real disproportionality signals in independent data. They do.

Originating idea: Helmut Sterz obituary in `~/projects/AI/ideas/blog/Christine-Cotton.md`.

---

## How publication actually works (the mechanism is in this repo)

The site is a **static nginx site** (the interactive Shiny app at this domain was
retired). It is built locally and rsync'd to the box. There is nothing to "discover"
on the VPS — the wiring is three in-repo pieces:

| Piece | Role |
|---|---|
| `app/logic/articles.R` | `ARTICLES` tribble — one row per article. `featured = TRUE` picks the single featured article on the landing page. **Source of truth for what is published and what is featured.** |
| `app/static/<id>.html` | The Quarto-rendered article HTML (input). `build_static_site.R` prepends a site-nav header to it. |
| `scripts/build_static_site.R` | Reads the tribble + the static HTML, writes the full site to `static_site/` (`index.html`, `articles.html`, per-article pages, favicon). |

Deploy is the rsync line printed at the end of `build_static_site.R`:

```bash
rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/
```

> **Correction to the prior draft of this doc:** earlier notes claimed the publication
> structure was "on the VPS, not in this repo," that `touch restart.txt` was needed
> (Shiny), and that the qmd had to be rendered on the box. All three were wrong. The
> `articles/shingles.md` stub is *not* the live shingles source — the live article is
> `app/static/shingles.html`, registered in `articles.R`. Featured status is the
> `featured` flag, not a VPS artifact.

---

## State of the article

- **Registered (done 2026-06-13).** A row for `christine_cotton` was added to
  `app/logic/articles.R` with `featured = TRUE`; the previous featured article
  (`shingles`) was flipped to `featured = FALSE`. Title/subtitle/date taken from the
  qmd front matter.
- **Every number is data-generated.** A `setup` chunk loads the signals parquet and
  defines `eb("^PT$")` / `n_signals()`. All EB05 values in the prose are inline
  `` `r eb(...)` `` calls anchored with `^...$` to one Preferred Term each. Prose and
  tables read the same parquet — they cannot drift. Verified: Myocarditis 3.14,
  Menstrual disorder 3.94, Heavy menstrual bleeding 2.86, Intermenstrual bleeding 2.64,
  Pulmonary thrombosis 2.98, DVT 2.73, Thrombosis 2.65.
- **Path is params-driven, dual-environment.** YAML `params.data_path` defaults to the
  server path `/srv/shiny-server/gps-patient/data/signals_vaers.parquet`; the setup
  chunk falls back to the local `/home/harlan/projects/gps-patient/data/...` copy if the
  server path is absent. First existing path wins; errors loudly if neither exists.
  Renders unedited in both places. Override: `quarto render … -P data_path:/path.parquet`.
- **Editorial review applied (Opus 4.8 pass).** EB05 corrected to a *within-database
  disproportionality* description (not "vs population background"); stimulated-reporting
  caveats moved inline into the myocarditis + menstrual sections; unverified trial counts
  (the "127 vs 116 SAE", "240 vs 139 Grade-3", "4 cardiac cases") cut and attributed to
  Cotton's document instead of asserted; ARR 0.84% kept with the *Lancet Microbe* 2021
  citation; ovarian-biodistribution claim corrected to the contested rat-LNP study;
  Ventavia attributed to *The BMJ* (Thacker 2021) as allegations Pfizer disputed; all
  Pfizer-misconduct framing reattributed to Cotton, not stated in the GPS voice; title
  changed from "What the Data Confirms" → "Tested Against VAERS" so it no longer
  contradicts the body.

## Numbers still to verify against Cotton's primary document (before final publish)

These were softened/attributed, not asserted, but quote her real figures if you have the
document open:
- The trial SAE / Grade-≥3 counts by arm.
- The "84% local AE in vaccine arm" reactogenicity figure (now stated qualitatively).
Her source docs: the book *Tous vaccinés, tous protégés?* and her final GCP assessment
("Assessment of Methodological Practices Implemented in Pfizer's COVID-19 mRNA Vaccine
Trials with respect to Good Clinical Practice").

---

## Blocker 1 — local render (resolved: Quarto + gt added to flake)

This workstation originally had no `quarto` on PATH and no `rmarkdown` in the renv. As of
2026-06-13 `flake.nix` provides both render dependencies, so the render is now local:
- `pkgs.quarto` in the devShell `packages` (the renderer; uses the `knitr` engine, which
  is in the renv at 1.51, and bundles its own pandoc).
- `pkgs.rPackages.gt` in `rWithPkgs` (the article's setup chunk does `library(gt)`).

Enter the shell with `nix develop` — the first activation downloads Quarto (sizable) and
may rebuild the R wrapper. The render needs the signals parquet at
`/home/harlan/projects/gps-patient/data/signals_vaers.parquet` (the setup chunk's local
fallback; present, verified 2026-06-13). The render command itself is folded into deploy
step 1 below.

## Blocker 2 — SSH to the VPS (deploy step only)

The final `rsync` needs SSH to `root@5.78.69.136`. The prior draft reported the
GitHub key (`~/.ssh/id_ed25519`) being rejected by the box. **Do not regenerate
`id_ed25519`** — it is the GitHub key (AI repo, transfer repo, lhn) and overwriting it
breaks those. Re-add the *existing* public key to the box:

```bash
# user runs this once, interactively (needs the VPS root password):
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@5.78.69.136
```

Public key to add (if pasting via Hetzner console instead):
`ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBtdaIDcyp2K0isfVzg2VMd1wk2vMsiXbqYPEpTC9sR5 harlananelson@gmail.com`

(Verified 2026-06-13: `~/.ssh/id_ed25519.pub` on this workstation matches the key above.)

---

## Deploy steps

1. **Render + place** `articles/christine-cotton-vaers.qmd` → `app/static/christine_cotton.html`.
   Quarto writes the HTML next to the source, so the render and the move are one step
   (the `--output` filename + `mv` must both use the registry id `christine_cotton`):
   ```bash
   nix develop   # picks up quarto + gt (added to flake.nix 2026-06-13)
   export RENV_CONFIG_AUTOLOADER_ENABLED=FALSE   # renv .Rprofile shadows the nix R lib; disable it
   export QUARTO_R="$(command -v Rscript)"        # else quarto runs /usr/bin/Rscript (system R) and fails
   cd articles && quarto render christine-cotton-vaers.qmd --output christine_cotton.html && cd ..
   mv articles/christine_cotton.html app/static/christine_cotton.html
   rm -rf articles/christine-cotton-vaers_files   # drop the now-unused libs dir (gitignored anyway)
   ```
   **Render from inside `articles/`**, not the project root: the qmd uses
   `embed-resources: true` (self-contained HTML, matching shingles/covid_vaccine — the
   build ships only the single `<id>.html`), and the embed post-process resolves the
   `*_files/libs` dir relative to cwd. Rendering from the repo root puts the HTML at root
   but the libs under `articles/`, so embed fails with `NotFound … quarto-html/quarto.js`.
   Output should be ~1.5 MB with **zero `_files/` references**.

   **Both env vars are required**, learned the hard way 2026-06-13:
   - Without `RENV_CONFIG_AUTOLOADER_ENABLED=FALSE`, renv's `.Rprofile` redirects R to the
     (unrestored) project library and `library(gt)` fails — the nix-provided gt/arrow/dplyr
     are invisible.
   - Without `QUARTO_R` pointed at the nix `Rscript`, quarto picks `/usr/bin/Rscript` (system
     R), which dies on a GLIBC mismatch under the shell's `LD_LIBRARY_PATH`.
   - Harmless noise: `jog.lua: Don't know how to traverse TableBody` errors print once per gt
     table — the HTML still renders correctly (verified: 16 gt tables + all inline EB05 numbers
     present). Do not chase these.

   Needs the local parquet at `/home/harlan/projects/gps-patient/data/signals_vaers.parquet`
   (present, verified 2026-06-13). `app/static/` is the only correct destination —
   `build_static_site.R` reads `app/static/<id>.html`, not the `articles/` dir.
2. **(Done)** Registry row added to `app/logic/articles.R`: `christine_cotton`,
   `featured = TRUE`; `shingles` flipped to `featured = FALSE`.
3. **Build** the static site locally (same `nix develop` shell, renv still disabled):
   ```bash
   RENV_CONFIG_AUTOLOADER_ENABLED=FALSE Rscript scripts/build_static_site.R   # writes static_site/
   ```
   Confirm `static_site/index.html` shows the Cotton card as ★ Featured and
   `static_site/christine_cotton.html` exists. (Harmless: an sprintf "one argument not
   used by format" warning prints from `NAV_INJECTION()` — a pre-existing bug in the
   build script, output is fine.)
   **(Done 2026-06-13 — verified: Cotton is the featured card, 16 gt tables intact,
   `/articles` lists all three.)**
4. **Restore SSH** if needed (Blocker 2): `ssh-copy-id` above, then `ssh root@5.78.69.136`
   to confirm access.
5. **Deploy** (rsync — the only step that touches the box):
   ```bash
   rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/
   ```
   No `touch restart.txt` — it is a static nginx site, served from disk.
6. **Smoke-test:** `curl -sI https://globalpatientsafety.com/ | head -1`; load the
   landing page (Cotton should be the featured card) and the article URL
   `https://globalpatientsafety.com/christine_cotton`; confirm the tables rendered
   (data path resolved on the box) and `/articles` lists it.

## Rollback

Flip `featured` back to `shingles` in `app/logic/articles.R`, rebuild, and rsync.
To fully remove: set the Cotton row to `status = "draft"` (or delete it) and remove
`app/static/christine_cotton.html`, then rebuild + rsync.
