box::use(
  shiny[testServer],
  testthat[expect_true, test_that],
)
box::use(
  app / main[server],
)

test_that("main server initializes without error", {
  # The main module wires up navigation and sub-module servers (portal,
  # articles, per-article) and exposes no top-level outputs to assert on, so
  # this is a smoke test: testServer errors if the module fails to start.
  testServer(server, {
    expect_true(is.function(session$ns))
  })
})
