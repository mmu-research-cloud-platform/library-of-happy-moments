library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0104 upload cards appear inside the sidebar", {
  html <- htmltools::renderTags(app_environment$ui)$html
  sidebar_start <- regexpr('class="sidebar', html, fixed = TRUE)[[1L]]
  main_start <- regexpr('class="main ', html, fixed = TRUE)[[1L]]
  expect_gt(sidebar_start, 0L)
  expect_lt(main_start, sidebar_start)
  sidebar_html <- substr(html, sidebar_start, nchar(html))
  for (id in c("video", "first", "second")) {
    expect_match(sidebar_html, paste0('id="', id, '"'), fixed = TRUE)
    expect_length(
      gregexpr(paste0('id="', id, '"'), html, fixed = TRUE)[[1L]],
      1L
    )
  }
})

test_that("0105 processing indicator renders while busy", {
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, 'id="processing_progress"', fixed = TRUE)
  shiny::testServer(app_environment$server, {
    expect_null(output$processing_progress)
    state$busy <- TRUE
    session$flushReact()
    expect_match(
      output$processing_progress$html,
      'progress-bar-striped progress-bar-animated',
      fixed = TRUE
    )
    expect_match(
      output$processing_progress$html,
      'aria-valuetext="Preparing clips"',
      fixed = TRUE
    )
  })
})

test_that("0106 processing is blocked when uploads are missing", {
  shiny::testServer(app_environment$server, {
    session$setInputs(process = 1)
    expect_identical(
      output$status,
      "Upload a video and two detailed FaceReader files."
    )
    expect_false(state$busy)
  })
})
