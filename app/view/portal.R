# Portal card grid.
# Reads TOOLS from app/logic/tools.R and renders one card per row.

box::use(
  bslib[card, card_body, card_header, layout_column_wrap],
  shiny[...],
)

box::use(
  app/logic/tools[TOOLS],
)

.status_badge <- function(status) {
  cls <- switch(status,
    live = "badge bg-success",
    beta = "badge bg-warning text-dark",
    coming_soon = "badge bg-secondary",
    "badge bg-secondary"
  )
  label <- switch(status,
    live = "Live",
    beta = "Beta",
    coming_soon = "Coming soon",
    status
  )
  span(class = cls, label)
}

.tool_card <- function(row) {
  disabled <- row$status == "coming_soon" || is.na(row$url)
  link <- if (disabled) {
    span(class = "btn btn-outline-secondary disabled", "Coming soon")
  } else {
    a(
      paste0("Open ", row$name, " \u2192"),
      href = row$url,
      target = "_blank",
      class = "btn btn-primary"
    )
  }
  card(
    class = "h-100",
    card_header(
      div(
        class = "d-flex justify-content-between align-items-center",
        strong(row$name),
        .status_badge(row$status)
      )
    ),
    card_body(
      p(class = "card-text flex-grow-1", row$tagline),
      div(class = "mt-auto", link)
    )
  )
}

#' @export
ui <- function(id) {
  layout_column_wrap(
    width = "320px",
    gap = "1rem",
    !!!lapply(seq_len(nrow(TOOLS)), function(i) .tool_card(TOOLS[i, ]))
  )
}

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Static content; no reactive state needed
  })
}
