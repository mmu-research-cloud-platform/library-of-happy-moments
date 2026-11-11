library(testthat)
source(testthat::test_path("..", "..", "R", "app_helpers.R"), local = TRUE)

synthetic_exports <- function(root, subjects = c("Parent (A)", "Child")) {
  dir.create(root, recursive = TRUE)
  paths <- file.path(root, c("parent_export.txt", "child_export.txt"))
  for (i in seq_along(paths)) {
    writeLines(c(
      "FaceReader video analysis detailed",
      "Filename\trecording.mp4",
      "Frame rate\t25",
      "Participant Name\tHeader label is not the pipeline subject",
      "Start time 01/01/2026 12:00:00",
      "Video Time\tParticipant Name\tNeutral\tHappy\tSad\tAngry\tSurprised\tScared\tDisgusted",
      vapply(0:49, function(frame) {
        paste(
          sprintf("00:00:%06.3f", frame / 25), subjects[[i]], 0,
          if (frame < 10 || frame >= 40) 0 else 0.8,
          0, 0, 0, 0, 0, sep = "\t"
        )
      }, character(1))
    ), paths[[i]])
  }
  lapply(paths, function(path) data.frame(name = basename(path), datapath = path))
}

test_that("uploaded subjects use the real parser and select literal pipeline names", {
  root <- tempfile("subject-selection-", tmpdir = getwd())
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  uploads <- synthetic_exports(root)
  subjects <- uploaded_subjects(uploads[[1L]], uploads[[2L]], TRUE, NULL)
  expect_identical(subjects, c("Parent (A)", "Child"))
  pattern <- resolve_optimised_subject("^Parent \\(A\\)$", subjects)
  expect_identical(pattern, "^Parent \\(A\\)$")

  inputs <- lapply(uploads, function(upload) {
    data <- facereaderconverter::loadFRfile(upload$datapath)
    data$id <- "video_001"
    data$subject <- trimws(data$participant_name)
    data[, c("id", "subject", "video_time", "happy")]
  })
  coded <- facereaderconverter::convert_to_episodes(
    dplyr::bind_rows(inputs), fps = 25, cores = 1L
  )
  shared <- facereaderconverter::shared_synchronous_episodes(coded)
  video <- file.path(root, "recording.mp4")
  writeBin(as.raw(1:5), video)
  prepare <- getFromNamespace("prepare_shared_synchrony_clips", "facereaderconverter")
  arguments <- list(
    coded_data = coded, shared_synchrony = shared,
    video_paths = c(video_001 = video), n = 1L, emotion = "happy"
  )
  expect_error(
    do.call(prepare, c(arguments, list(optimised_subject = "Parent (A)"))),
    "`optimised_subject` must match exactly one subject name.", fixed = TRUE
  )
  for (only in c(TRUE, FALSE)) {
    manifest <- do.call(prepare, c(arguments, list(
      optimised_subject = pattern, only_synchronies = only
    )))
    expect_equal(nrow(manifest), 1L)
    expect_equal(manifest$selection_value, 0.8)
  }
  for (only in c(TRUE, FALSE)) {
    manifest <- do.call(prepare, c(arguments, list(
      optimised_subject = "both", only_synchronies = only
    )))
    expect_equal(nrow(manifest), 1L)
    expect_equal(manifest$selection_value, 1.6)
  }
})

test_that("subject resolution follows maps, filename fallback and staging", {
  root <- tempfile("subject-mapping-", tmpdir = getwd())
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  uploads <- synthetic_exports(root, c("", "Child"))
  uploads[[1L]]$name <- "parent export.txt"
  expect_identical(
    uploaded_subjects(uploads[[1L]], uploads[[2L]], TRUE, NULL),
    c("parent_export", "Child")
  )
  expect_error(
    uploaded_subjects(uploads[[1L]], uploads[[2L]], FALSE, NULL),
    "Subject mapping CSV"
  )
  expect_identical(
    uploaded_subjects(
      uploads[[1L]], uploads[[2L]], FALSE, c(PARENT_EXPORT.TXT = "Mapped [A]")
    ),
    c("Mapped [A]", "Child")
  )
  expect_error(
    uploaded_subjects(
      uploads[[1L]], uploads[[2L]], TRUE, c(parent_export.txt = "Child")
    ),
    "distinct"
  )
  uploads <- synthetic_exports(file.path(root, "ambiguous"))
  lines <- readLines(uploads[[1L]]$datapath)
  lines[[8L]] <- sub("Parent (A)", "Other", lines[[8L]], fixed = TRUE)
  writeLines(lines, uploads[[1L]]$datapath)
  expect_error(
    uploaded_subjects(uploads[[1L]], uploads[[2L]], TRUE, NULL),
    "Subject mapping CSV"
  )
})

