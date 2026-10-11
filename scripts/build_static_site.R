#!/usr/bin/env Rscript
# Build a static landing site for globalpatientsafety.com.
#
# Inputs (single source of truth)
#   app/logic/articles.R     -> ARTICLES tribble
#   app/logic/tools.R        -> TOOLS tribble
#   app/static/<id>.html     -> rendered Quarto article (input + post-processed)
#
# Output (deployed to /var/www/globalpatientsafety/ on the VPS)
#   static_site/index.html       -> landing page
#   static_site/articles.html    -> articles card grid
#   static_site/<id>.html        -> article HTML with site-nav header prepended
#   static_site/favicon.ico
#
# Run:  Rscript scripts/build_static_site.R
#
# Why static: each page is served from disk by nginx with zero R worker
# cost. The interactive Shiny app at this domain is retired in favour of
# the tool subdomains, which remain Shiny.

library(tibble)
library(dplyr)
library(stringr)

# Resolve project root: if Rscript --file passed, use its dirname/..,
# otherwise fall back to getwd() which works when invoked from the project.
script_path <- tryCatch({
  arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1]
  if (!is.na(arg)) sub("^--file=", "", arg) else NA_character_
}, error = function(e) NA_character_)
PROJ_ROOT <- if (!is.na(script_path) && nzchar(script_path)) {
  normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
} else getwd()
if (!file.exists(file.path(PROJ_ROOT, "app/logic/articles.R"))) {
  PROJ_ROOT <- getwd()
}
OUT_DIR <- file.path(PROJ_ROOT, "static_site")
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)

# ── Source the tribbles -----------------------------------------------------
# app/logic/*.R still carries the `box::use(tibble[tribble])` header it needed
# as a Rhino module. Binding a fake `box` in the eval env does NOT neutralise
# that call — `::` resolves the real namespace regardless of what is bound
# locally — so the previous stub silently made this script depend on the `box`
# package, which only happened to be installed via the (now archived) rhino
# tree. Strip the call textually instead, the way scripts/check_site_consistency.R
# does, and supply tribble ourselves. The registries then load with no tie to
# the retired Shiny stack. See archive/rhino-app/README.md.
load_tribble <- function(path, symbol) {
  text <- paste(readLines(path, warn = FALSE), collapse = "\n")
  text <- gsub("box::use\\s*\\([^)]*\\)", "", text, perl = TRUE)
  if (grepl("box::", text, fixed = TRUE)) {
    stop(sprintf(
      "%s has a box:: call this loader cannot strip; it would drag in the archived Rhino stack.",
      path
    ))
  }
  e <- new.env(parent = globalenv())
  e$tribble <- tibble::tribble
  e$tibble  <- tibble::tibble
  eval(parse(text = text), envir = e)
  if (!exists(symbol, envir = e, inherits = FALSE)) {
    stop(sprintf("%s does not define %s", path, symbol))
  }
  get(symbol, envir = e, inherits = FALSE)
}

ARTICLES <- load_tribble(file.path(PROJ_ROOT, "app/logic/articles.R"), "ARTICLES")
TOOLS    <- load_tribble(file.path(PROJ_ROOT, "app/logic/tools.R"),    "TOOLS")

published <- ARTICLES |> filter(status == "published")
featured  <- published |> filter(featured == TRUE) |> slice(1)

# Top-nav pages that are NOT articles (not in ARTICLES, not in the articles grid).
# Each is a Quarto doc rendered to app/static/<id>.html; build_standalone_pages()
# wraps it with the sticky back-nav. Nav links are emitted only when the HTML exists.
STANDALONE_PAGES <- tibble::tribble(
  ~id,        ~title,              ~nav_label,
  "methods",  "Signal & Noise",    "Signal &amp; Noise",
  "aems",     "Inside the AEMS Data", "AEMS"
)

standalone_html_exists <- function(id) {
  file.exists(file.path(PROJ_ROOT, "app/static", paste0(id, ".html")))
}

available_standalone <- STANDALONE_PAGES[
  vapply(STANDALONE_PAGES$id, standalone_html_exists, logical(1)),
  ,
  drop = FALSE
]

