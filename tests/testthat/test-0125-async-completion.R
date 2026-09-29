library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0125 successful worker completion is safe outside a reactive consumer", {
  shiny::testServer(app_environment$server, {
    clip_dir <- tempfile("completed-clips-")
    dir.create(clip_dir)
    on.exit(unlink(clip_dir, recursive = TRUE), add = TRUE)
    manifest <- data.frame(clip_filename = "clip.mp4")
    state$busy <- TRUE
    finish_processing(result = list(results = list(list(
      clip_manifest = manifest,
      clip_output = clip_dir
    ))))
    expect_false(state$busy)
    expect_identical(state$manifest, manifest)
    expect_identical(state$clip_dir, clip_dir)
    expect_match(output$status, "Generated 1 clips", fixed = TRUE)
    expect_match(output$download_control$html, 'id="download"', fixed = TRUE)
  })
})
