video_extensions <- c("mp4", "mov", "mkv", "avi")
fr_extensions <- c("txt", "xlsx")
face_reader_emotions <- c(
  "happy",
  "sad",
  "angry",
  "surprised",
  "scared",
  "disgusted"
)

validate_upload <- function(upload, extensions, label) {
  if (
    is.null(upload) ||
      nrow(upload) != 1L ||
      !tolower(tools::file_ext(upload$name[[1L]])) %in% extensions ||
      !file.exists(upload$datapath[[1L]]) ||
      file.info(upload$datapath[[1L]])$size <= 0
  ) {
    stop(
      sprintf(
        "Select one non-empty %s file (%s).",
        label,
        paste(extensions, collapse = ", ")
      ),
      call. = FALSE
    )
  }
  invisible(TRUE)
}

validate_detailed_export <- function(upload, video) {
  validate_upload(upload, fr_extensions, "FaceReader")
  validate_upload(video, video_extensions, "video")
  path <- upload$datapath[[1L]]
  extension <- tolower(tools::file_ext(upload$name[[1L]]))
  # Shiny's upload paths have no extension; the package dispatches on the suffix.
  staged <- tempfile(fileext = paste0(".", extension))
  on.exit(unlink(staged), add = TRUE)
  if (!file.copy(path, staged)) {
    stop("Could not inspect the FaceReader export.", call. = FALSE)
  }
  metadata <- getFromNamespace(
    "synchrony_fr_header_metadata",
    "facereaderconverter"
  )(staged)
  if (!identical(metadata$type, "detailed")) {
    stop("FaceReader export must be a detailed analysis.", call. = FALSE)
  }
  if (
    length(metadata$fps) != 1L ||
      !is.finite(metadata$fps) ||
      metadata$fps <= 0 ||
      metadata$fps != round(metadata$fps)
  ) {
    stop("FaceReader export needs a valid frame rate.", call. = FALSE)
  }
  if (extension == "txt") {
    lines <- readr::read_lines(staged, n_max = 200L)
    row <- getFromNamespace("detect_fr_header_row", "facereaderconverter")(
      lines
    )
    headers <- strsplit(lines[[row]], "\t|;|,", perl = TRUE)[[1L]]
  } else {
    preview <- suppressMessages(readxl::read_excel(
      staged,
      n_max = 200L,
      col_names = FALSE
    ))
    row <- getFromNamespace("detect_fr_header_row", "facereaderconverter")(
      as.character(preview[[1L]])
    )
    headers <- as.character(unlist(preview[row, ], use.names = FALSE))
  }
  headers <- tolower(trimws(headers))
  if (!all(c("video time", "neutral", face_reader_emotions) %in% headers)) {
    stop(
      "FaceReader detailed export needs Video Time and emotion columns.",
      call. = FALSE
    )
  }
  invisible(metadata)
}

upload_validation <- function(video, first, second, ffprobe) {
  tryCatch(
    {
      warnings <- character()
      video_key <- function(value) {
        tolower(tools::file_path_sans_ext(basename(gsub("\\\\", "/", value))))
      }
      validate_upload(video, video_extensions, "video")
      first_metadata <- validate_detailed_export(first, video)
      second_metadata <- validate_detailed_export(second, video)
      for (entry in list(
        list(upload = first, metadata = first_metadata),
        list(upload = second, metadata = second_metadata)
      )) {
        upload <- entry$upload
        metadata <- entry$metadata
        if (
          length(metadata$video_filename) != 1L ||
            is.na(metadata$video_filename) ||
            !nzchar(metadata$video_filename) ||
            !identical(
              video_key(metadata$video_filename),
              video_key(video$name[[1L]])
            )
        ) {
          warnings <- c(
            warnings,
            sprintf(
              "%s metadata names '%s', which does not match the uploaded video '%s'.",
              upload$name[[1L]],
              metadata$video_filename,
              video$name[[1L]]
            )
          )
        }
      }
      if (!identical(first_metadata$fps, second_metadata$fps)) {
        warnings <- c(
          warnings,
          sprintf(
            "The FaceReader exports use different frame rates (%s and %s).",
            first_metadata$fps,
            second_metadata$fps
          )
        )
      }
      names <- vapply(
        list(video, first, second),
        function(upload) safe_upload_name(upload$name[[1L]]),
        character(1)
      )
      if (any(!nzchar(names)) || anyDuplicated(tolower(names))) {
        stop("Upload filenames must be distinct.", call. = FALSE)
      }
      if (inherits(ffprobe, "error")) {
        stop(conditionMessage(ffprobe), call. = FALSE)
      }
      if (length(ffprobe) != 1L || !file.exists(ffprobe)) {
        stop("FFprobe is unavailable.", call. = FALSE)
      }
      probe <- suppressWarnings(system2(
        ffprobe,
        c(
          "-v",
          "error",
          "-select_streams",
          "v:0",
          "-show_entries",
          "stream=codec_type",
          "-of",
          "default=noprint_wrappers=1",
          shQuote(video$datapath[[1L]])
        ),
        stdout = TRUE,
        stderr = TRUE
      ))
      if (!is.null(attr(probe, "status")) || !"codec_type=video" %in% probe) {
        stop("The uploaded video cannot be read.", call. = FALSE)
      }
      list(error = NULL, warnings = unique(warnings))
    },
    error = function(error) {
      list(error = error, warnings = character())
    }
  )
}

