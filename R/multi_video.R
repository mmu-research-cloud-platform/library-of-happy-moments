run_media_command <- function(ffmpeg, args, label, verbose = FALSE) {
  diagnostics <- suppressWarnings(system2(
    ffmpeg, c("-nostdin", "-y", "-v", "error", args),
    stdout = TRUE, stderr = TRUE
  ))
  if (isTRUE(verbose) && length(diagnostics)) message(paste(diagnostics, collapse = "\n"))
  if (!is.null(attr(diagnostics, "status"))) {
    stop(sprintf("%s: %s", label, paste(diagnostics, collapse = "\n")), call. = FALSE)
  }
}

export_video_views <- function(manifest, videos, output_dir, primary, info, ffmpeg, verbose) {
  width <- ceiling(info[[1L]]$width / 2) * 2
  height <- ceiling(info[[1L]]$height / 2) * 2
  fps <- info[[1L]]$fps
  for (camera in seq_along(videos)) {
    directory <- file.path(output_dir, "views", paste0("video_", camera))
    if (!dir.create(directory, recursive = TRUE)) {
      stop("Could not create the camera clip directory.", call. = FALSE)
    }
    for (i in seq_len(nrow(manifest))) {
      destination <- file.path(directory, manifest$clip_filename[[i]])
      args <- c(
        "-i", shQuote(videos[[camera]]),
        "-ss", sprintf("%.9f", manifest$start_seconds[[i]]),
        "-t", sprintf("%.9f", manifest$duration_seconds[[i]]),
        "-map", "0:v:0",
        if (camera == primary) c("-map", "0:a:0?") else "-an",
        "-vf", shQuote(sprintf("fps=%.9f,pad=ceil(iw/2)*2:ceil(ih/2)*2", fps)),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
        "-movflags", "+faststart", shQuote(destination)
      )
      run_media_command(ffmpeg, args, sprintf("Could not create video %d, clip %d", camera, i), verbose)
      if (!file.exists(destination) || file.info(destination)$size <= 0) {
        stop("FFmpeg did not create a camera clip.", call. = FALSE)
      }
    }
  }
  for (i in seq_len(nrow(manifest))) {
    views <- file.path(output_dir, "views", paste0("video_", seq_along(videos)), manifest$clip_filename[[i]])
    destination <- file.path(output_dir, manifest$clip_filename[[i]])
    if (length(videos) == 1L) {
      if (!file.copy(views[[1L]], destination)) stop("Could not save the clip.", call. = FALSE)
    } else {
      filters <- vapply(seq_along(videos), function(camera) {
        sprintf(
          "[%d:v:0]scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,setsar=1,setpts=PTS-STARTPTS[v%d]",
          camera - 1L, width, height, width, height, camera
        )
      }, character(1))
      layout <- paste(sprintf("%d_%d", ((seq_along(videos) - 1L) %% 2L) * width,
        ((seq_along(videos) - 1L) %/% 2L) * height), collapse = "|")
      stack <- sprintf("%sxstack=inputs=%d:layout=%s:fill=black:shortest=1[out]",
        paste0("[v", seq_along(videos), "]", collapse = ""), length(videos), layout)
      args <- c(
        unlist(lapply(views, function(path) c("-i", shQuote(path))), use.names = FALSE),
        "-filter_complex_threads", "1",
        "-filter_complex", shQuote(paste(c(filters, stack), collapse = ";")),
        "-map", shQuote("[out]"), "-map", sprintf("%d:a:0?", primary - 1L),
        "-t", sprintf("%.9f", manifest$duration_seconds[[i]]),
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
        "-movflags", "+faststart", shQuote(destination)
      )
      run_media_command(ffmpeg, args, sprintf("Could not compose clip %d", i), verbose)
    }
    if (!file.exists(destination) || file.info(destination)$size <= 0) {
      stop("FFmpeg did not create the composite clip.", call. = FALSE)
    }
    if (!isTRUE(verbose)) cat(sprintf("\rExporting clips %d%%", round(i / nrow(manifest) * 100)))
  }
  invisible(manifest)
}

