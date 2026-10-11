# Machine-access files and the accessibility statement.
# Sourced by scripts/build_static_site.R after the page shell exists.

shell_page <- function(title, description, page, body) {
  md <- if (identical(page, "/")) "/index.md" else paste0(page, ".md")
  paste0(
    site_head(title, description, page = page),
    skip_link,
    site_nav(),
    llm_banner(md),
    '<main id="main" tabindex="-1">\n',
    body,
    '\n</main>\n',
    site_foot
  )
}

write_out <- function(name, text) {
  path <- file.path(OUT_DIR, name)
  writeLines(text, path)
  cat("  wrote", path, "\n")
}

page_rows <- function() {
  rows <- list(
    list(path = "/", title = "Home",
         line = "Pharmacovigilance tools and signal analyses."),
    list(path = "/pipeline", title = "Pipeline analysis",
         line = "ClinicalTrials.gov studies for one lead sponsor. role=any includes collaborators. Registry facts, not a safety conclusion."),
    list(path = "/articles", title = "Articles",
         line = "Published signal analyses."),
    list(path = "/api", title = "API",
         line = "How to call GET /pipeline. FAERS signals stay on faers.mobi."),
    list(path = "/mcp", title = "MCP",
         line = "The hosted MCP server is https://faers.mobi/mcp and includes get_pipeline."),
    list(path = "/accessibility", title = "Accessibility",
         line = "WCAG 2.1 Level AA target, known exceptions, and a contact address.")
  )
  if (nrow(published)) {
    for (i in seq_len(nrow(published))) {
      rows[[length(rows) + 1]] <- list(
        path = paste0("/", published$id[[i]]),
        title = published$title[[i]],
        line = published$subtitle[[i]]
      )
    }
  }
  if (nrow(available_standalone)) {
    for (i in seq_len(nrow(available_standalone))) {
      id <- available_standalone$id[[i]]
      if (id %in% published$id) next
      rows[[length(rows) + 1]] <- list(
        path = paste0("/", id),
        title = available_standalone$title[[i]],
        line = available_standalone$title[[i]]
      )
    }
  }
  rows
}

build_robots <- function() {
  write_out("robots.txt", paste(
    "User-agent: *",
    "Allow: /",
    "",
    "Sitemap: https://globalpatientsafety.com/sitemap.xml",
    "# Machine index: https://globalpatientsafety.com/llms.txt",
    "",
    sep = "\n"
  ))
}

build_sitemap <- function(rows) {
  urls <- vapply(rows, function(row) {
    sprintf(
      "  <url><loc>https://globalpatientsafety.com%s</loc></url>",
      if (identical(row$path, "/")) "/" else row$path
    )
  }, character(1))
  write_out("sitemap.xml", paste0(
    '<?xml version="1.0" encoding="UTF-8"?>\n',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n',
    paste(urls, collapse = "\n"),
    "\n</urlset>\n"
  ))
}

build_llms <- function(rows) {
  lines <- c(
    "# Global Patient Safety",
    "",
    "Open pharmacovigilance tools and ClinicalTrials.gov pipeline reports.",
    "Hypotheses and registry facts, not causation and not medical advice.",
    "",
    "## Pages",
    ""
  )
  for (row in rows) {
    md <- if (identical(row$path, "/")) "/index.md" else paste0(row$path, ".md")
    lines <- c(lines, sprintf(
      "- [%s](https://globalpatientsafety.com%s): %s Markdown: https://globalpatientsafety.com%s",
      row$title, row$path, row$line, md
    ))
  }
  lines <- c(
    lines, "",
    "## Machine endpoints",
    "",
    "- GET https://globalpatientsafety.com/pipeline?sponsor=Sanofi — JSON studies whose lead sponsor matches. role=any includes collaborators",
    "- GET https://globalpatientsafety.com/pipeline?sponsor=Sanofi&format=brief — text/plain brief",
    "- GET https://faers.mobi/signals — FAERS disproportionality (a different service)",
    "- GET https://vaers.globalpatientsafety.com/signals?vaccine=COVID19&event=Myocarditis — VAERS reporting signals (a different service)",
    "- MCP https://faers.mobi/mcp — one server, tools get_pipeline and get_vaers plus the FAERS tools",
    "",
    "Disclaimer: registry facts from ClinicalTrials.gov are not efficacy or safety conclusions. FAERS signals are statistical patterns, not evidence of causation. VAERS counts are reporting, not incidence."
  )
  write_out("llms.txt", paste(lines, collapse = "\n"))
}

