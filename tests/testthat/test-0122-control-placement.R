library(testthat)
library(shiny)

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

test_that("0122 processing controls live in sidebar and download follows player", {
  html <- htmltools::renderTags(app_environment$ui)$html
  sidebar_start <- regexpr('class="sidebar', html, fixed = TRUE)[[1L]]
  main_start <- regexpr('class="main ', html, fixed = TRUE)[[1L]]
  expect_gt(sidebar_start, 0L)
  expect_gt(sidebar_start, main_start)
  for (id in c("process", "clear_inputs", "cancel_control")) {
    position <- regexpr(paste0('id="', id, '"'), html, fixed = TRUE)[[1L]]
    expect_gt(position, sidebar_start)
  }
  player_position <- regexpr('id="player"', html, fixed = TRUE)[[1L]]
  download_position <- regexpr('id="download_control"', html, fixed = TRUE)[[
    1L
  ]]
  expect_gt(player_position, main_start)
  expect_lt(player_position, sidebar_start)
  expect_gt(download_position, player_position)
  expect_lt(download_position, sidebar_start)
})

test_that("0123 download remains disabled until clips are generated", {
  shiny::testServer(app_environment$server, {
    expect_match(output$download_control$html, "disabled", fixed = TRUE)
    state$manifest <- data.frame(clip_filename = "sample.mp4")
    session$flushReact()
    expect_match(output$download_control$html, 'id="download"', fixed = TRUE)
  })
})
