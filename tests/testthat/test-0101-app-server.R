library(testthat)
library(shiny)
app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
source("app.R", local = TRUE)
setwd(old_directory)

test_that("server prevents processing without uploads", {
  expect_error(
    locate_media_tools(tempfile("missing-media-tools-")),
    "Bundled FFmpeg and FFprobe"
  )
  shiny::testServer(server, {
    expect_false(ready())
    session$setInputs(process = 1)
    expect_false(state$busy)
    expect_identical(
      output$status,
      "Upload a video and two detailed FaceReader files."
    )
  })
})

test_that("the page contains the requested upload and navigation controls", {
  html <- htmltools::renderTags(ui)$html
  for (id in c(
    "video",
    "first",
    "second",
    "process",
    "previous",
    "next_clip",
    "clip_order"
  )) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_identical(
    bslib::bs_get_variables(
      bslib::bs_theme(version = 5, primary = "#00afff"),
      "primary"
    )[[1L]] |>
      tolower(),
    "#00afff"
  )
})
