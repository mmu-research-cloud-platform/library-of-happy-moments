library(testthat)
library(shiny)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

upload <- function(path, name = basename(path)) {
  data.frame(name = name, datapath = path)
}

fixture <- function(name) {
  file.path(Sys.getenv("TEST_DATA"), "brazil", name)
}

test_that("0115 Process video starts disabled and rejects missing uploads", {
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, 'id="process"', fixed = TRUE)
  expect_match(html, 'disabled id="process"', fixed = TRUE)
  expect_match(
    htmltools::renderTags(app_environment$ui)$head,
    "Shiny.addCustomMessageHandler('process-readiness'",
    fixed = TRUE
  )
  shiny::testServer(app_environment$server, {
    expect_identical(ready(), FALSE)
    session$setInputs(process = 1)
    expect_identical(state$busy, FALSE)
    expect_identical(
      output$status,
      "Upload a video and two detailed FaceReader files."
    )
  })
})

test_that("0116 Process video requires two matching detailed exports", {
  skip_if(!nzchar(Sys.getenv("TEST_DATA")))
  first <- fixture(
    "100024_child_Analysis 1_video_20260907_195450_detailed.xlsx"
  )
  second <- fixture("100024_mum_Analysis 1_video_20260907_195448_detailed.xlsx")
  state_export <- fixture(
    "Participant 10_Participant 10_Analysis 1_video_20260918_143140_state.xlsx"
  )
  video_path <- fixture("ID100024_side_by_side.mp4")
  skip_if(!all(file.exists(c(first, second, state_export, video_path))))
  video <- upload(video_path)
  ffprobe <- locate_media_tools(app_path)[["ffprobe"]]
  expect_identical(
    uploads_ready(video, upload(first), upload(second), ffprobe),
    TRUE
  )
  expect_identical(
    uploads_ready(video, upload(first), upload(state_export), ffprobe),
    FALSE
  )
  expect_identical(
    uploads_ready(video, upload(first), upload(first), ffprobe),
    FALSE
  )
  expect_identical(
    uploads_ready(
      upload(video_path, "wrong.mp4"),
      upload(first),
      upload(second),
      ffprobe
    ),
    TRUE
  )
  expect_gt(
    length(
      upload_validation(
        upload(video_path, "wrong.mp4"),
        upload(first),
        upload(second),
        ffprobe
      )$warnings
    ),
    0L
  )
  expect_identical(
    uploads_ready(video, upload(first), upload(second, "bad.csv"), ffprobe),
    FALSE
  )
  expect_identical(
    uploads_ready(
      upload(first, "ID100024_side_by_side.mp4"),
      upload(first),
      upload(second),
      ffprobe
    ),
    FALSE
  )
  shiny::testServer(app_environment$server, {
    session$setInputs(video = video, first = upload(first))
    expect_identical(ready(), FALSE)
    session$setInputs(second = upload(state_export))
    expect_identical(ready(), FALSE)
    session$setInputs(second = upload(second))
    expect_identical(ready(), TRUE)
    state$busy <- TRUE
    session$flushReact()
    expect_identical(ready(), TRUE)
  })
})

test_that("0117 TXT detailed exports pass and state exports fail silently", {
  skip_if(!nzchar(Sys.getenv("TEST_DATA")))
  folder <- file.path(Sys.getenv("TEST_DATA"), "c2e-directory", "mum", "8892")
  detailed <- file.path(
    folder,
    "Participant 10_8892_Analysis 1_video_20260721_125850_detailed.txt"
  )
  state_export <- file.path(
    folder,
    "Participant 10_8892_Analysis 1_video_20260721_125850_state.txt"
  )
  skip_if(!all(file.exists(c(detailed, state_export))))
  video <- upload(
    detailed,
    "#8892 Sussed card game teen view point synced 10 minutes_1.mp4"
  )
  expect_identical(
    validate_detailed_export(upload(detailed), video)$type,
    "detailed"
  )
  expect_identical(
    uploads_ready(
      video,
      upload(detailed),
      upload(state_export),
      locate_media_tools(app_path)[["ffprobe"]]
    ),
    FALSE
  )
})

test_that("0118 video filename mismatches are confirmable warnings", {
  skip_if(!nzchar(Sys.getenv("TEST_DATA")))
  first <- fixture(
    "100024_child_Analysis 1_video_20260907_195450_detailed.xlsx"
  )
  second <- fixture("100024_mum_Analysis 1_video_20260907_195448_detailed.xlsx")
  video_path <- fixture("ID100024_side_by_side.mp4")
  skip_if(!all(file.exists(c(first, second, video_path))))
  validation <- upload_validation(
    upload(video_path, "other-video.mp4"),
    upload(first),
    upload(second),
    locate_media_tools(app_path)[["ffprobe"]]
  )
  expect_null(validation$error)
  expect_gt(length(validation$warnings), 0L)
  expect_match(
    paste(validation$warnings, collapse = " "),
    "metadata",
    ignore.case = TRUE
  )
})
