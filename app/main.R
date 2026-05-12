# globalpatientsafety.com — Portal, Articles, and About.
#
# Navigation:
#   Home      — hero + featured article card + tool grid
#   Articles  — article index cards
#   <article> — individual article tabs, added dynamically
#   About     — project background

box::use(
  shiny[
    NS, moduleServer, navbarPage, tabPanel, insertTab, showTab,
    updateNavbarPage, observeEvent, reactive, tags, div, p, a, span,
    h2, h3, h4, hr, HTML, tagList
  ],
  bslib[bs_theme, font_google],
)

box::use(
  app/view/portal,
  app/view/articles,
  app/view/article_covid_vaccine,
  app/logic/articles[ARTICLES],
)

# ── Featured article card shown on the Home tab ───────────────────────────────

.featured_article_card <- function(ns) {
  featured <- ARTICLES[ARTICLES$featured == TRUE & ARTICLES$status == "published", ][1, ]
  if (nrow(featured) == 0) return(NULL)

  div(
    class = "card border-primary mb-5",
    div(class = "card-header bg-primary text-white fw-semibold",
      "★ Featured Article"
    ),
    div(class = "card-body",
      tags$h5(class = "card-title", featured$title),
      p(class = "text-muted small mb-2", featured$date),
      p(class = "card-text", featured$subtitle),
      tags$button(
        class   = "btn btn-primary btn-sm",
        onclick = sprintf(
          "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
          ns("open_featured"), featured$id
        ),
        "Read article →"
      )
    )
  )
}

# ── UI ────────────────────────────────────────────────────────────────────────

#' @export
ui <- function(id) {
  ns <- NS(id)

  navbarPage(
    title     = tagList(
      tags$span("Global", style = "color:#4aa8d8;"),
      " Patient Safety"
    ),
    id        = ns("nav"),
    theme     = bs_theme(
      version     = 5,
      bg          = "#f8fafc",
      fg          = "#1a2332",
      primary     = "#1a6b9a",
      "navbar-bg" = "#1a2332",
      base_font   = font_google("Inter")
    ),
    collapsible = TRUE,
    fluid       = TRUE,
    header = tags$style(HTML("
      .navbar-brand { font-weight: 500; letter-spacing: -0.02em; }
      .nav-link     { font-size: 0.9rem; }
    ")),

    # ── Home ─────────────────────────────────────────────────────────────────
    tabPanel(
      "Home", value = "home",
      # Hero
      div(
        class = "bg-primary text-white py-5 mb-4",
        div(
          class = "container text-center",
          tags$h1("Global Patient Safety", class = "display-4 fw-light mb-3"),
          p(class = "lead mb-0",
            "Open tools for pharmacovigilance signal detection ",
            "and clinical research acceleration.")
        )
      ),
      div(
        class = "container",
        # Featured article
        .featured_article_card(ns),
        # Tool grid
        h2("Tools", class = "mb-4 fw-light"),
        portal$ui(ns("portal")),
        hr(class = "my-5"),
        div(
          class = "row",
          div(
            class = "col-md-8",
            h2("About", class = "fw-light"),
            p("Global Patient Safety is a growing suite of open-source tools for ",
              "pharmacovigilance and clinical research. Signal detection produces ",
              "hypotheses, not conclusions; cohort construction should be transparent ",
              "and auditable; and clinical data work should be reproducible."),
            p("Built by ",
              a("Harlan A. Nelson", href = "https://harlananelson.com", target = "_blank"),
              ". Source on ",
              a("GitHub", href = "https://github.com/harlananelson", target = "_blank"), ".")
          ),
          div(
            class = "col-md-4",
            h3("Disclaimer", class = "fw-light"),
            p(tags$small(class = "text-muted",
              "Signals are statistical patterns in spontaneous reporting data, ",
              "not evidence of causation. Outputs are hypotheses requiring further investigation."))
          )
        )
      ),
      div(
        class = "bg-light py-4 mt-5 text-center text-muted",
        tags$small("globalpatientsafety.com")
      )
    ),

    # ── Articles index ────────────────────────────────────────────────────────
    tabPanel(
      "Articles", value = "articles",
      articles$ui(ns("articles"))
    ),

    # ── Individual article tabs (pre-rendered, hidden until opened) ───────────
    tabPanel(
      "COVID-19 Vaccine Signals",
      value = "article_covid_vaccine",
      article_covid_vaccine$ui(ns("article_covid_vaccine"))
    ),

    # ── About ─────────────────────────────────────────────────────────────────
    tabPanel(
      "About", value = "about",
      div(
        class = "container py-5",
        style = "max-width: 760px;",
        div(class = "mb-4",
          tags$h2("About Global Patient Safety", class = "fw-light mb-3"),
          p(class = "lead text-muted",
            "We analyse 35 years of FDA and CDC adverse-event data using ",
            "peer-reviewed Bayesian statistics to surface drug safety signals ",
            "that matter to patients and clinicians."),
          tags$hr()
        ),
        div(class = "row g-4 mb-5",
          div(class = "col-md-4",
            div(class = "p-3",
              tags$h5("Data sources", class = "fw-semibold mb-2"),
              tags$ul(class = "text-muted small",
                tags$li("FDA FAERS (2018–2024)"),
                tags$li("CDC VAERS (1990–2025)")
              )
            )
          ),
          div(class = "col-md-4",
            div(class = "p-3",
              tags$h5("Methods", class = "fw-semibold mb-2"),
              tags$ul(class = "text-muted small",
                tags$li("GPS — 5th-percentile credible bound of two-component Gamma mixture posterior (DuMouchel 1999 framework). EB05 is a direct posterior quantile on the linear RR scale, not the EBGM geometric mean."),
                tags$li("PRR, ROR, BCPNN/IC"),
                tags$li("Flagged by ≥2 of 4 methods")
              )
            )
          ),
          div(class = "col-md-4",
            div(class = "p-3",
              tags$h5("Privacy", class = "fw-semibold mb-2"),
              p(class = "text-muted small",
                "No data is stored. No account required.")
            )
          )
        ),
        div(class = "mb-4",
          tags$h5("Related tools", class = "fw-semibold mb-2"),
          div(class = "d-flex gap-3 flex-wrap",
            a("faers.mobi",  href = "https://faers.mobi",  target = "_blank", class = "btn btn-outline-secondary btn-sm"),
            a("aers.mobi",   href = "https://aers.mobi",   target = "_blank", class = "btn btn-outline-secondary btn-sm"),
            a("vaers.globalpatientsafety.com",
              href = "https://vaers.globalpatientsafety.com", target = "_blank",
              class = "btn btn-outline-secondary btn-sm")
          )
        ),
        div(class = "text-muted small",
          "© Global Patient Safety. Data: public domain (FDA, CDC). ",
          "Method: ",
          a("GPS framework (DuMouchel 1999)", href = "https://doi.org/10.1177/009286159903300105", target = "_blank"),
          ". EB05 is the 5th-percentile of the dual-Gamma posterior (linear RR scale), not the EBGM geometric mean. Not medical advice."
        )
      )
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    portal$server("portal")
    article_covid_vaccine$server("article_covid_vaccine")

    # Navigate to an article tab by id
    nav_to_article <- function(article_id) {
      tab_value <- paste0("article_", article_id)
      updateNavbarPage(session, "nav", selected = tab_value)
    }

    articles$server("articles", switch_to_article = nav_to_article)

    # Featured article button on Home tab
    observeEvent(input$open_featured, {
      nav_to_article(input$open_featured)
    })
  })
}
