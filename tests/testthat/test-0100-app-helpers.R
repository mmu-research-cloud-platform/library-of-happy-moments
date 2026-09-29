library(testthat)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)

test_that("uploads are validated and staged with safe unique names", {
  root <- tempfile("uploads-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  file <- tempfile(fileext = ".mp4")
  writeBin(as.raw(1:5), file)
  fr1 <- tempfile(fileext = ".txt")
  fr2 <- tempfile(fileext = ".xlsx")
  writeLines("export", fr1)
  writeLines("export", fr2)
  upload <- function(name, path) data.frame(name = name, datapath = path)
  paths <- stage_uploads(
    upload("folder/recording.mp4", file),
    upload("one.txt", fr1),
    upload("two.xlsx", fr2),
    root
  )
  expect_length(paths, 3L)
  expect_true(all(file.exists(paths)))
  expect_identical(basename(paths[[1L]]), "recording.mp4")
  expect_error(
    stage_uploads(
      upload("video.mp4", file),
      upload("one.txt", fr1),
      upload("ONE.TXT", fr1),
      tempfile("uploads-")
    ),
    "distinct"
  )
})

test_that("subject map keys follow staged upload filenames", {
  csv <- tempfile(fileext = ".csv")
  on.exit(unlink(csv), add = TRUE)
  utils::write.csv(
    data.frame(export_filename = "participant one.txt", subject = "Parent"),
    csv,
    row.names = FALSE
  )
  upload <- data.frame(name = "subjects.csv", datapath = csv)
  expect_identical(parse_subject_map(upload), c(participant_one.txt = "Parent"))
})

test_that("sorting uses numeric manifest order, not lexical filenames", {
  manifest <- data.frame(
    clip_filename = c("10.mp4", "2.mp4", "1.mp4"),
    selection_rank = c(10L, 2L, 1L),
    clip_order = c(1L, 3L, 2L)
  )
  expect_identical(ordered_clips(manifest, "time")$clip_order, 1:3)
  expect_identical(
    ordered_clips(manifest, "rank")$selection_rank,
    c(1L, 2L, 10L)
  )
})

test_that("ZIP contains clips and manifest", {
  root <- tempfile("clips-")
  dir.create(root)
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  writeBin(as.raw(1:5), file.path(root, "clip.mp4"))
  manifest <- data.frame(clip_filename = "clip.mp4", selection_rank = 1L)
  archive <- tempfile(fileext = ".zip")
  on.exit(unlink(archive), add = TRUE)
  create_clips_zip(manifest, root, archive)
  expect_setequal(
    utils::unzip(archive, list = TRUE)$Name,
    c("clip.mp4", "manifest.csv")
  )
  expect_error(
    create_clips_zip(data.frame(clip_filename = "../bad.mp4"), root, archive),
    "Invalid clip manifest"
  )
})

test_that("integer settings reject values beyond R integer limits", {
  expect_error(
    parse_optional_number(as.character(.Machine$integer.max + 1), "Frames"),
    "non-negative whole"
  )
  defaults <- list(
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
    time_limit_frames = "",
    subject_from_filename = TRUE,
    subject_map = NULL,
    verbose = FALSE,
    exclude_emotions = "neutral",
    emotion = "happy",
    optimised_subject = "both",
    only_synchronies = TRUE,
    buffer_units = "seconds"
  )
  for (key in c("consecutive_missing", "cores", "n")) {
    invalid <- defaults
    invalid[[key]] <- .Machine$integer.max + 1
    expect_error(pipeline_options(invalid), "non-negative whole")
  }
})

test_that("binary paths are platform-specific and both tools are required", {
  expect_identical(
    binary_directory("root", "Darwin", "arm64"),
    file.path("root", "bin", "macos-arm64")
  )
  expect_identical(
    binary_directory("root", "Windows", "AMD64"),
    file.path("root", "bin", "windows-x64")
  )
  expect_error(binary_directory("root", "Linux", "arm64"), "Unsupported CPU")
  expect_error(locate_media_tools(tempdir(), "Windows", "AMD64"), "required")
})
