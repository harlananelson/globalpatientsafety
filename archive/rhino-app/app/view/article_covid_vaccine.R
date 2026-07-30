# COVID-19 Vaccine VAERS Safety Signals — article view module.
#
# Renders inline using the same signals data as gps-patient.
# Data path is resolved at runtime; falls back gracefully if absent.

box::use(
  shiny[...],
)

SIGNALS_PATH <- "/srv/shiny-server/gps-patient/data/signals_vaers.parquet"
FIRST_SEEN_PATH <- "/srv/shiny-server/gps-patient/data/covid_first_seen.parquet"

.load_covid <- function() {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    return(NULL)
  }
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    return(NULL)
  }
  if (!file.exists(SIGNALS_PATH)) {
    return(NULL)
  }

  vaers_raw <- arrow::open_dataset(SIGNALS_PATH) |> dplyr::collect()

  label_vaccine <- function(drug) {
    dplyr::case_when(
      grepl("PFIZER.*BIVALENT|BIVALENT.*PFIZER", drug, ignore.case = TRUE) ~ "Pfizer Bivalent",
      grepl("MODERNA.*BIVALENT|BIVALENT.*MODERNA", drug, ignore.case = TRUE) ~ "Moderna Bivalent",
      grepl("PFIZER|BIONTECH|COMIRNATY", drug, ignore.case = TRUE) ~ "Pfizer-BioNTech",
      grepl("MODERNA|SPIKEVAX|MNEXSPIKE", drug, ignore.case = TRUE) ~ "Moderna",
      grepl("JANSSEN|JOHNSON", drug, ignore.case = TRUE) ~ "Janssen (J&J)",
      grepl("NOVAVAX", drug, ignore.case = TRUE) ~ "Novavax",
      TRUE ~ "Unknown"
    )
  }

  covid <- vaers_raw |>
    dplyr::filter(grepl("COVID|SARS|BNT|MRNA", drug, ignore.case = TRUE)) |>
    dplyr::mutate(vaccine = label_vaccine(drug))

  first_seen <- if (file.exists(FIRST_SEEN_PATH)) {
    arrow::open_dataset(FIRST_SEEN_PATH) |>
      dplyr::collect() |>
      dplyr::mutate(vaccine = label_vaccine(drug))
  } else {
    NULL
  }

  list(covid = covid, first_seen = first_seen)
}

VACCINE_COLOURS <- c(
  "Pfizer-BioNTech"  = "#1a6b9a",
  "Moderna"          = "#e05f2a",
  "Janssen (J&J)"    = "#2e8b57",
  "Pfizer Bivalent"  = "#6baed6",
  "Moderna Bivalent" = "#fd8d3c",
  "Novavax"          = "#756bb1",
  "Unknown"          = "#bdbdbd"
)

# ── Plots ─────────────────────────────────────────────────────────────────────

.plot_thrombosis <- function(covid) {
  thromb <- covid |>
    dplyr::filter(
      grepl("thrombo|embol|clot|coagul|disseminated|purpura|platelet|heparin|anti-platelet",
        event,
        ignore.case = TRUE
      ),
      n_methods_flagged >= 2, eb05 > 2
    ) |>
    dplyr::mutate(event = stringr::str_trunc(event, 55))

  ggplot2::ggplot(
    thromb,
    ggplot2::aes(eb05, forcats::fct_reorder(event, eb05),
      colour = vaccine, size = n_methods_flagged
    )
  ) +
    ggplot2::geom_point(alpha = 0.85) +
    ggplot2::scale_colour_manual(values = VACCINE_COLOURS) +
    ggplot2::scale_size_continuous(range = c(2, 6), breaks = 2:4) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      x = "EB05 (log scale)", y = NULL,
      colour = "Vaccine", size = "Methods",
      title = "Thrombotic Signals — COVID-19 Vaccines"
    ) +
    ggplot2::theme_minimal(base_size = 13) +
    ggplot2::theme(
      axis.text.y     = ggplot2::element_text(size = 10),
      legend.position = "right"
    )
}