build_openapi <- function() {
  py <- file.path(PROJ_ROOT, "scripts/gps_pipeline.py")
  spec <- system2("python3", c(py, "--openapi"), stdout = TRUE)
  if (!length(spec)) stop("gps_pipeline.py --openapi produced nothing")
  write_out("openapi.json", paste(spec, collapse = "\n"))
}

api_md <- function() {
  paste(
    "# Global Patient Safety API",
    "",
    "Machine path: GET /pipeline?sponsor=",
    "",
    "Registry facts from ClinicalTrials.gov. Not efficacy or safety conclusions.",
    "FAERS signals are a different service: https://faers.mobi/api",
    "",
    "## GET /pipeline",
    "",
    "sponsor (required for JSON and brief): trimmed, then matched against the",
    "lead sponsor name. A family name that contains it counts, such as",
    "Sanofi Pasteur for Sanofi. It is not expanded to other companies.",
    "role (optional): omitted means lead. collaborator means collaborator only.",
    "any means lead or collaborator, which is the ClinicalTrials.gov sponsor search.",
    "Each study has role lead or collaborator. n_studies counts that same role.",
    "status (optional): omitted means ongoing studies (RECRUITING,",
    "ENROLLING_BY_INVITATION, NOT_YET_RECRUITING, ACTIVE_NOT_RECRUITING).",
    "ALL means every status. Or one of RECRUITING, ENROLLING_BY_INVITATION,",
    "NOT_YET_RECRUITING, ACTIVE_NOT_RECRUITING, COMPLETED, SUSPENDED, TERMINATED,",
    "WITHDRAWN, UNKNOWN, AVAILABLE, NO_LONGER_AVAILABLE, TEMPORARILY_NOT_AVAILABLE,",
    "APPROVED_FOR_MARKETING, WITHHELD.",
    "phase (optional): EARLY_PHASE1, PHASE1, PHASE2, PHASE3, PHASE4, NA.",
    "limit (optional): default 50, maximum 200.",
    "pageToken (optional): the next_page_token from a previous response.",
    "format (optional): json, brief, or html.",
    "With format omitted, a client that sends Accept: text/html gets HTML.",
    "Any other client gets JSON.",
    "",
    "n_studies is the registry total. by_phase and by_status count only the",
    "studies in this response (counts_of is \"returned\").",
    "An unknown sponsor is HTTP 200 with n_studies 0 and studies [].",
    "If ClinicalTrials.gov does not respond, the status is 503.",
    "If it returns an error, the status is 502.",
    "Those error bodies have error and source, and no NCT ids.",
    "",
    "## Examples",
    "",
    "curl -sS 'https://globalpatientsafety.com/pipeline?sponsor=Sanofi'",
    "curl -sS 'https://globalpatientsafety.com/pipeline?sponsor=Sanofi&role=any'",
    "curl -sS 'https://globalpatientsafety.com/pipeline?sponsor=Sanofi&format=brief'",
    "curl -sS -H 'Accept: text/html' 'https://globalpatientsafety.com/pipeline?sponsor=Sanofi'",
    "",
    "OpenAPI: https://globalpatientsafety.com/openapi.json",
    "MCP: https://faers.mobi/mcp (tool get_pipeline). See /mcp.md",
    "",
    sep = "\n"
  )
}

mcp_md <- function() {
  paste(
    "# MCP",
    "",
    "One hosted server, on faers.mobi. This site does not run a second one.",
    "",
    "URL: https://faers.mobi/mcp",
    "Transport: Streamable HTTP. Auth: none.",
    "Tool: get_pipeline(sponsor, status, phase, limit, role)",
    "It calls GET https://globalpatientsafety.com/pipeline?format=json",
    "and returns registry facts. It does not turn those facts into a FAERS signal.",
    "Omitted role is lead sponsor. role=any includes collaborator-only trials.",
    "",
    "The same server still has the FAERS tools (get_signal, and the rest).",
    "Install notes: https://faers.mobi/mcp.md",
    "",
    "```json",
    "{",
    '  "mcpServers": {',
    '    "faers-mobi": { "url": "https://faers.mobi/mcp" }',
    "  }",
    "}",
    "```",
    "",
    sep = "\n"
  )
}

