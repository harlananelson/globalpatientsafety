# Article index — card grid linking to each article tab.

box::use(
  bslib[card, card_body, card_header, layout_column_wrap],
  shiny[...],
)

box::use(
  app/logic/articles[ARTICLES],
)

.article_card <- function(row, ns) {
  card(
    class = "h-100",
    card_header(
      div(
        class = "d-flex justify-content-between align-items-center gap-2",
        strong(row$title),
        if (row$featured) span(class = "badge bg-primary", "Featured") else NULL
      )
    ),
    card_body(
      p(class = "text-muted small mb-1", row$date),
      p(class = "card-text flex-grow-1", row$subtitle),
      div(
        class = "mt-auto",
        tags$button(
          class = "btn btn-outline-primary btn-sm",
          onclick = sprintf(
            "Shiny.setInputValue('%s', '%s', {priority: 'event'})",
            ns("open_article"), row$id
          ),
          paste0("Read →")
        )
      )
    )
  )
}

#' @export
ui <- function(id) {
  ns <- NS(id)
  # Match menu/featured/server paths: only published articles (drafts have no
  # view modules and would render as dead-click "Read →" buttons).
  shown <- ARTICLES[ARTICLES$status == "published", , drop = FALSE]
  div(
    class = "container-fluid py-4",
    tags$h4("Articles", class = "fw-light mb-4"),
    layout_column_wrap(
      width = "380px",
      gap   = "1.25rem",
      !!!lapply(seq_len(nrow(shown)), function(i) .article_card(shown[i, ], ns))
    )
  )
}

#' @export
server <- function(id, switch_to_article) {
  moduleServer(id, function(input, output, session) {
    shiny::observeEvent(input$open_article, {
      switch_to_article(input$open_article)
    })
  })
}
