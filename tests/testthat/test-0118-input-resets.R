library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0118 instructions and scoped reset controls appear", {
  tags <- htmltools::renderTags(app_environment$ui)
  html <- tags$html
  for (id in c(
    "clear_inputs",
    "reset_advanced",
    "reset_clip_export",
    "reset_synchrony",
    "reset_episode"
  )) {
    expect_match(html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_match(html, "How to create clips", fixed = TRUE)
  expect_match(html, 'data-value="Instructions"', fixed = TRUE)
  expect_match(tags$head, "clear-upload-inputs", fixed = TRUE)
  expect_match(tags$head, "status.ready", fixed = TRUE)
})

test_that("0119 processing requires validated uploads and advanced settings", {
  shiny::testServer(app_environment$server, {
    expect_false(inputs_ready())
    session$setInputs(process = 1)
    expect_false(state$busy)
    session$setInputs(T_down = 1, T_up = 0.2)
    expect_false(inputs_ready())
    session$setInputs(process = 2)
    expect_false(state$busy)
  })
})

test_that("0120 clearing inputs discards previous clips but not settings", {
  shiny::testServer(app_environment$server, {
    directory <- tempfile("old-clips-")
    dir.create(directory)
    assign("run_root", directory, envir = environment(finish_processing))
    state$manifest <- data.frame(clip_filename = "old.mp4")
    state$clip_dir <- directory
    state$index <- 3L
    session$setInputs(n = 7, clear_inputs = 1)
    expect_null(state$manifest)
    expect_null(state$clip_dir)
    expect_identical(state$index, 1L)
    expect_false(dir.exists(directory))
    expect_identical(input$n, 7)
    expect_match(output$status, "Upload a video")
    state$busy <- TRUE
    session$setInputs(clear_inputs = 2)
    expect_true(state$busy)
  })
})

test_that("0121 panel and overall reset handlers accept changed controls", {
  shiny::testServer(app_environment$server, {
    session$setInputs(
      n = 7,
      emotion = "sad",
      optimised_subject = "first",
      only_synchronies = FALSE,
      buffer_before = 9,
      buffer_after = 8,
      time_limit = 6,
      constraint_method = "strict",
      missing_threshold = 0.5,
      T_up = 0.4,
      T_down = 0.3,
      delta = 0.2,
      delta_window = 1,
      min_dur_sec = 2,
      consecutive_missing = 20,
      cores = 2
    )
    expect_silent(session$setInputs(reset_clip_export = 1))
    expect_silent(session$setInputs(reset_synchrony = 1))
    expect_silent(session$setInputs(reset_episode = 1))
    state$manifest <- data.frame(clip_filename = "old.mp4")
    session$setInputs(reset_advanced = 1)
    expect_null(state$manifest)
    expect_match(output$status, "Upload a video")
    state$busy <- TRUE
    session$setInputs(reset_advanced = 2)
    expect_true(state$busy)
  })
})