upload_readiness_error <- function(video, first, second, ffprobe) {
  upload_validation(video, first, second, ffprobe)$error
}

uploads_ready <- function(video, first, second, ffprobe) {
  is.null(upload_readiness_error(video, first, second, ffprobe))
}

safe_upload_name <- function(name) {
  gsub("[^[:alnum:]_.-]", "_", basename(gsub("\\\\", "/", name)))
}

stage_uploads <- function(video, first, second, root) {
  validate_upload(video, video_extensions, "video")
  validate_upload(first, fr_extensions, "FaceReader")
  validate_upload(second, fr_extensions, "FaceReader")
  if (!dir.create(root, recursive = TRUE, showWarnings = FALSE)) {
    stop("Could not create a processing workspace.", call. = FALSE)
  }
  files <- list(video, first, second)
  names <- vapply(
    files,
    function(x) safe_upload_name(x$name[[1L]]),
    character(1)
  )
  if (any(!nzchar(names)) || anyDuplicated(tolower(names))) {
    stop(
      "Upload filenames must be distinct, including case-insensitive matches.",
      call. = FALSE
    )
  }
  paths <- file.path(root, names)
  for (i in seq_along(files)) {
    if (!file.copy(files[[i]]$datapath[[1L]], paths[[i]])) {
      stop("Failed to stage the uploaded files.", call. = FALSE)
    }
  }
  paths
}

parse_subject_map <- function(upload) {
  if (is.null(upload)) {
    return(NULL)
  }
  validate_upload(upload, "csv", "subject map")
  mapping <- utils::read.csv(upload$datapath[[1L]], stringsAsFactors = FALSE)
  if (
    !all(c("export_filename", "subject") %in% names(mapping)) ||
      anyNA(mapping[, c("export_filename", "subject")]) ||
      any(!nzchar(trimws(mapping$export_filename))) ||
      any(!nzchar(trimws(mapping$subject))) ||
      anyDuplicated(tolower(mapping$export_filename))
  ) {
    stop(
      "Subject map needs unique export_filename and non-empty subject columns.",
      call. = FALSE
    )
  }
  keys <- vapply(
    trimws(mapping$export_filename),
    safe_upload_name,
    character(1)
  )
  if (anyDuplicated(tolower(keys))) {
    stop("Subject map filenames collide after upload staging.", call. = FALSE)
  }
  stats::setNames(trimws(mapping$subject), keys)
}

parse_optional_number <- function(value, label) {
  if (is.null(value) || !nzchar(trimws(value))) {
    return(NULL)
  }
  number <- suppressWarnings(as.numeric(value))
  if (
    length(number) != 1L ||
      !is.finite(number) ||
      number < 0 ||
      number != floor(number) ||
      number > .Machine$integer.max
  ) {
    stop(
      sprintf("%s must be a non-negative whole number or blank.", label),
      call. = FALSE
    )
  }
  as.integer(number)
}

