library(testthat)
app_path <- normalizePath(testthat::test_path("..", ".."), winslash = "/")
app_environment <- new.env(parent = globalenv())
withr::with_dir(app_path, source("app.R", local = app_environment))
source(file.path(app_path, "R", "app_helpers.R"), local = TRUE)
source(file.path(app_path, "R", "multi_video.R"), local = TRUE)

multi_video_options <- function() list(
  T_up = 0.2, T_down = 0.1, delta = 0.1, delta_window = 0.2,
  min_dur_sec = 0.1, time_limit = 3, missing_threshold = 0,
  buffer_before = 5, buffer_after = 3, consecutive_missing = 150,
  cores = 1, n = 10, constraint_method = "episode",
  subject_from_filename = TRUE, subject_map = NULL, verbose = FALSE,
  emotion = "happy", optimised_subject = "both", only_synchronies = TRUE
)

multi_video_fixture <- function(root, tools) {
  dir.create(root, recursive = TRUE)
  videos <- file.path(root, c("recording.mp4", "other.mp4", "third.mp4"))
  for (i in seq_along(videos)) {
    run_media_command(tools[["ffmpeg"]], c(
      "-f", "lavfi", "-i", c(
        "color=c=red:s=64x48:r=25:d=2",
        "color=c=blue:s=32x64:r=25:d=2.04",
        "color=c=yellow:s=64x48:r=25:d=2"
      )[[i]],
      if (i != 2L) c("-f", "lavfi", "-i", sprintf("sine=frequency=%d:duration=2", i * 440)),
      "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", shQuote(videos[[i]])
    ), "Could not create synthetic video")
  }
  exports <- file.path(root, c("parent.txt", "child.txt"))
  for (i in seq_along(exports)) writeLines(c(
    "FaceReader video analysis detailed", "Filename\trecording.mp4", "Frame rate\t25",
    "Start time 01/01/2026 12:00:00",
    "Video Time\tParticipant Name\tNeutral\tHappy\tSad\tAngry\tSurprised\tScared\tDisgusted",
    vapply(0:49, function(frame) paste(
      sprintf("00:00:%06.3f", frame / 25), c("Parent (A)", "Child")[[i]], 0,
      if (frame >= 10 && frame < 40) 0.8 else 0, 0, 0, 0, 0, 0, sep = "\t"
    ), character(1))
  ), exports[[i]])
  upload <- function(path) data.frame(name = basename(path), datapath = path)
  list(videos = videos, exports = exports, uploads = lapply(videos, upload), fr = lapply(exports, upload))
}

test_that("duration tolerance handles exact matching and its boundary", {
  expect_equal(validate_video_durations(c(2, 2)), 2)
  expect_equal(validate_video_durations(c(2, 2.04), 40), 2)
  expect_equal(validate_video_durations(c(2, 2.039), 40), 2)
  expect_error(validate_video_durations(c(2, 2.041), 40, c("one.mp4", "two.mp4")), "one.mp4 = 2")
  expect_error(validate_video_durations(c(2, 2.04), 0), "tolerance 0")
  for (value in list(-1, NA_real_, Inf, numeric(), "10")) {
    expect_error(validate_video_durations(c(2, 2), value), "non-negative")
  }
  for (values in list(c(2, NA), c(2, Inf), c(0, 2), numeric())) {
    expect_error(validate_video_durations(values), "readable")
  }
})