chatgpt_md <- function() {
  paste(
    "# ChatGPT",
    "",
    "Schema: https://globalpatientsafety.com/openapi.json",
    "FAERS schema (separate): https://faers.mobi/openapi.json",
    "",
    "Custom GPT: Actions, import the schema, authentication none.",
    "",
    "Instructions you can paste:",
    "",
    "Use getPipeline when the question is what a company is studying,",
    "or how many of its trials are in a phase or status.",
    "Pass the company name as sponsor. The default role is lead sponsor.",
    "Pass role=any to include collaborator-only trials. Do not invent NCT ids.",
    "If the call fails, say ClinicalTrials.gov was unavailable.",
    "Say that the rows are registry facts, not evidence a drug works or is safe.",
    "For an adverse-event signal, use https://faers.mobi/openapi.json instead.",
    "",
    sep = "\n"
  )
}

access_md <- function() {
  paste(
    "# Accessibility",
    "",
    "Target: WCAG 2.1 Level AA.",
    "Status: partial, reviewed 2026-10-10.",
    "",
    "This static site has a skip link, a main landmark, labelled pipeline",
    "controls, table captions, and text colours aimed at 4.5:1.",
    "Known exceptions: some article heat-map cells sit just under 4.5:1,",
    "chart descriptions are generated from the heading above the figure",
    "rather than from an author-written fig-alt, and there has not been a",
    "screen-reader pass. faers.mobi is a separate site and is not covered here.",
    "",
    "Contact: harlananelson@gmail.com",
    "We read that mailbox at least once a week.",
    "",
    sep = "\n"
  )
}

twin_md <- function(title, line, path) {
  paste(
    paste0("# ", title),
    "",
    "Machine path: GET /pipeline?sponsor= on this site, and GET https://faers.mobi/signals for FAERS signals.",
    "",
    line,
    "",
    paste0("Full page: https://globalpatientsafety.com", path),
    "",
    "Signals are statistical patterns, not evidence of causation. Not medical advice.",
    "A pipeline report is a ClinicalTrials.gov registry fact, not a safety conclusion.",
    "",
    sep = "\n"
  )
}