test_that("ambiguous, stale and unresolved selections never fall back to both", {
  subjects <- c("Parent", "Parent 2")
  expect_identical(resolve_optimised_subject("both", subjects), "both")
  expect_error(resolve_optimised_subject("Parent", subjects), "Select.*dropdown")
  expect_error(resolve_optimised_subject("^Missing$", subjects), "Select.*dropdown")
  expect_error(resolve_optimised_subject(NULL, subjects), "Select.*dropdown")
  expect_error(resolve_optimised_subject("", subjects), "Select.*dropdown")
  expect_error(resolve_optimised_subject("^Parent$", c("Parent", "Parent")), "distinct")
  for (name in c("A.B", "A+B", "A[B]", "A\\B", "A^B$", "both")) {
    choices <- subject_choices(c(name, paste0(name, " extra")))
    pattern <- unname(choices[[name]])
    expect_identical(grepl(pattern, c(name, paste0(name, " extra"))), c(TRUE, FALSE))
    expect_false(identical(pattern, "both"))
  }
})

test_that("displayed errors strip ANSI while the original condition stays intact", {
  message <- "\033[1m! in callr subprocess.\033[22m\nCaused by error:\n\033[31m! `optimised_subject` must match exactly one subject name.\033[39m"
  error <- simpleError(message)
  expect_identical(
    display_error(error),
    paste(
      "! in callr subprocess.\nCaused by error:\n! `optimised_subject` must match exactly one subject name.",
      "Re-select an uploaded subject from the Optimised subject dropdown and check the Subject mapping CSV. If the name is correct, the subject may have no detected intervals; check the episode settings and selected emotions.",
      sep = "\n"
    )
  )
  expect_identical(conditionMessage(error), message)
  expect_identical(
    display_error(simpleError("\033]8;;https://example.test\033\\Help\033]8;;\033\\")),
    "Help"
  )
})

app_path <- testthat::test_path("..", "..")
old_directory <- getwd()
setwd(app_path)
app_environment <- new.env(parent = globalenv())
source("app.R", local = app_environment)
setwd(old_directory)

default_options <- list(
  T_up = 0.2, T_down = 0.1, delta = 0.1, delta_window = 0.2,
  min_dur_sec = 0.1, time_limit = 3, missing_threshold = 0,
  buffer_before = 0, buffer_after = 0, consecutive_missing = 150,
  cores = 1, n = 1, constraint_method = "episode",
  subject_from_filename = TRUE, subject_map = NULL, verbose = FALSE,
  emotion = "happy", optimised_subject = "both", only_synchronies = TRUE
)

test_that("dropdown, pipeline options and error display reject stale selections", {
  html <- htmltools::renderTags(app_environment$ui)$html
  expect_match(html, '<select id="optimised_subject"', fixed = TRUE)
  expect_false(grepl("both or regex", html, fixed = TRUE))
  root <- tempfile("subject-server-", tmpdir = getwd())
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  uploads <- synthetic_exports(root)
  shiny::testServer(app_environment$server, {
    messages <- list()
    session$sendInputMessage <- function(inputId, message) {
      messages[[inputId]] <<- message
    }
    do.call(session$setInputs, c(default_options, list(
      first = uploads[[1L]], second = uploads[[2L]]
    )))
    expect_identical(subjects(), c("Parent (A)", "Child"))
    expect_match(messages$optimised_subject$options, "Parent (A)", fixed = TRUE)
    expect_identical(messages$optimised_subject$value, "both")
    session$setInputs(optimised_subject = "^Parent \\(A\\)$")
    expect_identical(
      pipeline_options(input, subjects())$optimised_subject, "^Parent \\(A\\)$"
    )
    expect_identical(pipeline_options(input, subjects())$only_synchronies, TRUE)
    session$setInputs(only_synchronies = FALSE)
    expect_identical(pipeline_options(input, subjects())$only_synchronies, FALSE)
    lines <- readLines(uploads[[1L]]$datapath)
    writeLines(gsub("Parent (A)", "New parent", lines, fixed = TRUE), uploads[[1L]]$datapath)
    replacement <- uploads[[1L]]
    replacement$name <- "replacement.txt"
    session$setInputs(first = replacement)
    expect_identical(messages$optimised_subject$value, "")
    expect_error(pipeline_options(input, subjects()), "select again")
    session$setInputs(optimised_subject = "")
    expect_error(pipeline_options(input, subjects()), "dropdown")
    session$setInputs(optimised_subject = "^New parent$")
    expect_identical(pipeline_options(input, subjects())$optimised_subject, "^New parent$")
    session$setInputs(reset_clip_export = 1)
    expect_identical(messages$optimised_subject$value, "both")
    error <- simpleError("\033[31mSubprocess failed\033[39m")
    state$busy <- TRUE
    finish_processing(error = error)
    session$flushReact()
    expect_identical(output$status, "Subprocess failed")
    expect_identical(conditionMessage(error), "\033[31mSubprocess failed\033[39m")
  })
})