.plot_cardiac <- function(covid) {
  cardiac <- covid |>
    dplyr::filter(
      grepl("myocard|pericard|cardiac|heart|tachycard|arrhyth|infarct|fibrillat",
        event,
        ignore.case = TRUE
      ),
      n_methods_flagged >= 2, eb05 > 2
    ) |>
    dplyr::arrange(dplyr::desc(eb05)) |>
    dplyr::slice_head(n = 20) |>
    dplyr::mutate(event = stringr::str_trunc(event, 50))

  ggplot2::ggplot(
    cardiac,
    ggplot2::aes(eb05, forcats::fct_reorder(event, eb05),
      colour = vaccine, size = n_methods_flagged
    )
  ) +
    ggplot2::geom_point(alpha = 0.85) +
    ggplot2::scale_colour_manual(values = VACCINE_COLOURS) +
    ggplot2::scale_size_continuous(range = c(2, 6), breaks = 2:4) +
    ggplot2::scale_x_log10() +
    ggplot2::labs(
      x = "EB05 (log scale)", y = NULL,
      colour = "Vaccine", size = "Methods",
      title = "Top 20 Cardiac Signals — COVID-19 Vaccines"
    ) +
    ggplot2::theme_minimal(base_size = 13)
}

.plot_emergence <- function(covid, first_seen) {
  if (is.null(first_seen)) {
    return(NULL)
  }

  top_events <- covid |>
    dplyr::filter(n_methods_flagged >= 2) |>
    dplyr::group_by(event) |>
    dplyr::summarise(max_eb05 = max(eb05), .groups = "drop") |>
    dplyr::arrange(dplyr::desc(max_eb05)) |>
    dplyr::slice_head(n = 35) |>
    dplyr::pull(event)

  first_seen |>
    dplyr::filter(event %in% top_events) |>
    dplyr::mutate(
      event = stringr::str_trunc(event, 50),
      first_date = as.Date(paste0(
        stringr::str_extract(first_quarter, "^\\d{4}"), "-",
        sprintf("%02d", (as.integer(stringr::str_extract(first_quarter, "\\d$")) - 1L) * 3L + 1L),
        "-01"
      ))
    ) |>
    ggplot2::ggplot(
      ggplot2::aes(first_date, forcats::fct_reorder(event, first_date, min),
        colour = vaccine
      )
    ) +
    ggplot2::geom_point(size = 3, alpha = 0.85) +
    ggplot2::scale_colour_manual(values = VACCINE_COLOURS) +
    ggplot2::scale_x_date(date_breaks = "6 months", date_labels = "%Y Q%q") +
    ggplot2::labs(
      x = "First quarter flagged", y = NULL,
      colour = "Vaccine",
      title = "Signal Emergence Timeline — Top 35 Signals"
    ) +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 35, hjust = 1),
      axis.text.y = ggplot2::element_text(size = 10)
    )
}

# ── UI ────────────────────────────────────────────────────────────────────────

#' @export
ui <- function(id) {
  tagList(
    div(
      class = "d-flex justify-content-end align-items-center px-3 py-2 bg-light border-bottom",
      style = "gap: 0.5rem;",
      tags$span(class = "text-muted small", "Share this article:"),
      tags$button(
        class = "btn btn-sm btn-outline-secondary",
        type = "button",
        onclick = paste0(
          "navigator.clipboard.writeText(window.location.href);",
          "this.textContent='✓ Copied'; ",
          "setTimeout(()=>{this.textContent='Copy link';}, 1500);"
        ),
        "Copy link"
      )
    ),
    tags$iframe(
      src    = "static/covid_vaccine.html",
      style  = "width:100%; height:calc(100vh - 50px); border:none;",
      title  = "COVID-19 Vaccine Safety Signals in VAERS"
    )
  )
}

