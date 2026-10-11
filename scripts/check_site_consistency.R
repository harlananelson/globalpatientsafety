#!/usr/bin/env Rscript
# Lightweight consistency checks for the static-site registries.
# Base R only — no renv, box, tibble, or rhino.
#
# Exit 0 if OK; exit 1 on any hard failure.
#
# Run:  Rscript --vanilla scripts/check_site_consistency.R
#   (--vanilla avoids project .Rprofile / renv bootstrap)

args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
script_path <- if (length(file_arg)) sub("^--file=", "", file_arg[1]) else NA_character_
PROJ_ROOT <- if (!is.na(script_path) && nzchar(script_path)) {
  normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
} else {
  getwd()
}

fail <- function(...) {
  cat("FAIL:", sprintf(...), "\n")
  quit(status = 1)
}
ok <- function(...) cat("OK:", sprintf(...), "\n")

# Parse app/logic/*.R that assign a tribble to SYMBOL, without loading box/tibble.
# Strips box::use(...) blocks and provides a base-R tribble().
load_tribble_file <- function(path, symbol) {
  if (!file.exists(path)) fail("missing %s", path)
  lines <- readLines(path, warn = FALSE)
  # Drop box::use( ... ) blocks (possibly multi-line)
  text <- paste(lines, collapse = "\n")
  text <- gsub("box::use\\s*\\([^)]*\\)", "", text, perl = TRUE)
  # tribble: ~col, val, val, ~col2, ...
  tribble <- function(...) {
    dots <- list(...)
    is_form <- vapply(dots, function(x) inherits(x, "formula"), logical(1))
    col_names <- vapply(dots[is_form], function(f) as.character(f[[2L]]), character(1))
    n_cols <- length(col_names)
    if (n_cols == 0L) stop("tribble: no columns")
    vals <- dots[!is_form]
    if (length(vals) %% n_cols != 0L) {
      stop("tribble: incomplete last row in ", path)
    }
    n_rows <- length(vals) / n_cols
    cols <- vector("list", n_cols)
    names(cols) <- col_names
    for (j in seq_len(n_cols)) {
      cells <- vals[seq(j, length(vals), by = n_cols)]
      # Preserve type of first non-NULL cell
      cols[[j]] <- unlist(cells, recursive = FALSE, use.names = FALSE)
    }
    as.data.frame(cols, stringsAsFactors = FALSE, optional = TRUE)
  }
  e <- new.env(parent = baseenv())
  e$tribble <- tribble
  # NA_character_ / TRUE / FALSE resolve from baseenv parent
  eval(parse(text = text), envir = e)
  if (!exists(symbol, envir = e, inherits = FALSE)) {
    fail("%s does not define %s", path, symbol)
  }
  get(symbol, envir = e, inherits = FALSE)
}

ARTICLES <- load_tribble_file(file.path(PROJ_ROOT, "app/logic/articles.R"), "ARTICLES")
TOOLS    <- load_tribble_file(file.path(PROJ_ROOT, "app/logic/tools.R"), "TOOLS")

# featured may come through as logical or character depending on parse
if (is.character(ARTICLES$featured)) {
  ARTICLES$featured <- ARTICLES$featured %in% c("TRUE", "true", "T", "1")
}

published <- ARTICLES[ARTICLES$status == "published", , drop = FALSE]
ok("%d published article(s), %d tool(s)", nrow(published), nrow(TOOLS))

for (i in seq_len(nrow(published))) {
  id <- published$id[[i]]
  html <- file.path(PROJ_ROOT, "app/static", paste0(id, ".html"))
  if (!file.exists(html)) {
    fail("published article '%s' has no app/static/%s.html", id, id)
  }
  ok("published %s → static HTML present", id)
}