test_that("multi-video uploads share two exports and validate the audio source", {
  tools <- app_environment$media_tools
  skip_if(inherits(tools, "error"), "Platform media tools unavailable")
  root <- tempfile("multi-readiness-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- multi_video_fixture(root, tools)
  check <- function(primary = 1L, tolerance = 0, uploads = fixture$uploads) upload_validation(
    uploads, fixture$fr[[1L]], fixture$fr[[2L]], tools[["ffprobe"]], primary, tolerance
  )
  expect_match(conditionMessage(check()$error), "durations differ")
  valid <- check(tolerance = 40)
  expect_null(valid$error)
  expect_length(valid$video_info, 3)
  expect_equal(valid$shared_duration, 2)
  expect_length(valid$warnings, 0)
  expect_length(check(primary = 3L, tolerance = 40)$warnings, 2)
  expect_match(conditionMessage(check(primary = 4L, tolerance = 40)$error), "Audio source")
  expect_match(conditionMessage(check(tolerance = -1)$error), "non-negative")
  staging <- stage_uploads(fixture$uploads, fixture$fr[[1L]], fixture$fr[[2L]], file.path(root, "staged"))
  expect_length(staging, 5)
  expect_identical(basename(staging), c(basename(fixture$videos), basename(fixture$exports)))
  duplicate <- fixture$uploads
  duplicate[[2L]]$name <- "RECORDING.MP4"
  expect_match(conditionMessage(check(tolerance = 40, uploads = duplicate)$error), "distinct")
  expect_error(probe_video(fixture$exports[[1L]], tools[["ffprobe"]]), "cannot be read")
})

test_that("real shared clips and ZIP preserve camera order, shortest time and chosen audio", {
  tools <- app_environment$media_tools
  skip_if(inherits(tools, "error"), "Platform media tools unavailable")
  root <- tempfile("multi-export-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- multi_video_fixture(file.path(root, "inputs"), tools)
  options <- pipeline_options(multi_video_options(), c("Parent (A)", "Child"))
  result <- run_shared_video_pipeline(fixture$videos, fixture$exports, file.path(root, "clips"),
    3L, 40, options, tools)
  manifest <- result$results[[1L]]$clip_manifest
  expect_equal(nrow(manifest), 1)
  expect_equal(manifest$start_seconds, 0)
  expect_equal(manifest$duration_seconds, 2)
  expect_identical(manifest$audio_source, "third.mp4")
  expect_identical(manifest$video_count, 3L)
  expect_equal(manifest$selection_value, 1.6)
  composite <- manifest$clip_path[[1L]]
  info <- probe_video(composite, tools[["ffprobe"]])
  expect_equal(c(info$width, info$height, info$duration), c(128, 96, 2))
  for (camera in 1:3) expect_equal(
    probe_video(file.path(root, "clips", "views", paste0("video_", camera), manifest$clip_filename),
      tools[["ffprobe"]])$duration, 2
  )
  sample <- file.path(root, "sample.rgb")
  run_media_command(tools[["ffmpeg"]], c("-i", shQuote(composite), "-frames:v", "1",
    "-pix_fmt", "rgb24", "-f", "rawvideo", shQuote(sample)), "Could not inspect composite")
  pixels <- readBin(sample, "raw", n = 128 * 96 * 3)
  pixel <- function(x, y) as.integer(pixels[(y * 128 + x) * 3 + 1:3])
  expect_gt(pixel(32, 24)[[1]], 200)
  expect_gt(pixel(96, 24)[[3]], 200)
  expect_lt(max(pixel(66, 24)), 20) # Letterbox beside the portrait camera.
  expect_gt(min(pixel(32, 72)[1:2]), 200)
  expect_lt(max(pixel(96, 72)), 20) # Blank odd cell.
  audio <- file.path(root, "audio.raw")
  run_media_command(tools[["ffmpeg"]], c("-i", shQuote(composite), "-t", "1",
    "-ar", "8000", "-ac", "1", "-f", "s16le", shQuote(audio)), "Could not inspect audio")
  signal <- readBin(audio, "integer", n = 8000, size = 2, signed = TRUE, endian = "little")
  spectrum <- Mod(fft(signal))
  frequency <- (which.max(spectrum[2:4000]) / length(signal)) * 8000
  expect_equal(frequency, 1320, tolerance = 5)
  archive <- file.path(root, "shared_clips.zip")
  create_clips_zip(manifest, dirname(composite), archive)
  expect_setequal(utils::unzip(archive, list = TRUE)$Name, c(manifest$clip_filename, "manifest.csv"))
  extracted <- file.path(root, "unzipped")
  utils::unzip(archive, exdir = extracted)
  expect_identical(utils::read.csv(file.path(extracted, "manifest.csv"))$audio_source, "third.mp4")
  single <- run_shared_video_pipeline(fixture$videos[1], fixture$exports, file.path(root, "single"),
    1L, 0, options, tools)$results[[1L]]$clip_manifest
  expect_equal(probe_video(single$clip_path, tools[["ffprobe"]])$width, 64)
  silent <- run_shared_video_pipeline(fixture$videos, fixture$exports, file.path(root, "silent"),
    2L, 40, options, tools)$results[[1L]]$clip_manifest
  streams <- system2(tools[["ffprobe"]], c("-v", "error", "-select_streams", "a",
    "-show_entries", "stream=codec_type", "-of", "csv=p=0", shQuote(silent$clip_path)), stdout = TRUE)
  expect_length(streams, 0)
  expect_error(run_media_command(tools[["ffmpeg"]], c("-not-a-real-option"), "Export failed"), "Export failed")
})

test_that("server adds and removes videos, keeps defaults, and invalidates results", {
  shiny::testServer(app_environment$server, {
    expect_identical(video_ids(), "video")
    expect_identical(primary_video(), 1L)
    session$setInputs(add_video = 1)
    expect_identical(video_ids(), c("video", "video_2"))
    session$setInputs(add_video = 2)
    expect_identical(video_ids(), c("video", "video_2", "video_3"))
    session$setInputs(audio_source = "video_3")
    expect_identical(primary_video(), 3L)
    directory <- tempfile("stale-clips-")
    dir.create(directory)
    state$results_root <- directory
    state$manifest <- data.frame(clip_filename = "old.mp4")
    state$clip_dir <- directory
    session$setInputs(duration_tolerance = 40)
    expect_null(state$manifest)
    expect_false(dir.exists(directory))
    session$setInputs(remove_video_2 = 1)
    expect_identical(video_ids(), c("video", "video_3"))
    expect_identical(primary_video(), 2L)
    session$setInputs(clear_inputs = 1)
    expect_identical(video_ids(), "video")
    expect_null(state$manifest)
    expect_identical(input$duration_tolerance, 40)
    session$setInputs(add_video = 3, audio_source = "video")
    expect_length(video_ids(), 2)
    session$setInputs(reset_multi_video = 1)
    expect_identical(video_ids(), "video")
  })
  html <- htmltools::renderTags(app_environment$ui)
  for (id in c("add_video", "audio_source", "duration_tolerance", "video_columns")) {
    expect_match(html$html, paste0('id="', id, '"'), fixed = TRUE)
  }
  expect_match(html$head, "multi-video.js", fixed = TRUE)
  multi_panel <- htmltools::tagQuery(app_environment$ui)$find("#audio_source")$closest(".accordion-item")$selectedTags()
  expect_match(as.character(multi_panel[[1L]]), "Multi-video", fixed = TRUE)
})

test_that("FaceReader frame durations use the same tolerance as all videos", {
  expect_equal(facereader_duration(data.frame(video_time = seq(0, 1.96, 0.04)), 25, "export.txt"), 2)
  expect_error(facereader_duration(data.frame(video_time = c(0, NA)), 25, "bad.txt"), "bad.txt")
  expect_error(facereader_duration(data.frame(), 25, "empty.txt"), "Video Time")
  expect_error(facereader_duration(data.frame(video_time = 0), 0, "fps.txt"), "frame rate")
  tools <- app_environment$media_tools
  skip_if(inherits(tools, "error"), "Platform media tools unavailable")
  root <- tempfile("fr-durations-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- multi_video_fixture(root, tools)
  check <- function(tolerance) upload_validation(
    fixture$uploads[c(1, 3)], fixture$fr[[1L]], fixture$fr[[2L]], tools[["ffprobe"]],
    duration_tolerance = tolerance
  )
  expect_null(check(0)$error)
  expect_equal(check(0)$fr_durations, c(2, 2))
  lines <- readLines(fixture$exports[[1L]])
  writeLines(sub("00:00:01.960", "00:00:02.000", lines, fixed = TRUE), fixture$exports[[1L]])
  expect_null(check(40)$error)
  expect_match(conditionMessage(check(39)$error), "Video/FaceReader durations differ")
  expect_match(conditionMessage(check(0)$error), "parent.txt = 2.040000000")
  writeLines(lines[1:30], fixture$exports[[1L]])
  expect_match(conditionMessage(check(40)$error), "parent.txt")
})

test_that("the real multi-video worker completes and upload replacement invalidates it", {
  tools <- app_environment$media_tools
  skip_if(inherits(tools, "error"), "Platform media tools unavailable")
  root <- tempfile("multi-server-")
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  fixture <- multi_video_fixture(root, tools)
  shiny::testServer(app_environment$server, {
    session$setInputs(add_video = 1)
    session$setInputs(add_video = 2)
    do.call(session$setInputs, c(multi_video_options(), list(
      video = fixture$uploads[[1L]], video_2 = fixture$uploads[[2L]], video_3 = fixture$uploads[[3L]],
      first = fixture$fr[[1L]], second = fixture$fr[[2L]],
      audio_source = "video", duration_tolerance = 40
    )))
    expect_true(inputs_ready())
    expect_identical(output$status, "Inputs validated. Ready to process.")
    session$setInputs(process = 1)
    expect_true(state$busy)
    process <- get("worker", envir = environment(poll_worker))
    process$wait(timeout = 30000)
    expect_false(process$is_alive())
    poll_worker(get("run_id", envir = environment(poll_worker)))
    session$flushReact()
    expect_false(state$busy)
    expect_identical(state$video_count, 3L)
    expect_identical(state$primary, 1L)
    player <- output$player$html
    expect_match(player, 'data-duration="2"', fixed = TRUE)
    expect_match(player, "views/video_3", fixed = TRUE)
    expect_true(dir.exists(state$results_root))
    old_directory <- state$results_root
    replacement <- fixture$uploads[[3L]]
    replacement$name <- "replacement.mp4"
    session$setInputs(video_3 = replacement)
    expect_null(state$manifest)
    expect_false(dir.exists(old_directory))
    session$setInputs(process = 2)
    expect_true(state$busy)
    process <- get("worker", envir = environment(poll_worker))
    session$setInputs(duration_tolerance = 0)
    expect_false(state$busy)
    expect_false(process$is_alive())
    expect_null(state$manifest)
  })
})