.ui_shiny <- function(id) {
  ns <- NS(id)
  div(
    class = "container py-4",
    style = "max-width: 900px;",

    # Header
    div(
      class = "mb-4",
      tags$h2("COVID-19 Vaccine Safety Signals in VAERS",
        class = "fw-light mb-2"
      ),
      p(
        class = "lead text-muted",
        "Bayesian disproportionality analysis across nine vaccine products"
      ),
      p(
        class = "text-muted small",
        "Global Patient Safety · 2026-05-04 · ",
        tags$a("VAERS methodology", href = "#methods")
      )
    ),

    # Callout
    div(
      class = "alert alert-info",
      tags$strong("Note: "),
      "VAERS is a passive surveillance system. Signals indicate statistical ",
      "disproportionality within the reporting database, not established causation."
    ),

    # Overview
    h3("Overview", class = "mt-4 mb-3 fw-light"),
    uiOutput(ns("overview_table")),

    # TTS
    h3("Thrombosis with Thrombocytopenia Syndrome (TTS)",
      class = "mt-5 mb-2 fw-light"
    ),
    p(
      "Janssen (J&J) shows EB05 = 18.4 flagged by all four methods for TTS — the ",
      "dominant product-specific signal in the dataset, corroborating the regulatory ",
      "findings that led to Janssen's restricted and eventually discontinued use."
    ),
    plotOutput(ns("plot_thrombosis"), height = "580px"),

    # Cardiac
    h3("Cardiac Signals", class = "mt-5 mb-2 fw-light"),
    p(
      "Immune-mediated myocarditis shows EB05 = 36.5 (attributed to 'Unknown' vaccine — ",
      "likely mRNA doses without recorded manufacturer). The Pfizer Bivalent booster ",
      "shows a cluster of cardiac monitoring events all flagged by 4 methods."
    ),
    plotOutput(ns("plot_cardiac"), height = "460px"),

    # Emergence timeline
    h3("Signal Emergence Timeline", class = "mt-5 mb-2 fw-light"),
    p(
      "The quarter each signal first crossed the ≥2-method threshold. Early 2021 ",
      "signals reflect the initial post-authorisation period; later emergence indicates ",
      "booster/bivalent-specific events or rare outcomes requiring larger denominators."
    ),
    plotOutput(ns("plot_emergence"), height = "560px"),

    # Summary table
    h3("Signal Summary by Vaccine", class = "mt-5 mb-3 fw-light"),
    uiOutput(ns("summary_table")),

    # Methods
    tags$hr(class = "my-5"),
    h4("Methods", id = "methods", class = "fw-light mb-3"),
    tags$ul(
      class = "text-muted",
      tags$li(tags$strong("GPS"), " — Gamma-Poisson Shrinker (DuMouchel 1999). EB05 is the 5th-percentile credible lower bound of the two-component Gamma mixture posterior on the linear RR scale — a direct posterior quantile, not the EBGM geometric mean (which uses a log transformation). EB05 > 2."),
      tags$li(tags$strong("PRR"), " — Proportional Reporting Ratio. PRR > 2, χ² > 4, n ≥ 3."),
      tags$li(tags$strong("ROR"), " — Reporting Odds Ratio. Lower 95% CI > 1."),
      tags$li(tags$strong("BCPNN/IC"), " — Information Component. IC₀₂₅ > 0.")
    ),
    p(
      class = "text-muted small",
      "Data: CDC VAERS 1990–present (public domain). ",
      "Implementation: safetysignal R package."
    )
  )
}

# ── Server ────────────────────────────────────────────────────────────────────

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    data <- shiny::reactive({
      .load_covid()
    })

    output$overview_table <- renderUI({
      d <- req(data())
      covid <- d$covid

      rows <- covid |>
        dplyr::group_by(vaccine) |>
        dplyr::summarise(
          Pairs = dplyr::n(),
          `≥2 methods` = sum(n_methods_flagged >= 2),
          `≥3 methods` = sum(n_methods_flagged >= 3),
          `4 methods` = sum(n_methods_flagged >= 4),
          `Max EB05` = round(max(eb05, na.rm = TRUE), 1),
          .groups = "drop"
        ) |>
        dplyr::arrange(dplyr::desc(`≥2 methods`))

      tags$table(
        class = "table table-sm table-striped",
        tags$thead(tags$tr(lapply(names(rows), tags$th))),
        tags$tbody(
          lapply(seq_len(nrow(rows)), function(i) {
            tags$tr(lapply(as.character(rows[i, ]), tags$td))
          })
        )
      )
    })

    output$plot_thrombosis <- renderPlot({
      d <- req(data())
      .plot_thrombosis(d$covid)
    })

    output$plot_cardiac <- renderPlot({
      d <- req(data())
      .plot_cardiac(d$covid)
    })

    output$plot_emergence <- renderPlot({
      d <- req(data())
      .plot_emergence(d$covid, d$first_seen)
    })

    output$summary_table <- renderUI({
      d <- req(data())
      first_seen <- d$first_seen

      if (is.null(first_seen)) {
        return(p("First-seen data not available."))
      }

      rows <- first_seen |>
        dplyr::group_by(vaccine) |>
        dplyr::summarise(
          `Earliest signal` = min(first_quarter, na.rm = TRUE),
          `Signals detected` = dplyr::n(),
          .groups = "drop"
        ) |>
        dplyr::arrange(`Earliest signal`)

      tags$table(
        class = "table table-sm table-striped",
        tags$thead(tags$tr(lapply(names(rows), tags$th))),
        tags$tbody(
          lapply(seq_len(nrow(rows)), function(i) {
            tags$tr(lapply(as.character(rows[i, ]), tags$td))
          })
        )
      )
    })
  })
}
