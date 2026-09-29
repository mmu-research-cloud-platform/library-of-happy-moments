library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0111 cancel control appears only while processing", {
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, 'id="cancel_control"', fixed = TRUE)
  shiny::testServer(app_environment$server, {
    expect_null(output$cancel_control)
    state$busy <- TRUE
    session$flushReact()
    expect_match(
      output$cancel_control$html,
      'id="cancel_processing"',
      fixed = TRUE
    )
    state$busy <- FALSE
    session$flushReact()
    expect_null(output$cancel_control)
  })
})

test_that("0112 confirmation is required before stopping the run", {
  shiny::testServer(app_environment$server, {
    state$busy <- TRUE
    state$percent <- 40L
    session$setInputs(confirm_cancel = 1)
    expect_true(state$busy)
    session$setInputs(cancel_processing = 1)
    expect_true(state$busy)
    expect_identical(state$percent, 40L)
    session$setInputs(keep_processing = 1)
    expect_true(state$busy)
    expect_identical(state$percent, 40L)
    session$setInputs(confirm_cancel = 2)
    expect_true(state$busy)
    session$setInputs(cancel_processing = 2)
    session$setInputs(confirm_cancel = 3)
    expect_false(state$busy)
    expect_null(state$percent)
    expect_identical(state$status, "Processing cancelled.")
    expect_null(output$processing_progress)
  })
})

test_that("0113 completion while confirmation is open cannot cancel results", {
  shiny::testServer(app_environment$server, {
    state$busy <- TRUE
    session$setInputs(cancel_processing = 1)
    finish_processing(error = simpleError("Run finished"))
    session$setInputs(confirm_cancel = 1)
    expect_false(state$busy)
    expect_identical(state$status, "Run finished")
  })
})

test_that("0114 confirmed cancellation kills worker and discards partial files", {
  shiny::testServer(app_environment$server, {
    directory <- tempfile("cancel-run-")
    dir.create(directory)
    writeLines("partial", file.path(directory, "partial.mp4"))
    assign("run_root", directory, envir = environment(poll_worker))
    process <- callr::r_bg(function() Sys.sleep(30), supervise = TRUE)
    assign("worker", process, envir = environment(poll_worker))
    state$busy <- TRUE
    session$setInputs(cancel_processing = 1)
    session$setInputs(confirm_cancel = 1)
    expect_false(process$is_alive())
    expect_false(dir.exists(directory))
    expect_false(state$busy)
    expect_silent(poll_worker(run_id - 1L))
    expect_identical(state$status, "Processing cancelled.")
  })
})
