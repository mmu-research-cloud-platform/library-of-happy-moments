library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0124 process controls precede advanced options in the sidebar", {
  html <- htmltools::renderTags(app_environment$ui)$html
  sidebar_start <- regexpr('class="sidebar', html, fixed = TRUE)[[1L]]
  process_position <- regexpr('id="process"', html, fixed = TRUE)[[1L]]
  clear_position <- regexpr('id="clear_inputs"', html, fixed = TRUE)[[1L]]
  advanced_position <- regexpr('data-value="Advanced options"', html, fixed = TRUE)[[1L]]
  expect_gt(process_position, sidebar_start)
  expect_gt(clear_position, process_position)
  expect_gt(advanced_position, clear_position)
  expect_length(gregexpr('id="process"', html, fixed = TRUE)[[1L]], 1L)
})