test_that("XLSX subjects also come from loaded participant columns", {
  skip_if_not_installed("openxlsx")
  root <- tempfile("subject-xlsx-", tmpdir = getwd())
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  uploads <- synthetic_exports(root)
  for (i in seq_along(uploads)) {
    rows <- strsplit(readLines(uploads[[i]]$datapath), "\t", fixed = TRUE)
    cells <- matrix(NA_character_, nrow = length(rows), ncol = 9L)
    for (row in seq_along(rows)) cells[row, seq_along(rows[[row]])] <- rows[[row]]
    path <- sub("\\.txt$", ".xlsx", uploads[[i]]$datapath)
    openxlsx::write.xlsx(as.data.frame(cells), path, colNames = FALSE)
    uploads[[i]] <- data.frame(name = basename(path), datapath = path)
  }
  expect_identical(
    uploaded_subjects(uploads[[1L]], uploads[[2L]], TRUE, NULL),
    c("Parent (A)", "Child")
  )
})

test_that("Process video exports clips through the real callr pipeline", {
  tools <- app_environment$media_tools
  skip_if(inherits(tools, "error"), "Bundled FFmpeg/FFprobe are unavailable")
  root <- tempfile("subject-pipeline-", tmpdir = getwd())
  on.exit(unlink(root, recursive = TRUE), add = TRUE)
  uploads <- synthetic_exports(file.path(root, "inputs"))
  video <- file.path(root, "inputs", "recording.mp4")
  status <- system2(
    tools[["ffmpeg"]],
    c("-v", "error", "-f", "lavfi", "-i", "color=c=black:s=32x32:r=25:d=2",
      "-c:v", "libx264", "-pix_fmt", "yuv420p", shQuote(video)),
    stdout = TRUE, stderr = TRUE
  )
  expect_null(attr(status, "status"))
  settings <- default_options
  settings$optimised_subject <- "^Parent \\(A\\)$"
  subjects <- uploaded_subjects(uploads[[1L]], uploads[[2L]], TRUE, NULL)
  arguments <- c(list(
    inpath = dirname(video), video_path = video,
    output_dir = file.path(root, "clips"), output = "folder",
    ffmpeg = tools[["ffmpeg"]]
  ), pipeline_options(settings, subjects))
  run_pipeline <- function(arguments) {
    do.call(facereaderconverter::synchrony_moments_pipeline, arguments)
  }
  legacy <- arguments
  legacy$optimised_subject <- "Parent (A)"
  expect_error(
    callr::r(run_pipeline, args = list(legacy)),
    "`optimised_subject` must match exactly one subject name.", fixed = TRUE
  )
  shiny::testServer(app_environment$server, {
    do.call(session$setInputs, c(settings, list(
      video = data.frame(name = "recording.mp4", datapath = video),
      first = uploads[[1L]], second = uploads[[2L]]
    )))
    expect_true(inputs_ready())
    session$setInputs(process = 1)
    expect_true(state$busy)
    process <- get("worker", envir = environment(poll_worker))
    process$wait(timeout = 30000)
    expect_false(process$is_alive())
    result <- process$get_result()
    expect_identical(
      sort(unique(as.character(result$results[[1L]]$coding_input$subject))),
      sort(subjects())
    )
    poll_worker(get("run_id", envir = environment(poll_worker)))
    session$flushReact()
    expect_false(state$busy)
    expect_equal(nrow(state$manifest), 1L)
    expect_identical(output$status, "Generated 1 clips.")
    paths <- file.path(state$clip_dir, state$manifest$clip_filename)
    expect_true(all(file.exists(paths)), info = paste(paths, collapse = "\n"))

    mapping_path <- file.path(root, "subjects.csv")
    mapping <- data.frame(
      export_filename = c("parent_export.txt", "child_export.txt"),
      subject = c("Mapped [A]", "Mapped child")
    )
    utils::write.csv(mapping, mapping_path, row.names = FALSE)
    session$setInputs(subject_map = data.frame(name = "subjects.csv", datapath = mapping_path))
    expect_false(inputs_ready())
    session$setInputs(optimised_subject = "^Mapped \\[A\\]$", only_synchronies = FALSE)
    expect_true(inputs_ready())
    session$setInputs(process = 2)
    expect_true(state$busy)
    process <- get("worker", envir = environment(poll_worker))
    process$wait(timeout = 30000)
    expect_false(process$is_alive())
    result <- process$get_result()
    expect_identical(
      sort(unique(as.character(result$results[[1L]]$coding_input$subject))),
      sort(subjects())
    )
    poll_worker(get("run_id", envir = environment(poll_worker)))
    session$flushReact()
    expect_false(state$busy)
    expect_equal(nrow(state$manifest), 1L)
    expect_identical(as.character(state$manifest$subject1), "Mapped [A]")
    expect_true(all(is.na(state$manifest$subject2)))
    expect_true(all(file.exists(file.path(state$clip_dir, state$manifest$clip_filename))))

    mapping$subject <- "Repeated"
    utils::write.csv(mapping, mapping_path, row.names = FALSE)
    session$setInputs(subject_map = data.frame(name = "duplicate.csv", datapath = mapping_path))
    expect_false(inputs_ready())
    expect_match(output$status, "two distinct subjects", fixed = TRUE)
    session$setInputs(process = 3)
    expect_false(state$busy)
  })
})