cat("Loaded ", nrow(published), "published articles and",
    nrow(TOOLS), "tools;",
    nrow(available_standalone), "standalone nav pages available.\n")

# ── HTML helpers ------------------------------------------------------------
esc <- function(s) {
  s <- as.character(s); s[is.na(s)] <- ""
  s <- gsub("&",  "&amp;",  s, fixed = TRUE)
  s <- gsub("<",  "&lt;",   s, fixed = TRUE)
  s <- gsub(">",  "&gt;",   s, fixed = TRUE)
  s <- gsub('"',  "&quot;", s, fixed = TRUE)
  s
}

# First sentence of every description names the machine path (handshake 2026-10-10).
MACHINE_SENTENCE <- paste(
  "Machine path: GET /pipeline?sponsor= on this site, and",
  "GET https://faers.mobi/signals for FAERS signals."
)

site_head <- function(title, description = "", page = "/") {
  md <- if (identical(page, "/")) "/index.md" else paste0(page, ".md")
  desc <- paste(MACHINE_SENTENCE, description)
  sprintf('<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>%s</title>
  <meta name="description" content="%s">
  <link rel="alternate" type="text/markdown" href="%s">
  <link rel="alternate" href="/llms.txt" title="llms.txt">
  <link rel="service-desc" type="application/json" href="/openapi.json">
  <link rel="icon" href="/favicon.ico">
  <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;700&display=swap" rel="stylesheet">
  <style>
    body { font-family: "Inter", -apple-system, system-ui, sans-serif; background: #f8fafc; color: #1a2332; }
    a { color: #0b4f6a; }
    .navbar-dark { background-color: #1a2332 !important; }
    .navbar-dark .nav-link { color: #e8f4fb; }
    .navbar-brand { font-weight: 500; letter-spacing: -0.02em; }
    .navbar-brand .brand-accent { color: #7ec8e8; }
    .hero { background-color: #0f4c6e; color: white; padding: 4rem 0 3rem; }
    .hero h1 { font-weight: 300; letter-spacing: -0.02em; }
    .hero a.btn { background: #fff; color: #0f4c6e; }
    .card { border: none; box-shadow: 0 1px 3px rgba(0,0,0,0.08); }
    .card-tool { transition: transform 0.15s ease; }
    .card-tool:hover { transform: translateY(-2px); box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    .featured-card { border: 1px solid #0f4c6e; }
    .featured-card .card-header { background: #0f4c6e; color: white; font-weight: 600; }
    .section-title { font-weight: 300; margin: 2rem 0 1rem; }
    .text-muted { color: #495057 !important; }
    .badge-soon { background: #334155; color: #fff; }
    .llm-access { background: #e7eef3; color: #1a2332; padding: .75rem 0; }
    .llm-access a { color: #0b4f6a; }
    .skip-link { position: absolute; left: 0; top: -3rem; background: #fff; color: #0b4f6a; padding: .5rem 1rem; z-index: 2000; }
    .skip-link:focus { top: 0; }
    footer { background: #f8fafc; padding: 1.5rem 0; text-align: center; color: #334155; font-size: 0.95rem; margin-top: 4rem; }
    footer a { color: #0b4f6a; }
    :focus-visible { outline: 3px solid #0b4f6a; outline-offset: 2px; }
    .navbar :focus-visible { outline-color: #b9e2f5; }
  </style>
</head>
<body>
', esc(title), esc(desc), esc(md))
}

skip_link <- '<a class="skip-link" href="#main">Skip to content</a>\n'

llm_banner <- function(md_href) {
  sprintf('
<div class="llm-access">
  <div class="container">
    <strong>LLM / API access.</strong>
    <a href="/api">API</a> ·
    <a href="/llms.txt">llms.txt</a> ·
    <a href="/mcp.md">MCP</a> ·
    <a href="%s">Markdown</a>
  </div>
</div>
', esc(md_href))
}

site_nav <- function(active = "") {
  # Standalone nav items only when the page's source HTML exists — avoids
  # shipping a dead /methods or /aems link after a skipped Quarto render.
  standalone_items <- if (nrow(available_standalone) == 0) {
    ""
  } else {
    paste0(vapply(seq_len(nrow(available_standalone)), function(i) {
      row <- available_standalone[i, ]
      sprintf(
        '        <li class="nav-item"><a class="nav-link" href="/%s">%s</a></li>\n',
        esc(row$id), row$nav_label
      )
    }, character(1)), collapse = "")
  }

  paste0(
    '<nav class="navbar navbar-expand-md navbar-dark">
  <div class="container-fluid">
    <a class="navbar-brand" href="/"><span class="brand-accent">Global</span> Patient Safety</a>
    <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nav" aria-controls="nav" aria-expanded="false" aria-label="Toggle navigation">
      <span class="navbar-toggler-icon"></span>
    </button>
    <div class="collapse navbar-collapse" id="nav">
      <ul class="navbar-nav ms-auto">
        <li class="nav-item"><a class="nav-link" href="/">Home</a></li>
        <li class="nav-item"><a class="nav-link" href="/pipeline">Pipeline analysis</a></li>
        <li class="nav-item"><a class="nav-link" href="/articles">Articles</a></li>
',
    standalone_items,
    '        <li class="nav-item"><a class="nav-link" href="https://faers.mobi" target="_blank" rel="noopener">faers.mobi</a></li>
        <li class="nav-item"><a class="nav-link" href="https://picodag.globalpatientsafety.com" target="_blank" rel="noopener">pico-dag</a></li>
        <li class="nav-item"><a class="nav-link" href="https://vaers.globalpatientsafety.com" target="_blank" rel="noopener">vaers</a></li>
        <li class="nav-item"><a class="nav-link" href="/#about">About</a></li>
      </ul>
    </div>
  </div>
</nav>
'
  )
}

site_foot <- '
<footer>
  <div class="container">
    <small>© Global Patient Safety · CDC VAERS + FDA FAERS public-domain data ·
      <a href="https://doi.org/10.1177/009286159903300105" target="_blank" rel="noopener">GPS framework (DuMouchel 1999)</a> ·
      Signals are statistical patterns, not evidence of causation. Not medical advice.
      · <a href="/accessibility">Accessibility</a>
    </small>
  </div>
</footer>
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"></script>
<script>
  // Backwards compat: old ?article=<id> Shiny permalinks redirect to /<id>.
  (function(){
    var m = location.search.match(/[?&]article=([^&]+)/);
    if (m && location.pathname === "/") {
      location.replace("/" + decodeURIComponent(m[1]));
    }
  })();
</script>
</body>
</html>'

# ── Templates ---------------------------------------------------------------
article_card_html <- function(row) {
  sprintf('
<div class="col">
  <a href="/%s" style="text-decoration:none; color:inherit;">
    <div class="card h-100">
      <div class="card-body">
        <h3 class="card-title h5">%s</h3>
        <p class="text-muted small mb-2">%s</p>
        <p class="card-text">%s</p>
      </div>
    </div>
  </a>
</div>', esc(row$id), esc(row$title), esc(row$date), esc(row$subtitle))
}

tool_card_html <- function(row) {
  status_badge <- switch(row$status,
    live        = '<span class="badge bg-success">Live</span>',
    beta        = '<span class="badge bg-warning text-dark">Beta</span>',
    coming_soon = '<span class="badge badge-soon">Coming soon</span>',
    "")
  href <- if (!is.na(row$url) && nzchar(row$url)) row$url else ""
  # Same-site paths (e.g. /methods) stay in this tab; external tools open blank.
  # A coming-soon card is not a link: an href of "#" is a keyboard trap.
  attrs <- if (grepl("^/", href)) {
    ""
  } else {
    'target="_blank" rel="noopener"'
  }
  inner <- sprintf('
    <div class="card card-tool h-100">
      <div class="card-body">
        <div class="d-flex justify-content-between align-items-start mb-2">
          <h3 class="card-title h5 m-0">%s</h3>
          %s
        </div>
        <p class="card-text text-muted small">%s</p>
      </div>
    </div>',
    esc(row$name), status_badge, esc(row$tagline))
  wrapped <- if (row$status == "coming_soon" || !nzchar(href)) {
    sprintf('<div class="h-100" aria-disabled="true">%s</div>', inner)
  } else {
    sprintf('<a href="%s" %s style="text-decoration:none; color:inherit;">%s</a>',
            esc(href), attrs, inner)
  }
  sprintf('<div class="col">%s</div>', wrapped)
}

# ── INDEX -------------------------------------------------------------------
build_index <- function() {
  # Primer pages (e.g. aems) use a "Start here" label so the splash reads as
  # orientation/education — useful when licensors or new visitors land first.
  featured_label <- if (nrow(featured) && featured$id[1] %in% c("aems", "methods")) {
    "★ Start here — how we read the data"
  } else {
    "★ Featured Article"
  }
  featured_html <- if (nrow(featured) == 0) "" else sprintf('
<section class="container my-5">
  <div class="card featured-card mb-3">
    <div class="card-header">%s</div>
    <div class="card-body">
      <h2 class="card-title h4 mb-2">%s</h2>
      <p class="text-muted small mb-2">%s</p>
      <p class="card-text">%s</p>
      <a href="/%s" class="btn btn-primary btn-sm mt-2">Read →</a>
    </div>
  </div>
</section>',
    featured_label,
    esc(featured$title), esc(featured$date), esc(featured$subtitle), esc(featured$id))

  tool_cards <- paste(
    vapply(seq_len(nrow(TOOLS)), function(i) tool_card_html(TOOLS[i, ]),
           character(1)),
    collapse = "\n")

  recent_articles <- published |> arrange(desc(date)) |> head(3)
  recent_cards <- paste(
    vapply(seq_len(nrow(recent_articles)),
           function(i) article_card_html(recent_articles[i, ]), character(1)),
    collapse = "\n")

  html <- paste0(
    site_head(
      "Global Patient Safety — Pharmacovigilance tools and signal analyses",
      "Open tools for pharmacovigilance signal detection and clinical research acceleration. CDC VAERS and FDA FAERS analyses using peer-reviewed Bayesian and frequentist disproportionality methods.",
      page = "/"
    ),
    skip_link,
    site_nav(active = "home"),
    llm_banner("/index.md"),
    '<main id="main" tabindex="-1">',
    '<header class="hero">
  <div class="container text-center">
    <h1 class="display-5 mb-3">Global Patient Safety</h1>
    <p class="lead mb-3">Open tools for pharmacovigilance signal detection and clinical research acceleration.</p>
    <p class="mb-0"><a class="btn" href="/pipeline">Pipeline analysis</a></p>
  </div>
</header>',
    featured_html,
    '<section class="container my-5">
  <h2 class="section-title">Tools</h2>
  <div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-3">',
    tool_cards,
    '</div>
</section>',
    sprintf('
<section class="container my-5">
  <div class="d-flex justify-content-between align-items-baseline">
    <h2 class="section-title m-0">Recent articles</h2>
    <a href="/articles" class="small">View all →</a>
  </div>
  <div class="row row-cols-1 row-cols-md-3 g-3 mt-1">%s</div>
</section>',
    recent_cards),
    '<section id="about" class="container my-5" style="max-width: 760px;">
  <h2 class="section-title">About</h2>
  <p class="lead text-muted">We analyse 35 years of FDA and CDC adverse-event data using peer-reviewed Bayesian statistics to surface drug safety signals that matter to patients and clinicians.</p>
  <div class="row g-4 my-4">
    <div class="col-md-4">
      <h3 class="h6 fw-semibold mb-2">Data sources</h3>
      <ul class="text-muted small mb-0">
        <li>FDA FAERS (2018–present)</li>
        <li>CDC VAERS (1990–present)</li>
      </ul>
    </div>
    <div class="col-md-4">
      <h3 class="h6 fw-semibold mb-2">Methods</h3>
      <ul class="text-muted small mb-0">
        <li>GPS — 5th-percentile credible bound, dual-Gamma posterior, linear RR scale (DuMouchel 1999 framework)</li>
        <li>PRR, ROR, BCPNN/IC</li>
        <li>Consensus: flagged by ≥ 2 of 4 methods</li>
      </ul>
    </div>
    <div class="col-md-4">
      <h3 class="h6 fw-semibold mb-2">Privacy</h3>
      <p class="text-muted small mb-0">No data is stored. No account required.</p>
    </div>
  </div>
</section>',
    '</main>',
    site_foot
  )
  writeLines(html, file.path(OUT_DIR, "index.html"))
  cat("  wrote", file.path(OUT_DIR, "index.html"), "\n")
}

# ── ARTICLES INDEX ----------------------------------------------------------
build_articles_index <- function() {
  cards <- paste(
    vapply(seq_len(nrow(published)),
           function(i) article_card_html(published[i, ]), character(1)),
    collapse = "\n")

  html <- paste0(
    site_head("Articles — Global Patient Safety",
              "Pharmacovigilance signal analyses and reanalyses.",
              page = "/articles"),
    skip_link,
    site_nav(active = "articles"),
    llm_banner("/articles.md"),
    '<main id="main" tabindex="-1">',
    '<header class="container mt-4">
  <h1 class="section-title">Articles</h1>
  <p class="text-muted">Independent signal analyses using the project\'s standard disproportionality methodology.</p>
</header>',
    '<section class="container my-4">
  <div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-3">',
    cards,
    '</div>
</section>',
    '</main>',
    site_foot)
  writeLines(html, file.path(OUT_DIR, "articles.html"))
  cat("  wrote", file.path(OUT_DIR, "articles.html"), "\n")
}

# ── ARTICLE PAGES (post-process Quarto HTML) --------------------------------
# Each app/static/<id>.html is the full Quarto-rendered document. To present
# it within the site (back link, nav), we prepend a thin header bar that
# links to / and /articles, and a share button. The Quarto <body> contents
# remain intact below.
#
# One %s: the page id, used only in the markdown-twin href. The old constant
# form could not name that per-page link.
article_chrome <- function(page) {
  sprintf('
<a class="skip-link" href="#quarto-document-content">Skip to content</a>
<div class="llm-access">
  <strong>LLM / API access.</strong>
  <a href="/api">API</a> ·
  <a href="/llms.txt">llms.txt</a> ·
  <a href="/mcp.md">MCP</a> ·
  <a href="/%s.md">Markdown</a>
</div>
<div class="d-flex align-items-center justify-content-between px-3 py-2"
     style="background:#1a2332; color:#fff; font-family:Inter,sans-serif; font-size:14px; position:sticky; top:0; z-index:1000;">
  <div>
    <a href="/" style="color:#7ec8e8; text-decoration:none; margin-right:1rem;">&larr; Global Patient Safety</a>
    <a href="/pipeline" style="color:#d7eef8; text-decoration:none; margin-right:1rem;">Pipeline analysis</a>
    <a href="/articles" style="color:#d7eef8; text-decoration:none;">All articles</a>
  </div>
  <button onclick="navigator.clipboard.writeText(location.href);this.textContent=\'Copied\';setTimeout(()=>this.textContent=\'Copy link\',1500);"
          style="background:transparent; color:#fff; border:1px solid #7ec8e8; padding:4px 10px; border-radius:4px; cursor:pointer; font-size:13px;">
    Copy link
  </button>
</div>
', esc(page))
}

finish_quarto <- function(html, out, page) {
  nav <- article_chrome(page)
  html <- sub("(<body[^>]*>)", paste0("\\1\n", nav), html, perl = TRUE)
  writeLines(html, out)
  py <- file.path(PROJ_ROOT, "scripts/polish_html.py")
  status <- system2("python3", c(py, out, page))
  if (!identical(as.integer(status), 0L)) {
    stop(sprintf("polish_html.py failed for %s", page))
  }
}

build_article_pages <- function() {
  for (i in seq_len(nrow(published))) {
    row <- published[i, ]
    src <- file.path(PROJ_ROOT, "app/static", paste0(row$id, ".html"))
    if (!file.exists(src)) {
      warning(sprintf("Skipping %s: %s not found", row$id, src))
      next
    }
    out <- file.path(OUT_DIR, paste0(row$id, ".html"))
    html <- paste(readLines(src, warn = FALSE), collapse = "\n")
    finish_quarto(html, out, row$id)
    cat("  wrote", out,
        sprintf("(%.1f KB)", file.info(out)$size / 1024), "\n")
  }
}

# ── STANDALONE NAV PAGES (post-process Quarto HTML) -------------------------
# STANDALONE_PAGES is defined near the top (with nav coupling). Here we wrap
# each available page with the sticky back-nav bar used for articles.
build_standalone_pages <- function() {
  for (i in seq_len(nrow(STANDALONE_PAGES))) {
    row <- STANDALONE_PAGES[i, ]
    src <- file.path(PROJ_ROOT, "app/static", paste0(row$id, ".html"))
    if (!file.exists(src)) {
      warning(sprintf("Skipping standalone %s: %s not found (render the .qmd first)",
                      row$id, src))
      next
    }
    out  <- file.path(OUT_DIR, paste0(row$id, ".html"))
    html <- paste(readLines(src, warn = FALSE), collapse = "\n")
    finish_quarto(html, out, row$id)
    cat("  wrote", out, sprintf("(%.1f KB)", file.info(out)$size / 1024), "\n")
  }
}

# ── FAVICON -----------------------------------------------------------------
build_favicon <- function() {
  src <- file.path(PROJ_ROOT, "app/static/favicon.ico")
  if (file.exists(src)) {
    file.copy(src, file.path(OUT_DIR, "favicon.ico"), overwrite = TRUE)
    cat("  wrote", file.path(OUT_DIR, "favicon.ico"), "\n")
  }
}

# ── Dead internal-link check ------------------------------------------------
# Scan built HTML for same-site hrefs (./id or /id, no scheme) and warn when
# the target file is missing from static_site/. Fails hard on zero targets
# that look like article/standalone slugs (not anchors or assets).
check_internal_links <- function() {
  html_files <- list.files(OUT_DIR, pattern = "\\.html$", full.names = TRUE)
  if (length(html_files) == 0) {
    return(invisible(NULL))
  }
  # Known-good built pages (index/articles plus published + standalone)
  known <- c(
    "index", "articles", "pipeline", "api", "mcp", "accessibility",
    published$id,
    available_standalone$id
  )
  # Also accept file paths that exist under OUT_DIR
  broken <- character()
  for (f in html_files) {
    lines <- paste(readLines(f, warn = FALSE), collapse = "\n")
    # href="./slug" or href="/slug" (no further path, no query/hash-only)
    matches <- unlist(regmatches(
      lines,
      gregexpr('href=["\'](\\.?/)?([a-zA-Z0-9_\\-]+)["\']', lines, perl = TRUE)
    ))
    if (length(matches) == 0) next
    slugs <- sub('href=["\'](\\.?/)?([a-zA-Z0-9_\\-]+)["\']', "\\2", matches, perl = TRUE)
    # Drop anchors/home-ish
    slugs <- setdiff(unique(slugs), c("", "index", "#about"))
    for (slug in slugs) {
      # Skip if it looks like an external fragment we didn't capture
      if (slug %in% known) next
      target <- file.path(OUT_DIR, paste0(slug, ".html"))
      if (!file.exists(target)) {
        broken <- c(broken, sprintf("%s -> /%s", basename(f), slug))
      }
    }
  }
  if (length(broken) > 0) {
    warning(
      "Dead internal links in built site:\n  - ",
      paste(unique(broken), collapse = "\n  - "),
      "\nFix the source .qmd (or publish the target article) before deploy."
    )
    cat("WARNING: ", length(unique(broken)), " dead internal link(s) detected.\n", sep = "")
  } else {
    cat("  internal-link check: OK\n")
  }
}

# ── Run all -----------------------------------------------------------------
cat("\nBuilding static site to", OUT_DIR, "\n")
build_favicon()
build_index()
build_articles_index()
build_article_pages()
build_standalone_pages()
source(file.path(PROJ_ROOT, "scripts/static_site_access.R"))
build_machine_access()
check_internal_links()

cat("\nDone. Deploy with:\n",
    "  rsync -av --delete static_site/ root@5.78.69.136:/var/www/globalpatientsafety/\n",
    sep = "")
