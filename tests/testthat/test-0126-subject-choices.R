library(testthat)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)

test_that("0126 subject_choices lists participants first and both last", {
  choices <- subject_choices("Parent", "Child")
  expect_identical(
    names(choices),
    c("Participant 1: Parent", "Participant 2: Child", "both")
  )
  expect_identical(unname(choices), c("^Parent$", "^Child$", "both"))
})

test_that("0127 subject_choices defaults to both and escapes regex characters", {
  expect_identical(subject_choices(), c(both = "both"))
  choices <- subject_choices("A.B (1)", "C+D")
  expect_identical(unname(choices)[1:2], c("^A\\.B \\(1\\)$", "^C\\+D$"))
  expect_true(grepl(choices[[1L]], "A.B (1)"))
  expect_false(grepl(choices[[1L]], "AxB (1)"))
})

test_that("0128 participant_name reads metadata and falls back to filename", {
  with_name <- tempfile(fileext = ".txt")
  without_name <- tempfile(fileext = ".txt")
  on.exit(unlink(c(with_name, without_name)), add = TRUE)
  writeLines(c("Filename\tvideo.mp4", "Participant Name\tParent"), with_name)
  writeLines(c("Filename\tvideo.mp4", "Participant Name\t"), without_name)
  upload <- function(name, path) data.frame(name = name, datapath = path)
  expect_identical(participant_name(upload("p1.txt", with_name)), "Parent")
  expect_identical(participant_name(upload("child.txt", without_name)), "child")
  expect_identical(
    participant_name(upload("missing.txt", tempfile(fileext = ".txt"))),
    "missing"
  )
})
