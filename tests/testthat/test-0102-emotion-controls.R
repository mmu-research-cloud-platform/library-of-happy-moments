library(testthat)
library(shiny)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)
app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0102 emotion selections are validated and passed as vectors", {
  expect_identical(parse_emotions(c("happy", "sad")), c("happy", "sad"))
  expect_null(parse_emotions(NULL))
  expect_identical(parse_emotions("neutral", allow_neutral = TRUE), "neutral")
  expect_error(parse_emotions("neutral"), "FaceReader dropdown")
  expect_error(parse_emotions("unknown"), "FaceReader dropdown")
  expect_setequal(
    face_reader_emotions,
    c(
      "happy",
      "sad",
      "angry",
      "surprised",
      "scared",
      "disgusted"
    )
  )
})

test_that("0103 header and emotion controls render in the requested order", {
  rendered <- htmltools::renderTags(app_environment$ui)
  html <- rendered$html
  expect_lt(
    regexpr("Synchrony selection", html, fixed = TRUE)[[1L]],
    regexpr("Episode detection", html, fixed = TRUE)[[1L]]
  )
  expect_match(html, 'id="emotion"', fixed = TRUE)
  expect_false(grepl('id="exclude_emotions"', html, fixed = TRUE))
  expect_match(html, 'multiple="multiple"')
  css <- sass::sass(attr(app_environment$ui, "bs_theme"))
  expect_match(
    css,
    "body.bslib-page-sidebar > .navbar.navbar-static-top",
    fixed = TRUE
  )
  expect_match(css, "background: #00afff", fixed = TRUE)
})
