# globalpatientsafety.com — Broader Safety Metrics Dashboard

box::use(
  shiny[bootstrapPage, moduleServer, NS, tags, div, fluidPage, navbarPage,
        tabPanel, fileInput, reactive, req, observeEvent, h4, p, hr,
        fluidRow, column, selectInput],
)

box::use(
  app/view/signal_table,
)

#' @export
ui <- function(id) {
  ns <- NS(id)
  navbarPage(
    title = "Global Patient Safety",
    theme = bslib::bs_theme(bootswatch = "united"),
    tabPanel("Signal Detection",
      fluidPage(
        div(class = "container-fluid", style = "padding-top: 20px;",
          fluidRow(
            column(12,
              h4("Bayesian Safety Signal Detection"),
              p("Upload adverse event reporting data from any source to detect ",
                "disproportionate signals using Gamma-Poisson shrinkage."),
              hr()
            )
          ),
          fluidRow(
            column(4,
              fileInput(ns("data_file"), "Upload data (CSV):", accept = ".csv")
            ),
            column(4,
              selectInput(ns("data_source"), "Data source:",
                          choices = c("FAERS (Drugs)" = "faers",
                                      "VAERS (Vaccines)" = "vaers",
                                      "MAUDE (Devices)" = "maude",
                                      "EudraVigilance" = "eudra",
                                      "VigiBase (WHO)" = "vigibase",
                                      "Custom" = "custom"))
            ),
            column(4,
              p(tags$strong("Expected columns:"), " product, event"),
              p("Each row = one adverse event report.")
            )
          ),
          signal_table$ui(ns("signals"))
        )
      )
    ),
    tabPanel("About",
      fluidPage(
        div(style = "max-width: 800px; margin: 40px auto;",
          tags$h2("Global Patient Safety"),
          tags$p("A platform for pharmacovigilance signal detection across ",
                 "multiple international adverse event reporting systems."),
          tags$h3("Supported Data Sources"),
          tags$ul(
            tags$li(tags$strong("FAERS"), " — FDA Adverse Event Reporting System (US drugs)"),
            tags$li(tags$strong("VAERS"), " — Vaccine Adverse Event Reporting System (US vaccines)"),
            tags$li(tags$strong("MAUDE"), " — FDA device reports"),
            tags$li(tags$strong("EudraVigilance"), " — European Medicines Agency"),
            tags$li(tags$strong("VigiBase"), " — WHO global ICSR database")
          ),
          tags$h3("Statistical Method"),
          tags$ul(
            tags$li("Prior: 2-component Gamma mixture fitted via EM algorithm"),
            tags$li("Posterior: full Gamma mixture with percentile-based signal detection"),
            tags$li("Reference: DuMouchel (1999), American Statistician 53(3)")
          )
        )
      )
    )
  )
}

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    uploaded_data <- reactive({
      req(input$data_file)
      utils::read.csv(input$data_file$datapath, stringsAsFactors = FALSE)
    })

    signal_table$server("signals", data = uploaded_data)
  })
}