parse_emotions <- function(value, allow_neutral = FALSE) {
  if (is.null(value) || !length(value)) {
    return(NULL)
  }
  choices <- if (allow_neutral) {
    c(face_reader_emotions, "neutral")
  } else {
    face_reader_emotions
  }
  if (!is.character(value) || anyNA(value) || any(!value %in% choices)) {
    stop("Select emotions from the FaceReader dropdown.", call. = FALSE)
  }
  unique(value)
}

participant_label <- function(x) {
  tolower(sub(":$", "", trimws(x)))
}

# Metadata lines are "Participant Name<TAB>value"; detailed exports place
# "Participant Name" as a table column header, with values in the next row.
participant_from_txt <- function(lines) {
  split_cells <- function(line) strsplit(line, "\t", fixed = TRUE)[[1L]]
  has_label <- function(line) {
    any(participant_label(split_cells(line)) == "participant name")
  }
  header <- Position(has_label, lines)
  if (is.null(header)) {
    return(NA_character_)
  }
  cells <- split_cells(lines[[header]])
  if (
    length(cells) == 2L && participant_label(cells[[1L]]) == "participant name"
  ) {
    return(trimws(cells[[2L]]))
  }
  col <- which(participant_label(cells) == "participant name")[1L]
  if (header == length(lines)) {
    return(NA_character_)
  }
  values <- split_cells(lines[[header + 1L]])
  if (col > length(values)) NA_character_ else trimws(values[[col]])
}

participant_from_xlsx <- function(path) {
  preview <- suppressMessages(readxl::read_excel(
    path,
    n_max = 200L,
    col_names = FALSE
  ))
  grid <- unname(as.matrix(as.data.frame(
    lapply(preview, as.character),
    stringsAsFactors = FALSE
  )))
  hit <- which(participant_label(grid) == "participant name", arr.ind = TRUE)
  if (nrow(hit) == 0L) {
    return(NA_character_)
  }
  row <- hit[[1L, 1L]]
  col <- hit[[1L, 2L]]
  filled <- which(!is.na(grid[row, ]) & nzchar(trimws(grid[row, ])))
  if (length(filled) == 2L) {
    return(if (col < ncol(grid)) trimws(grid[row, col + 1L]) else NA_character_)
  }
  if (row == nrow(grid)) NA_character_ else trimws(grid[row + 1L, col])
}

participant_name <- function(upload) {
  fallback <- tools::file_path_sans_ext(upload$name[[1L]])
  extension <- tolower(tools::file_ext(upload$name[[1L]]))
  name <- tryCatch(
    {
      staged <- tempfile(fileext = paste0(".", extension))
      on.exit(unlink(staged), add = TRUE)
      file.copy(upload$datapath[[1L]], staged)
      if (extension == "txt") {
        participant_from_txt(readr::read_lines(staged, n_max = 200L))
      } else {
        participant_from_xlsx(staged)
      }
    },
    error = function(e) NA_character_
  )
  if (length(name) != 1L || is.na(name) || !nzchar(name)) fallback else name
}

subject_choices <- function(first = NULL, second = NULL) {
  choices <- character()
  add <- function(label, name) {
    if (!is.null(name)) {
      value <- paste0("^", gsub("([][{}()+*^$|\\\\?.])", "\\\\\\1", name), "$")
      choices[[sprintf("%s: %s", label, name)]] <<- value
    }
  }
  add("Participant 1", first)
  add("Participant 2", second)
  c(choices, both = "both")
}

