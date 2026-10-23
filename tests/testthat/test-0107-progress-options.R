library(testthat)
library(shiny)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)
app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0107 console progress is parsed from latest update", {
  expect_null(clip_export_percent("Preparing data"))
  expect_identical(clip_export_percent("\r |===|  10%\r |====|  75%"), 75L)
  expect_identical(clip_export_percent("\r |====| 100%"), 100L)
  expect_null(clip_export_percent(" |=======| 101%"))
})

test_that("0108 banner and advanced settings reflect simplified controls", {
  html <- htmltools::renderTags(app_environment$ui)$html
  css <- sass::sass(attr(app_environment$ui, "bs_theme"))
  expect_match(
    css,
    "body.bslib-page-sidebar > .navbar.navbar-static-top",
    fixed = TRUE
  )
  expect_match(css, "background: #00afff", fixed = TRUE)
  expect_lt(
    regexpr("Clip export", html, fixed = TRUE)[[1L]],
    regexpr("Synchrony selection", html, fixed = TRUE)[[1L]]
  )
  expect_match(html, 'data-value="Advanced options"', fixed = TRUE)
  expect_match(html, 'class="accordion-button collapsed"', fixed = TRUE)
  expect_false(grepl('id="exclude_emotions"', html, fixed = TRUE))
  expect_false(grepl('id="time_limit_frames"', html, fixed = TRUE))
  expect_false(grepl('id="buffer_units"', html, fixed = TRUE))
  expect_false(grepl('value="frames"', html, fixed = TRUE))
})

test_that("0109 pipeline fixes neutral and seconds, rejecting frames constraint", {
  inputs <- list(
    T_up = 0.2,
    T_down = 0.1,
    delta = 0.1,
    delta_window = 0.2,
    min_dur_sec = 0.1,
    time_limit = 3,
    missing_threshold = 0,
    buffer_before = 5,
    buffer_after = 3,
    consecutive_missing = 150,
    cores = 0,
    n = 10,
    constraint_method = "episode",
    subject_from_filename = TRUE,
    subject_map = NULL,
    verbose = FALSE,
    emotion = "happy",
    optimised_subject = "both",
    only_synchronies = TRUE
  )
  opts <- pipeline_options(inputs)
  expect_identical(opts$exclude_emotions, "neutral")
  expect_identical(opts$buffer_units, "seconds")
  expect_null(opts$time_limit_frames)
  inputs$constraint_method <- "frames"
  expect_error(pipeline_options(inputs), "supported constraint method")
})

test_that("0110 progress UI renders real percentage when available", {
  shiny::testServer(app_environment$server, {
    expect_null(output$processing_progress)
    state$busy <- TRUE
    session$flushReact()
    expect_match(
      output$processing_progress$html,
      "Preparing clips",
      fixed = TRUE
    )
    state$percent <- 75L
    session$flushReact()
    expect_match(
      output$processing_progress$html,
      'aria-valuenow="75"',
      fixed = TRUE
    )
    expect_match(output$processing_progress$html, "75%", fixed = TRUE)
    finish_processing(error = simpleError("Validation failed"))
    session$flushReact()
    expect_match(output$status, "Validation failed")
    expect_false(state$busy)
  })
})

test_that("0111 instructions explain advanced option behavior", {
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, 'data-value="Instructions"', fixed = TRUE)
  expect_true(file.exists(file.path(app_path, "instructions.qmd")))
  expect_match(html, "Advanced options reference", fixed = TRUE)
  expect_match(html, "Entry and exit thresholds", fixed = TRUE)
  expect_match(html, "Delta threshold and delta window", fixed = TRUE)
  expect_match(html, "Missing threshold", fixed = TRUE)
  expect_match(html, "Optimised subject", fixed = TRUE)
  expect_match(html, "FaceReader Converter documentation", fixed = TRUE)
})
