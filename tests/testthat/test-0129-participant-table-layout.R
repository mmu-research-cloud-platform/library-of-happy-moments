library(testthat)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)

upload_of <- function(name, path) data.frame(name = name, datapath = path)

test_that("0129 participant_name reads a participant column from a TXT table header", {
  path <- tempfile(fileext = ".txt")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c(
      "Filename\tvideo.mp4",
      "Video Time\tSelection\tParticipant Name\tHappy",
      "00:00:01\tA\tParent\t0.2",
      "00:00:02\tA\tParent\t0.4"
    ),
    path
  )
  expect_identical(participant_name(upload_of("p1.txt", path)), "Parent")
})

test_that("0130 participant_name falls back to filename when TXT table has no value", {
  path <- tempfile(fileext = ".txt")
  on.exit(unlink(path), add = TRUE)
  writeLines(
    c("Video Time\tParticipant Name", "00:00:01\t"),
    path
  )
  expect_identical(participant_name(upload_of("child.txt", path)), "child")
})

test_that("0131 participant_name reads a participant column from an XLSX table", {
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  openxlsx::write.xlsx(
    data.frame(
      `Video Time` = c("00:00:01", "00:00:02"),
      `Participant Name` = c("Child", "Child"),
      Happy = c(0.2, 0.4),
      check.names = FALSE
    ),
    path
  )
  expect_identical(participant_name(upload_of("c.xlsx", path)), "Child")
})

test_that("0132 participant_name reads a metadata row in an XLSX sheet", {
  path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(path), add = TRUE)
  openxlsx::write.xlsx(
    data.frame(
      a = c("Filename", "Participant Name"),
      b = c("video.mp4", "Parent")
    ),
    path,
    colNames = FALSE
  )
  expect_identical(participant_name(upload_of("p.xlsx", path)), "Parent")
})

test_that("0133 clip ordering defaults to rank in the UI", {
  app_path <- testthat::test_path("..", "..")
  app_environment <- new.env(parent = globalenv())
  old_directory <- getwd()
  setwd(app_path)
  on.exit(setwd(old_directory), add = TRUE)
  source("app.R", local = app_environment)
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, '<option value="rank" selected', fixed = TRUE)
})