pipeline_options <- function(input) {
  numeric_options <- c(
    "T_up",
    "T_down",
    "delta",
    "delta_window",
    "min_dur_sec",
    "time_limit",
    "missing_threshold",
    "buffer_before",
    "buffer_after"
  )
  for (key in numeric_options) {
    value <- input[[key]]
    if (length(value) != 1L || !is.finite(value) || value < 0) {
      stop(sprintf("%s must be a non-negative number.", key), call. = FALSE)
    }
  }
  integers <- c("consecutive_missing", "cores", "n")
  for (key in integers) {
    value <- input[[key]]
    if (
      length(value) != 1L ||
        !is.finite(value) ||
        value < 0 ||
        value != floor(value) ||
        value > .Machine$integer.max
    ) {
      stop(
        sprintf("%s must be a non-negative whole number.", key),
        call. = FALSE
      )
    }
  }
  if (input$T_down > input$T_up) {
    stop("T_down cannot exceed T_up.", call. = FALSE)
  }
  if (!input$constraint_method %in% c("episode", "strict", "loose")) {
    stop("Select a supported constraint method.", call. = FALSE)
  }
  list(
    subject_from_filename = TRUE,
    subject_map = NULL,
    verbose = FALSE,
    T_up = input$T_up,
    T_down = input$T_down,
    delta = input$delta,
    delta_window = input$delta_window,
    min_dur_sec = input$min_dur_sec,
    consecutive_missing = as.integer(input$consecutive_missing),
    cores = as.integer(input$cores),
    time_limit = input$time_limit,
    time_limit_frames = NULL,
    constraint_method = input$constraint_method,
    missing_threshold = input$missing_threshold,
    exclude_emotions = "neutral",
    n = as.integer(input$n),
    emotion = parse_emotions(input$emotion),
    optimised_subject = input$optimised_subject,
    only_synchronies = input$only_synchronies,
    buffer = c(before = input$buffer_before, after = input$buffer_after),
    buffer_units = "seconds"
  )
}

clip_export_percent <- function(output) {
  matches <- regmatches(
    output,
    gregexpr("[[:space:]][[:digit:]]{1,3}%", output)
  )[[1L]]
  if (!length(matches)) {
    return(NULL)
  }
  percent <- as.integer(sub("%$", "", trimws(tail(matches, 1L))))
  if (percent > 100L) NULL else percent
}

ordered_clips <- function(manifest, order_by = "time") {
  if (is.null(manifest) || !nrow(manifest)) {
    return(manifest)
  }
  key <- if (identical(order_by, "rank")) "selection_rank" else "clip_order"
  manifest[order(manifest[[key]], manifest$selection_rank), , drop = FALSE]
}

create_clips_zip <- function(manifest, clip_dir, destination) {
  if (is.null(manifest) || !nrow(manifest)) {
    stop("There are no clips to download.", call. = FALSE)
  }
  filenames <- as.character(manifest$clip_filename)
  if (
    anyNA(filenames) ||
      anyDuplicated(filenames) ||
      any(basename(filenames) != filenames) ||
      any(!grepl("\\.mp4$", filenames, ignore.case = TRUE))
  ) {
    stop("Invalid clip manifest.", call. = FALSE)
  }
  files <- file.path(clip_dir, filenames)
  if (!all(file.exists(files))) {
    stop("One or more clips are missing.", call. = FALSE)
  }
  manifest_path <- file.path(clip_dir, "manifest.csv")
  if (!file.exists(manifest_path)) {
    utils::write.csv(manifest, manifest_path, row.names = FALSE)
  }
  zip::zipr(destination, files = c(filenames, "manifest.csv"), root = clip_dir)
  invisible(destination)
}

binary_directory <- function(
  root,
  os = Sys.info()[["sysname"]],
  arch = Sys.info()[["machine"]]
) {
  platform <- switch(
    tolower(os),
    windows = "windows",
    darwin = "macos",
    linux = "linux",
    stop("Unsupported operating system.", call. = FALSE)
  )
  architecture <- if (tolower(arch) %in% c("x86_64", "x86-64", "amd64")) {
    "x64"
  } else if (tolower(arch) %in% c("arm64", "aarch64") && platform == "macos") {
    "arm64"
  } else {
    stop("Unsupported CPU architecture.", call. = FALSE)
  }
  file.path(root, "bin", paste(platform, architecture, sep = "-"))
}

locate_media_tools <- function(
  root,
  os = Sys.info()[["sysname"]],
  arch = Sys.info()[["machine"]]
) {
  directory <- binary_directory(root, os, arch)
  suffix <- if (tolower(os) == "windows") ".exe" else ""
  paths <- file.path(directory, paste0(c("ffmpeg", "ffprobe"), suffix))
  if (!all(file.exists(paths))) {
    stop(
      sprintf("Bundled FFmpeg and FFprobe are required in %s.", directory),
      call. = FALSE
    )
  }
  stats::setNames(
    normalizePath(paths, winslash = "/", mustWork = TRUE),
    c("ffmpeg", "ffprobe")
  )
}