feat <- ARTICLES[ARTICLES$featured %in% TRUE, , drop = FALSE]
if (nrow(feat) > 0) {
  for (i in seq_len(nrow(feat))) {
    if (!identical(as.character(feat$status[[i]]), "published")) {
      fail("featured article '%s' is not published", feat$id[[i]])
    }
  }
  ok("featured article(s) are published")
}

for (i in seq_len(nrow(TOOLS))) {
  row <- TOOLS[i, ]
  name <- as.character(row$name[[1]])
  status <- as.character(row$status[[1]])
  url <- as.character(row$url[[1]])
  if (identical(status, "live")) {
    if (is.na(url) || !nzchar(url)) {
      fail("live tool '%s' has no URL", name)
    }
    if (grepl("^/", url) && !grepl("^//", url)) {
      slug <- sub("^/", "", url)
      slug <- sub("/$", "", slug)
      target <- file.path(PROJ_ROOT, "app/static", paste0(slug, ".html"))
      if (!file.exists(target)) {
        fail("live tool '%s' points to /%s but app/static/%s.html missing",
             name, slug, slug)
      }
      ok("live tool %s → /%s present", name, slug)
    } else {
      ok("live tool %s → external %s", name, url)
    }
  }
}

methods_html <- file.path(PROJ_ROOT, "app/static/methods.html")
sig <- TOOLS[TOOLS$name == "Signal methods", , drop = FALSE]
if (nrow(sig) == 1L && file.exists(methods_html)) {
  if (identical(as.character(sig$status[[1]]), "coming_soon")) {
    fail("Signal methods is coming_soon but app/static/methods.html exists")
  }
  ok("Signal methods card matches shipped methods.html")
}

draft_ids <- ARTICLES$id[ARTICLES$status == "draft"]
standalone <- c("aems.html", "methods.html")
for (sf in standalone) {
  path <- file.path(PROJ_ROOT, "app/static", sf)
  if (!file.exists(path)) next
  txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
  for (did in draft_ids) {
    needles <- c(
      paste0('href="./', did, '"'),
      paste0("href='./", did, "'"),
      paste0('href="/', did, '"'),
      paste0("href='/", did, "'")
    )
    if (any(vapply(needles, function(n) grepl(n, txt, fixed = TRUE), logical(1)))) {
      fail("%s links to draft article '%s'", sf, did)
    }
  }
  ok("%s has no draft-article hrefs", sf)
}

site <- file.path(PROJ_ROOT, "static_site")
index_html <- file.path(site, "index.html")
# static_site/ is gitignored build output. CI checks registries against
# app/static and does not run the builder. After a local build, this block
# is the gate that the machine-access pages actually landed in the tree
# that gets rsynced.
if (!file.exists(index_html)) {
  ok("static_site/ not present; machine-access markers are checked after a local build")
  cat("\nAll consistency checks passed.\n")
  quit(status = 0)
}
index_txt <- paste(readLines(index_html, warn = FALSE), collapse = "\n")
markers <- c(
  'href="/pipeline"',
  'id="main"',
  'aria-label="Toggle navigation"',
  'rel="alternate"',
  "LLM / API access",
  "Machine path:"
)
for (needle in markers) {
  if (!grepl(needle, index_txt, fixed = TRUE)) {
    fail("static_site/index.html is missing %s", needle)
  }
}
ok("homepage has the pipeline link, skip target, and machine-access head")
for (f in c(
  "robots.txt", "sitemap.xml", "llms.txt", "openapi.json",
  "api.md", "chatgpt.md", "mcp.md", "methods.md", "pipeline.md",
  "accessibility.html", "api.html"
)) {
  if (!file.exists(file.path(site, f))) fail("static_site/%s is missing", f)
}
openapi_txt <- paste(readLines(file.path(site, "openapi.json"), warn = FALSE), collapse = "\n")
if (!grepl("/pipeline", openapi_txt, fixed = TRUE)) {
  fail("openapi.json does not describe /pipeline")
}
ok("machine-access files are in the built site")

cat("\nAll consistency checks passed.\n")
quit(status = 0)