build_machine_access <- function() {
  rows <- page_rows()
  build_robots()
  build_sitemap(rows)
  build_llms(rows)
  build_openapi()

  write_out("api.md", api_md())
  write_out("API.md", api_md())
  write_out("api.html", shell_page(
    "API — Global Patient Safety",
    "Documents GET /pipeline, including JSON, format=brief, and what a registry outage returns.",
    "/api",
    paste0(
      '<article class="container py-4">\n',
      '<h1>API</h1>\n',
      '<p>', esc(MACHINE_SENTENCE), '</p>\n',
      '<p>Registry facts from ClinicalTrials.gov. Not efficacy or safety conclusions. ',
      'FAERS signals are a different service: <a href="https://faers.mobi/api">faers.mobi/api</a>.</p>\n',
      '<h2>GET /pipeline</h2>\n',
      '<p><code>sponsor</code> is required for JSON and for a brief. It is trimmed and matched against the lead sponsor name. A family name that contains it counts. It is not expanded to other companies.</p>\n',
      '<p><code>role</code> defaults to <code>lead</code>. <code>collaborator</code> is collaborator-only. <code>any</code> is lead or collaborator. Each study row says which one. <code>n_studies</code> counts that same role.</p>\n',
      '<p>With no <code>status</code>, the list is ongoing studies. <code>status=ALL</code> includes completed and stopped trials. <code>phase</code> is optional. <code>limit</code> defaults to 50 and stops at 200.</p>\n',
      '<p><code>format</code> is <code>json</code>, <code>brief</code> (text/plain), or <code>html</code>. With no format, a browser gets HTML and other clients get JSON.</p>\n',
      '<p><code>n_studies</code> is the registry total. Phase and status counts cover only the studies in that response.</p>\n',
      '<p>An unknown sponsor is HTTP 200 with <code>n_studies</code> 0. If ClinicalTrials.gov does not respond the status is 503. If it returns an error the status is 502. Those bodies contain no NCT ids.</p>\n',
      '<h2>Examples</h2>\n',
      '<pre tabindex="0">curl -sS \'https://globalpatientsafety.com/pipeline?sponsor=Sanofi\'\n',
      'curl -sS \'https://globalpatientsafety.com/pipeline?sponsor=Sanofi&amp;role=any\'\n',
      'curl -sS \'https://globalpatientsafety.com/pipeline?sponsor=Sanofi&amp;format=brief\'</pre>\n',
      '<p><a href="/openapi.json">OpenAPI</a> · <a href="/mcp.md">MCP</a> · <a href="/chatgpt.md">ChatGPT</a> · <a href="/api.md">Markdown</a></p>\n',
      '</article>'
    )
  ))

  write_out("mcp.md", mcp_md())
  write_out("mcp.html", shell_page(
    "MCP — Global Patient Safety",
    "How to connect to the one hosted MCP server, which includes get_pipeline.",
    "/mcp",
    paste0(
      '<article class="container py-4">\n<h1>MCP</h1>\n',
      '<p>One hosted server, on faers.mobi. This site does not run a second one.</p>\n',
      '<p>URL: <a href="https://faers.mobi/mcp">https://faers.mobi/mcp</a>. Streamable HTTP. No API key.</p>\n',
      '<p>The tool <code>get_pipeline</code> takes a sponsor and calls ',
      '<code>GET /pipeline?format=json</code> on this site. Omitted role is lead sponsor. <code>role=any</code> includes collaborator-only trials. The result is a registry list, not a FAERS signal.</p>\n',
      '<p>Install notes for the FAERS tools on the same server: <a href="https://faers.mobi/mcp.md">faers.mobi/mcp.md</a>.</p>\n',
      '<pre tabindex="0">{ "mcpServers": { "faers-mobi": { "url": "https://faers.mobi/mcp" } } }</pre>\n',
      '</article>'
    )
  ))

  write_out("chatgpt.md", chatgpt_md())
  write_out("accessibility.md", access_md())
  write_out("accessibility.html", shell_page(
    "Accessibility — Global Patient Safety",
    "WCAG 2.1 Level AA target, partial conformance, exceptions, and a contact address.",
    "/accessibility",
    paste0(
      '<article class="container py-4">\n<h1>Accessibility</h1>\n',
      '<p>Target standard: WCAG 2.1 Level AA. Status: partial. Last review: 2026-10-10.</p>\n',
      '<p>This site has a skip link, one main landmark, a labelled pipeline form, tables with captions, and text colours chosen to clear 4.5:1.</p>\n',
      '<h2>Known exceptions</h2>\n<ul>\n',
      '<li>Some heat-map cells in older articles sit just under 4.5:1.</li>\n',
      '<li>Chart text alternatives are taken from the heading above the figure, not from an author-written fig-alt.</li>\n',
      '<li>Nobody has done a screen-reader pass yet.</li>\n',
      '<li>faers.mobi is a separate site and is not covered by this page.</li>\n</ul>\n',
      '<h2>Contact</h2>\n',
      '<p><a href="mailto:harlananelson@gmail.com">harlananelson@gmail.com</a>. We read that mailbox at least once a week.</p>\n',
      '</article>'
    )
  ))

  write_out("pipeline.md", twin_md(
    "Pipeline analysis",
    paste(
      "GET /pipeline?sponsor= returns ClinicalTrials.gov studies for one company.",
      "format=brief is text/plain. format=html is the same page a browser shows.",
      "An unknown sponsor is an empty list, not an error.",
      "If the registry is down the response is 502 or 503 and contains no NCT ids.",
      api_md(),
      sep = "\n"
    ),
    "/pipeline"
  ))
  write_out("index.md", twin_md(
    "Global Patient Safety",
    "Open tools for pharmacovigilance, plus a ClinicalTrials.gov pipeline report for one sponsor.",
    "/"
  ))
  write_out("articles.md", twin_md(
    "Articles",
    "Published signal analyses. Drafts are not on this site.",
    "/articles"
  ))
  for (row in rows) {
    md_name <- if (identical(row$path, "/")) "index.md" else paste0(sub("^/", "", row$path), ".md")
    dest <- file.path(OUT_DIR, md_name)
    if (file.exists(dest)) next
    write_out(md_name, twin_md(row$title, row$line, row$path))
  }
}