run_shared_video_pipeline <- function(videos, exports, output_dir, primary, tolerance_ms, options, media_tools) {
  info <- lapply(videos, probe_video, ffprobe = media_tools[["ffprobe"]])
  duration <- validate_video_durations(
    vapply(info, `[[`, numeric(1), "duration"), tolerance_ms, basename(videos)
  )
  uploads <- lapply(exports, function(path) data.frame(name = basename(path), datapath = path))
  subjects <- uploaded_subjects(
    uploads[[1L]], uploads[[2L]], options$subject_from_filename, options$subject_map
  )
  resolve_optimised_subject(options$optimised_subject, subjects)
  inputs <- lapply(seq_along(exports), function(i) {
    data <- facereaderconverter::loadFRfile(exports[[i]], values_as_numeric = TRUE, clean_names = TRUE)
    data$id <- "video_001"
    data$subject <- subjects[[i]]
    data
  })
  coding_input <- dplyr::bind_rows(inputs)
  coding_input <- coding_input[, c("id", "subject", "video_time",
    intersect(c("neutral", face_reader_emotions), names(coding_input)))]
  metadata <- lapply(exports, getFromNamespace("synchrony_fr_header_metadata", "facereaderconverter"))
  fr_durations <- vapply(seq_along(inputs), function(i) {
    facereader_duration(inputs[[i]], metadata[[i]]$fps, basename(exports[[i]]))
  }, numeric(1))
  validate_video_durations(
    c(vapply(info, `[[`, numeric(1), "duration"), fr_durations),
    tolerance_ms, c(basename(videos), basename(exports)), label = "Video/FaceReader"
  )
  fps <- metadata[[1L]]$fps
  if (!identical(fps, metadata[[2L]]$fps)) {
    warning("The FaceReader exports use different frame rates; analysis uses participant 1's frame rate.", call. = FALSE)
  }
  coded <- do.call(facereaderconverter::convert_to_episodes, c(list(
    coding_df = coding_input, fps = fps
  ), options[c("T_up", "T_down", "delta", "delta_window", "min_dur_sec", "consecutive_missing", "cores")]))
  shared <- do.call(facereaderconverter::shared_synchronous_episodes, c(list(
    coded_data = coded, fps = fps
  ), options[c("time_limit", "time_limit_frames", "constraint_method", "missing_threshold", "exclude_emotions")]))
  selected <- if (identical(options$optimised_subject, "both") || options$only_synchronies) shared else coded$episodes
  if (!is.null(options$emotion)) selected <- selected[selected$emotion %in% options$emotion, ]
  manifest <- data.frame()
  if (nrow(selected)) {
    primary_path <- normalizePath(videos[[primary]], winslash = "/", mustWork = TRUE)
    manifest <- getFromNamespace("prepare_shared_synchrony_clips", "facereaderconverter")(
      coded_data = coded, shared_synchrony = shared,
      video_paths = c(video_001 = primary_path),
      n = options$n, emotion = options$emotion,
      optimised_subject = options$optimised_subject, only_synchronies = options$only_synchronies,
      buffer = options$buffer, buffer_units = options$buffer_units,
      video_durations = stats::setNames(duration, primary_path)
    )
    manifest <- as.data.frame(manifest)
    manifest$duration_seconds <- pmin(manifest$duration_seconds, duration - manifest$start_seconds)
    if (any(manifest$duration_seconds <= 0)) {
      stop("Selected intervals lie outside the shared video timeline.", call. = FALSE)
    }
    if (!dir.create(output_dir, recursive = TRUE)) stop("Could not create the clip directory.", call. = FALSE)
    export_video_views(manifest, videos, output_dir, primary, info, media_tools[["ffmpeg"]], options$verbose)
    manifest$clip_path <- file.path(output_dir, manifest$clip_filename)
    manifest$video_count <- length(videos)
    manifest$audio_source <- basename(videos[[primary]])
    utils::write.csv(manifest, file.path(output_dir, "manifest.csv"), row.names = FALSE)
  }
  list(results = list(list(
    coding_input = coding_input, coded_data = coded, shared_moments = shared,
    clip_manifest = manifest, clip_output = output_dir
  )), video_count = length(videos), primary = primary)
}
