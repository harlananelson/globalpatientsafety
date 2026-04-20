# globalpatientsafety.com — Clearing house / portal for the tool suite.
#
# Renders a landing page with cards linking to each tool. Extend by appending
# a row to the TOOLS tibble in app/logic/tools.R — the portal module picks it
# up automatically.

box::use(
  shiny[
    moduleServer, NS, tags, div, h1, h2, h3, p, a, hr
  ],
  bslib[bs_theme, page_fluid],
)

box::use(
  app/view/portal,
)

#' @export
ui <- function(id) {
  ns <- NS(id)
  page_fluid(
    theme = bs_theme(bootswatch = "flatly"),

    # Hero
    div(
      class = "bg-primary text-white py-5 mb-4",
      div(
        class = "container text-center",
        h1("Global Patient Safety", class = "display-4 fw-light mb-3"),
        p(
          "Open tools for pharmacovigilance signal detection and clinical research acceleration.",
          class = "lead mb-0"
        )
      )
    ),

    # Tool cards
    div(
      class = "container",
      h2("Tools", class = "mb-4"),
      portal$ui(ns("tools")),

      hr(class = "my-5"),

      div(
        class = "row",
        div(
          class = "col-md-8",
          h2("About"),
          p(
            "Global Patient Safety is a growing suite of open-source tools ",
            "for pharmacovigilance and clinical research. The tools share a ",
            "common philosophy: signal detection produces hypotheses, not ",
            "conclusions; cohort construction should be transparent and ",
            "auditable; and clinical data work should be reproducible on a ",
            "researcher's laptop."
          ),
          p(
            "Built by ",
            a("Harlan A. Nelson", href = "https://harlananelson.com", target = "_blank"),
            ". Source code on ",
            a("GitHub", href = "https://github.com/harlananelson", target = "_blank"),
            "."
          )
        ),
        div(
          class = "col-md-4",
          h3("Disclaimer"),
          p(
            tags$small(
              "Signals detected by these tools are statistical patterns in ",
              "spontaneous reporting data, not evidence of causation. ",
              "Outputs are hypotheses requiring further investigation."
            )
          )
        )
      )
    ),

    div(
      class = "bg-light py-4 mt-5 text-center text-muted",
      tags$small(
        "globalpatientsafety.com — clearing house for open clinical-data tools."
      )
    )
  )
}

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    portal$server("tools")
  })
}
