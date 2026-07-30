# Christine Cotton VAERS reanalysis — article view module.
#
# Renders the pre-built static HTML in an iframe with a share bar.
# Source QMD: articles/christine-cotton-vaers.qmd
# Built HTML: app/static/christine_cotton.html

box::use(
  shiny[...],
)

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
      src    = "static/christine_cotton.html",
      style  = "width:100%; height:calc(100vh - 50px); border:none;",
      title  = "Tested Against VAERS: Christine Cotton's Safety Claims and the Post-Market Record"
    )
  )
}

#' @export
server <- function(id) {
  moduleServer(id, function(input, output, session) {
    # Static content only — no server-side reactivity needed.
  })
}
