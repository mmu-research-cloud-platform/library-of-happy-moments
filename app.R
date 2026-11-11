library(shiny)
library(bslib)
source("R/app_helpers.R", local = TRUE)
source("R/multi_video.R", local = TRUE)

app_root <- normalizePath(".", winslash = "/", mustWork = TRUE)
startup_token <- Sys.getenv("STARTUP_TOKEN", unset = "")
media_tools <- tryCatch(locate_media_tools(app_root), error = identity)
if (!inherits(media_tools, "error")) {
  Sys.setenv(
    PATH = paste(
      dirname(media_tools[["ffprobe"]]),
      Sys.getenv("PATH"),
      sep = .Platform$path.sep
    )
  )
}
options(shiny.maxRequestSize = 1024 * 1024^2)

ui <- page_sidebar(
  title = "Library of Happy Moments",
  if (nzchar(startup_token)) {
    tags$meta(name = "app-startup", content = paste0("startup-", startup_token))
  },
  theme = bs_theme(version = 5, primary = "#00afff") |>
    bs_add_rules(
      "\n      body.bslib-page-sidebar > .navbar.navbar-static-top {
        background: #00afff;
        color: #002b40;
      }
      body.bslib-page-sidebar > .navbar .navbar-brand { color: #002b40; }
    "
    ),
  class = "bslib-page-dashboard",
  tags$head(tags$script(HTML(
    "$(function() {
    Shiny.addCustomMessageHandler('process-readiness', function(status) {
      $('#process').prop('disabled', !status.ready);
      $('#clear_inputs, #add_video, [id^=remove_video_], [id^=reset_], input[type=file], #audio_source, #duration_tolerance').prop('disabled', status.busy);
    });
    Shiny.addCustomMessageHandler('clear-upload-inputs', function(ids) {
      if (ids !== 'subject_map') $('#process').prop('disabled', true);
      (ids === 'subject_map' ? ['subject_map'] :
        Array.from(document.querySelectorAll('input[type=file]'), function(el) { return el.id; })).forEach(function(id) {
        var input = $('#' + id);
        input.val('');
        input.closest('.input-group').find('input[type=text]').val('');
        Shiny.setInputValue(id, null, {priority: 'event'});
      });
    });
    Shiny.addCustomMessageHandler('confirm-metadata-process', function(value) {
      Shiny.setInputValue('process', value + 1, {priority: 'event'});
    });
  });"
  )), tags$script(src = "multi-video.js"), tags$style(HTML(
    ".video-grid { display: grid; grid-template-columns: repeat(var(--video-columns, 2), minmax(0, 1fr)); gap: 1rem; }
     .video-grid video { width: 100%; }
     @media (max-width: 600px) { .video-grid { grid-template-columns: 1fr; } }"
  ))),
  sidebar = sidebar(
    card(
      card_header("Video"),
      div(id = "additional_videos",
        div(id = "container_video",
          fileInput("video", "Select video", accept = paste0(".", video_extensions)),
          uiOutput("remove_control_video")
        )
      ),
      actionButton("add_video", "Add video")
    ),
    card(
      card_header("FaceReader participant 1"),
      fileInput(
        "first",
        "Select detailed export",
        accept = paste0(".", fr_extensions)
      )
    ),
    card(
      card_header("FaceReader participant 2"),
      fileInput(
        "second",
        "Select detailed export",
        accept = paste0(".", fr_extensions)
      )
    ),
    div(
      class = "d-flex flex-wrap gap-2 align-items-center my-3",
      input_task_button(
        "process",
        "Process video",
        type = "primary",
        disabled = NA
      ),
      actionButton("clear_inputs", "Clear inputs"),
      uiOutput("cancel_control", inline = TRUE)
    ),
    accordion(
      open = FALSE,
      accordion_panel(
        "Multi-video",
        selectInput("audio_source", "Audio source", choices = c("First video added" = "video"), selected = "video"),
        numericInput("duration_tolerance", "Duration tolerance (milliseconds)", 0, min = 0),
        numericInput("video_columns", "Playback columns", 2, min = 1, step = 1),
        actionButton("reset_multi_video", "Reset multi-video")
      ),
      accordion_panel(
        "Advanced options",
        accordion(
          open = FALSE,
          accordion_panel(
            "Clip export",
            numericInput("n", "Number of clips (0 = all)", 10, min = 0),
            selectizeInput(
              "emotion",
              "Emotions (none = all)",
              choices = face_reader_emotions,
              selected = "happy",
              multiple = TRUE
            ),
            selectInput(
              "optimised_subject",
              "Optimised subject",
              choices = c("Both subjects (combined)" = "both"),
              selected = "both"
            ),
            checkboxInput("only_synchronies", "Only synchronies", TRUE),
            numericInput(
              "buffer_before",
              "Buffer before (seconds)",
              5,
              min = 0
            ),
            numericInput("buffer_after", "Buffer after (seconds)", 3, min = 0),
            actionButton("reset_clip_export", "Reset clip export")
          ),
          accordion_panel(
            "Matching and diagnostics",
            checkboxInput(
              "subject_from_filename",
              "Use filenames for missing participant names",
              TRUE
            ),
            fileInput(
              "subject_map",
              "Subject mapping CSV (optional)",
              accept = ".csv"
            ),
            checkboxInput(
              "verbose",
              "Show FFmpeg diagnostics in console",
              FALSE
            ),
            actionButton("reset_matching", "Reset matching and diagnostics")
          ),
          accordion_panel(
            "Synchrony selection",
            numericInput("time_limit", "Time limit (seconds)", 3, min = 0),
            selectInput(
              "constraint_method",
              "Constraint method",
              c("episode", "strict", "loose")
            ),
            numericInput(
              "missing_threshold",
              "Missing threshold",
              0,
              min = 0,
              max = 1
            ),
            actionButton("reset_synchrony", "Reset synchrony selection")
          ),
          accordion_panel(
            "Episode detection",
            numericInput("T_up", "Entry threshold", 0.20, min = 0, step = 0.01),
            numericInput("T_down", "Exit threshold", 0.1, min = 0, step = 0.01),
            numericInput(
              "delta",
              "Delta threshold",
              0.10,
              min = 0,
              step = 0.01
            ),
            numericInput(
              "delta_window",
              "Delta window (seconds)",
              0.2,
              min = 0
            ),
            numericInput(
              "min_dur_sec",
              "Minimum duration (seconds)",
              0.1,
              min = 0
            ),
            numericInput(
              "consecutive_missing",
              "Consecutive missing frames",
              150,
              min = 0
            ),
            numericInput("cores", "Cores (0 = package default)", 0, min = 0),
            actionButton("reset_episode", "Reset episode detection")
          )
        ),
        actionButton("reset_advanced", "Reset all inputs")
      )
    ),
    width = 350
  ),
  navset_tab(
    nav_panel(
      "Clips",
      textOutput("status"),
      uiOutput("processing_progress"),
      card(
        card_header("Generated clips"),
        div(
          class = "d-flex gap-2 align-items-center mb-3",
          selectInput(
            "clip_order",
            "Order clips by",
            c("Time" = "time", "Rank" = "rank"),
            width = "180px"
          ),
          actionButton("previous", "← Previous"),
          actionButton("next_clip", "Next →"),
          textOutput("position", inline = TRUE)
        ),
        uiOutput("player"),
        div(class = "mt-3", uiOutput("download_control", inline = TRUE))
      )
    ),
    nav_panel(
      "Instructions",
      card(
        card_header("How to create clips"),
        tags$ol(
          tags$li("Upload one video (MP4, MOV, MKV, or AVI), then use Add video below it in the sidebar for more camera views. When multiple videos exist, Remove video removes only that input, including the first; remaining uploads are preserved and labels are renumbered. Audio, duration tolerance and playback columns remain in Advanced options > Multi-video. All videos must already share the same starting point."),
          tags$li(
            "Upload two distinct, detailed FaceReader exports (TXT or XLSX), ",
            "one for each participant. Filename metadata is checked against the ",
            "selected Audio source, with confirmation required for mismatches. The same two exports are shared by all views."
          ),
          tags$li(
            "Choose the Audio source (first video added by default). All videos and both FaceReader exports must match in duration unless you set a duration tolerance in milliseconds. FaceReader duration includes its final Video Time frame. Accepted differences use the shortest video timeline."
          ),
          tags$li(
            "Optionally adjust Advanced options in the sidebar. If using a subject ",
            "mapping CSV, include export_filename and subject columns."
          ),
          tags$li(
            "When all inputs pass validation, select Process video. ",
            "Review synchronized clips on the Clips tab. Playback columns are configurable; downloaded clips always use a two-column composite (one video stays full-frame)."
          )
        ),
        p(
          "Clear inputs removes uploads and previously generated clips. ",
          "Reset all inputs also restores default settings; each advanced panel has its own reset button."
        )
      )
    )
  )
)

server <- function(input, output, session) {
  workspace <- tempfile("happy-moments-")
  dir.create(workspace)
  state <- reactiveValues(
    manifest = NULL,
    clip_dir = NULL,
    index = 1L,
    resource = NULL,
    status = "Upload a video and two detailed FaceReader files.",
    busy = FALSE,
    percent = NULL,
    video_count = 1L,
    primary = 1L,
    results_root = NULL
  )
  video_ids <- reactiveVal("video")
  next_video_id <- 1L
  uploaded_video_ids <- reactive({
    ids <- video_ids()
    ids[vapply(ids, function(id) !is.null(input[[id]]), logical(1))]
  })
  videos <- reactive(lapply(uploaded_video_ids(), function(id) input[[id]]))
  primary_video <- reactive({
    selected <- match(input$audio_source, uploaded_video_ids())
    if (length(selected) != 1L || is.na(selected)) 1L else selected
  })
  register_video_removal <- function(id) {
    force(id)
    output[[paste0("remove_control_", id)]] <- renderUI({
      if (length(video_ids()) > 1L) {
        actionButton(paste0("remove_", id), "Remove video")
      }
    })
    observeEvent(input[[paste0("remove_", id)]], {
      if (state$busy || length(video_ids()) <= 1L || !id %in% video_ids()) return()
      removeUI(paste0("#container_", id), immediate = TRUE)
      video_ids(setdiff(video_ids(), id))
    }, ignoreInit = TRUE)
  }
  register_video_removal("video")
  observeEvent(input$add_video, {
    if (state$busy) return()
    next_video_id <<- next_video_id + 1L
    id <- paste0("video_", next_video_id)
    label_id <- paste0("label_", id)
    output[[label_id]] <- renderText(paste("Video", match(id, video_ids())))
    insertUI("#additional_videos", "beforeEnd", ui = div(
      id = paste0("container_", id),
      fileInput(id, textOutput(label_id, inline = TRUE), accept = paste0(".", video_extensions)),
      uiOutput(paste0("remove_control_", id))
    ), immediate = TRUE)
    video_ids(c(video_ids(), id))
    register_video_removal(id)
  })
  observe({
    ids <- uploaded_video_ids()
    labels <- vapply(seq_along(ids), function(i) {
      upload <- input[[ids[[i]]]]
      if (is.null(upload)) paste("Video", i) else paste(i, upload$name[[1L]], sep = ": ")
    }, character(1))
    selected <- isolate(input$audio_source) %||% "video"
    if (!selected %in% ids) selected <- if (length(ids)) ids[[1L]] else character()
    updateSelectInput(session, "audio_source", choices = stats::setNames(ids, labels), selected = selected)
  })
  observe({
    columns <- input$video_columns %||% 2
    if (length(columns) != 1L || !is.finite(columns) || columns < 1 || columns != floor(columns)) {
      showNotification("Playback columns must be a positive whole number.", type = "error")
      return()
    }
    session$sendCustomMessage("video-columns", columns)
  })
  worker <- NULL
  run_root <- NULL
  run_id <- 0L
  pending_cancel <- NULL
  metadata_confirmed <- reactiveVal(FALSE)
  notified_upload_warnings <- character()
  diagnostics <- FALSE
  observeEvent(
    list(videos(), input$first, input$second, input$audio_source, input$duration_tolerance, input$subject_map),
    {
      metadata_confirmed(FALSE)
      notified_upload_warnings <<- character()
      if (state$busy) {
        run_id <<- run_id + 1L
        if (!is.null(worker) && worker$is_alive()) worker$kill_tree()
        worker <<- NULL
        finish_processing(error = simpleError("Inputs changed. Processing cancelled; regenerate clips."))
      }
      if (!is.null(state$manifest)) {
        discard_results()
        state$status <- "Inputs changed. Regenerate clips."
      }
    },
    ignoreInit = TRUE
  )
  session$onSessionEnded(function() {
    if (!is.null(worker) && worker$is_alive()) {
      worker$kill_tree()
    }
    worker <<- NULL
    resource <- isolate(state$resource)
    if (!is.null(resource)) {
      removeResourcePath(resource)
    }
    unlink(workspace, recursive = TRUE, force = TRUE)
  })
  output$status <- renderText(state$status)
  ffprobe <- if (inherits(media_tools, "error")) {
    media_tools
  } else {
    media_tools[["ffprobe"]]
  }
  upload_validation_result <- reactive(upload_validation(
    videos(),
    input$first,
    input$second,
    ffprobe,
    primary = primary_video(),
    duration_tolerance = input$duration_tolerance %||% 0
  ))
  upload_error <- reactive(upload_validation_result()$error)
  ready <- reactive(is.null(upload_error()))
  subjects <- reactive({
    if (is.null(input$first) || is.null(input$second)) {
      return(NULL)
    }
    uploaded_subjects(
      input$first, input$second, input$subject_from_filename,
      parse_subject_map(input$subject_map), tmpdir = workspace
    )
  })
  observe({
    available <- tryCatch(subjects(), error = identity)
    choices <- c("Both subjects (combined)" = "both")
    if (!is.null(available) && !inherits(available, "error")) {
      choices <- subject_choices(available)
    }
    selection <- isolate(input$optimised_subject)
    if (is.null(selection)) selection <- "both"
    if (!selection %in% choices) {
      selection <- ""
    }
    updateSelectInput(
      session, "optimised_subject",
      choices = c("Select an uploaded subject" = "", choices),
      selected = selection
    )
  })
  option_error <- reactive(tryCatch(
    {
      if (!ready()) {
        return(NULL)
      }
      pipeline_options(input, subjects())
      NULL
    },
    error = identity
  ))
  readiness_error <- reactive({
    if (!is.null(upload_error())) {
      return(upload_error())
    }
    option_error()
  })
  inputs_ready <- reactive(is.null(readiness_error()))
  observe({
    is_ready <- inputs_ready()
    session$sendCustomMessage(
      "process-readiness",
      list(ready = is_ready && !state$busy, busy = state$busy)
    )
  })
  observeEvent(readiness_error(), {
    if (!state$busy) {
      error <- readiness_error()
      has_upload <- any(vapply(videos(), Negate(is.null), logical(1))) ||
        !is.null(input$first) ||
        !is.null(input$second)
      if (!is.null(option_error())) {
        state$status <- display_error(option_error())
      } else if (!is.null(error) && has_upload) {
        state$status <- display_error(error)
      } else if (inherits(media_tools, "error") && !has_upload) {
        state$status <- display_error(media_tools)
      } else if (is.null(error) && has_upload) {
        state$status <- "Inputs validated. Ready to process."
      }
    }
  }, ignoreNULL = FALSE)

  discard_results <- function() {
    state$manifest <- NULL
    state$clip_dir <- NULL
    state$index <- 1L
    if (!is.null(state$resource)) {
      removeResourcePath(state$resource)
      state$resource <- NULL
    }
    if (!is.null(state$results_root)) {
      unlink(state$results_root, recursive = TRUE, force = TRUE)
      state$results_root <- NULL
    }
  }
  retain_first_video <- function() {
    retained <- video_ids()[[1L]]
    for (id in video_ids()[-1L]) removeUI(paste0("#container_", id), immediate = TRUE)
    video_ids(retained)
    updateSelectInput(session, "audio_source", selected = retained)
  }
  clear_inputs <- function() {
    session$sendCustomMessage("clear-upload-inputs", TRUE)
    retain_first_video()
    discard_results()
    if (!is.null(run_root)) {
      unlink(run_root, recursive = TRUE, force = TRUE)
      run_root <<- NULL
    }
    state$status <- "Upload a video and two detailed FaceReader files."
    metadata_confirmed(FALSE)
    notified_upload_warnings <<- character()
  }
  observeEvent(input$clear_inputs, {
    if (!state$busy) {
      clear_inputs()
      notified_upload_warnings <<- character()
    }
  })

  reset_clip_export <- function() {
    updateNumericInput(session, "n", value = 10)
    updateSelectizeInput(session, "emotion", selected = "happy")
    updateSelectInput(session, "optimised_subject", selected = "both")
    updateCheckboxInput(session, "only_synchronies", value = TRUE)
    updateNumericInput(session, "buffer_before", value = 5)
    updateNumericInput(session, "buffer_after", value = 3)
  }
  reset_matching <- function() {
    updateCheckboxInput(session, "subject_from_filename", value = TRUE)
    updateCheckboxInput(session, "verbose", value = FALSE)
    session$sendCustomMessage("clear-upload-inputs", "subject_map")
  }
  reset_synchrony <- function() {
    updateNumericInput(session, "time_limit", value = 3)
    updateSelectInput(session, "constraint_method", selected = "episode")
    updateNumericInput(session, "missing_threshold", value = 0)
  }
  reset_episode <- function() {
    updateNumericInput(session, "T_up", value = 0.20)
    updateNumericInput(session, "T_down", value = 0.1)
    updateNumericInput(session, "delta", value = 0.10)
    updateNumericInput(session, "delta_window", value = 0.2)
    updateNumericInput(session, "min_dur_sec", value = 0.1)
    updateNumericInput(session, "consecutive_missing", value = 150)
    updateNumericInput(session, "cores", value = 0)
  }
  reset_multi_video <- function() {
    retain_first_video()
    updateNumericInput(session, "duration_tolerance", value = 0)
    updateNumericInput(session, "video_columns", value = 2)
    discard_results()
  }
  observeEvent(input$reset_multi_video, {
    if (!state$busy) reset_multi_video()
  })
  observeEvent(input$reset_clip_export, {
    if (!state$busy) reset_clip_export()
  })
  observeEvent(input$reset_matching, {
    if (!state$busy) reset_matching()
  })
  observeEvent(input$reset_synchrony, {
    if (!state$busy) reset_synchrony()
  })
  observeEvent(input$reset_episode, {
    if (!state$busy) reset_episode()
  })
  observeEvent(input$reset_advanced, {
    if (state$busy) {
      return()
    }
    clear_inputs()
    reset_clip_export()
    reset_matching()
    reset_synchrony()
    reset_episode()
    updateSelectInput(session, "clip_order", selected = "time")
    updateNumericInput(session, "duration_tolerance", value = 0)
    updateNumericInput(session, "video_columns", value = 2)
  })
  output$processing_progress <- renderUI({
    if (!state$busy) {
      return(NULL)
    }
    percent <- state$percent
    bar <- if (is.null(percent)) {
      div(
        class = "progress-bar progress-bar-striped progress-bar-animated w-100"
      )
    } else {
      div(
        class = "progress-bar progress-bar-striped",
        style = sprintf("width: %d%%", percent),
        sprintf("%d%%", percent)
      )
    }
    div(
      class = "progress mb-3",
      role = "progressbar",
      `aria-label` = "Clip export progress",
      `aria-valuenow` = if (!is.null(percent)) percent,
      `aria-valuemin` = if (!is.null(percent)) 0,
      `aria-valuemax` = if (!is.null(percent)) 100,
      `aria-valuetext` = if (is.null(percent)) "Preparing clips" else NULL,
      bar
    )
  })
  output$cancel_control <- renderUI({
    if (state$busy) {
      actionButton(
        "cancel_processing",
        "Cancel processing",
        class = "btn-warning"
      )
    }
  })
  output$download_control <- renderUI({
    if (is.null(state$manifest) || !nrow(state$manifest)) {
      tags$button(
        "Download clips ZIP",
        class = "btn btn-secondary",
        disabled = NA
      )
    } else {
      downloadButton("download", "Download clips ZIP")
    }
  })

  finish_processing <- function(result = NULL, error = NULL) {
    if (!is.null(pending_cancel)) {
      removeModal()
    }
    on.exit(
      {
        pending_cancel <<- NULL
        worker <<- NULL
        state$busy <- FALSE
        state$percent <- NULL
        bslib::update_task_button("process", state = "ready")
      },
      add = TRUE
    )
    if (!is.null(error)) {
      state$status <- display_error(error)
      discard_results()
      if (!is.null(run_root)) {
        unlink(run_root, recursive = TRUE, force = TRUE)
        run_root <<- NULL
      }
      return()
    }
    upload_warnings <- isolate(upload_validation_result()$warnings)
    unseen_warnings <- setdiff(upload_warnings, notified_upload_warnings)
    if (length(unseen_warnings)) {
      showNotification(
        paste(unseen_warnings, collapse = " "),
        type = "warning",
        duration = NULL
      )
      notified_upload_warnings <<- union(
        notified_upload_warnings,
        unseen_warnings
      )
    }
    if (!length(result$results) || !nrow(result$results[[1L]]$clip_manifest)) {
      state$status <- "Processing completed; no clips matched the selected options."
      showNotification(
        "No clips were generated. There may be no synchronies in the exports, or the selected options may exclude all matches.",
        type = "warning",
        duration = NULL
      )
      if (!is.null(run_root)) {
        unlink(run_root, recursive = TRUE, force = TRUE)
        run_root <<- NULL
      }
      return()
    }
    manifest <- result$results[[1L]]$clip_manifest
    clip_dir <- result$results[[1L]]$clip_output
    resource <- paste0(
      "clips-",
      session$token,
      "-",
      basename(dirname(clip_dir))
    )
    addResourcePath(resource, clip_dir)
    state$resource <- resource
    http_server <- shiny::getShinyOption("server")
    if (!is.null(http_server)) {
      http_server$setStaticPath(.list = stats::setNames(list(httpuv::staticPath(
        clip_dir, headers = list("Accept-Ranges" = "bytes")
      )), resource))
    }
    state$manifest <- manifest
    state$clip_dir <- clip_dir
    state$index <- 1L
    state$resource <- resource
    state$video_count <- result$video_count %||% 1L
    state$primary <- result$primary %||% 1L
    state$results_root <- run_root
    state$status <- sprintf("Generated %d clips.", nrow(manifest))
    run_root <<- NULL
  }

  observeEvent(input$cancel_processing, {
    if (!state$busy) {
      return()
    }
    pending_cancel <<- run_id
    showModal(modalDialog(
      title = "Cancel processing?",
      "The current run and its partial clips will be discarded.",
      footer = tagList(
        actionButton("keep_processing", "Keep processing"),
        actionButton(
          "confirm_cancel",
          "Cancel processing",
          class = "btn-danger"
        )
      ),
      easyClose = FALSE
    ))
  })

  observeEvent(input$keep_processing, {
    pending_cancel <<- NULL
    removeModal()
  })

  observeEvent(input$confirm_cancel, {
    removeModal()
    if (!state$busy || !identical(pending_cancel, run_id)) {
      return()
    }
    pending_cancel <<- NULL
    run_id <<- run_id + 1L
    if (!is.null(worker) && worker$is_alive()) {
      worker$kill_tree()
    }
    worker <<- NULL
    if (!is.null(run_root)) {
      unlink(run_root, recursive = TRUE, force = TRUE)
      run_root <<- NULL
    }
    state$busy <- FALSE
    state$percent <- NULL
    state$status <- "Processing cancelled."
    bslib::update_task_button("process", state = "ready")
  })

  poll_worker <- function(expected_run_id) {
    if (is.null(worker) || !identical(expected_run_id, run_id)) {
      return()
    }
    output_text <- paste0(worker$read_output(), worker$read_error())
    if (diagnostics && nzchar(output_text)) {
      message(output_text)
    }
    percent <- if (!diagnostics) clip_export_percent(output_text) else NULL
    if (!is.null(percent)) {
      state$percent <- percent
      state$status <- sprintf("Exporting clips… %d%%", percent)
    }
    if (worker$is_alive()) {
      later::later(
        function() {
          shiny::withReactiveDomain(session, poll_worker(expected_run_id))
        },
        0.2
      )
    } else {
      remaining_output <- paste0(worker$read_output(), worker$read_error())
      if (diagnostics && nzchar(remaining_output)) {
        message(remaining_output)
      }
      last_percent <- if (!diagnostics) {
        clip_export_percent(remaining_output)
      } else {
        NULL
      }
      if (!is.null(last_percent)) {
        state$percent <- last_percent
      }
      result <- tryCatch(worker$get_result(), error = identity)
      if (inherits(result, "error")) {
        finish_processing(error = result)
      } else {
        tryCatch(
          finish_processing(result = result),
          error = function(error) finish_processing(error = error)
        )
      }
    }
  }

  observeEvent(input$process, {
    if (state$busy || !inputs_ready()) {
      return()
    }
    upload_warnings <- upload_validation_result()$warnings
    new_warnings <- setdiff(upload_warnings, notified_upload_warnings)
    if (length(new_warnings)) {
      showNotification(
        paste(new_warnings, collapse = " "),
        type = "warning",
        duration = NULL
      )
      notified_upload_warnings <<- union(notified_upload_warnings, new_warnings)
    }
    if (length(upload_warnings) && !metadata_confirmed()) {
      showModal(modalDialog(
        title = "Metadata mismatch",
        tagList(
          p("The selected files contain metadata mismatches:"),
          tags$ul(lapply(upload_warnings, tags$li)),
          p("Continue processing anyway? Results may be inaccurate.")
        ),
        footer = tagList(
          actionButton("cancel_metadata", "Go back"),
          actionButton(
            "confirm_metadata",
            "Continue anyway",
            class = "btn-warning"
          )
        ),
        easyClose = FALSE
      ))
      return()
    }
    metadata_confirmed(FALSE)
    run_id <<- run_id + 1L
    pending_cancel <<- NULL
    expected_run_id <- run_id
    state$busy <- TRUE
    state$percent <- NULL
    bslib::update_task_button("process", state = "busy")
    discard_results()
    state$status <- "Validating inputs…"
    tryCatch(
      {
        if (inherits(media_tools, "error")) {
          stop(conditionMessage(media_tools))
        }
        run_root <<- tempfile("run-", tmpdir = workspace)
        dir.create(run_root)
        uploads <- stage_uploads(
          videos(),
          input$first,
          input$second,
          file.path(run_root, "inputs")
        )
        options <- pipeline_options(input, subjects())
        diagnostics <<- isTRUE(options$verbose)
        state$status <- "Processing video…"
        arguments <- list(
          videos = uploads[seq_along(uploaded_video_ids())],
          exports = tail(uploads, 2L),
          output_dir = file.path(run_root, "clips"),
          primary = primary_video(),
          tolerance_ms = input$duration_tolerance %||% 0,
          options = options,
          media_tools = media_tools
        )
        worker <<- callr::r_bg(
          function(arguments, root) {
            source(file.path(root, "R", "app_helpers.R"), local = TRUE)
            source(file.path(root, "R", "multi_video.R"), local = TRUE)
            do.call(run_shared_video_pipeline, arguments)
          },
          args = list(arguments, app_root),
          stdout = "|",
          stderr = "|",
          supervise = TRUE
        )
        later::later(
          function() {
            shiny::withReactiveDomain(session, poll_worker(expected_run_id))
          },
          0.2
        )
      },
      error = function(error) {
        finish_processing(error = error)
      }
    )
  })

  observeEvent(input$confirm_metadata, {
    removeModal()
    metadata_confirmed(TRUE)
    session$sendCustomMessage("confirm-metadata-process", input$process)
  })
  observeEvent(input$cancel_metadata, {
    removeModal()
    metadata_confirmed(FALSE)
  })

  clips <- reactive(ordered_clips(state$manifest, input$clip_order))
  observeEvent(input$clip_order, {
    state$index <- 1L
  })
  observeEvent(input$previous, {
    state$index <- max(1L, state$index - 1L)
  })
  observeEvent(input$next_clip, {
    state$index <- min(
      if (is.null(clips())) 1L else nrow(clips()),
      state$index + 1L
    )
  })
  output$position <- renderText({
    if (is.null(clips()) || !nrow(clips())) {
      return("No clips")
    }
    sprintf("Clip %d of %d", state$index, nrow(clips()))
  })
  output$player <- renderUI({
    manifest <- clips()
    if (is.null(manifest) || !nrow(manifest) || is.null(state$resource)) {
      return(p("Clips will appear here after processing."))
    }
    clip <- manifest[state$index, , drop = FALSE]
    filename <- as.character(clip$clip_filename[[1L]])
    if (
      !identical(basename(filename), filename) ||
        !file.exists(file.path(state$clip_dir, filename))
    ) {
      return(p("Clip file is unavailable."))
    }
    tagList(
      div(class = "video-grid", `data-primary` = state$primary - 1L,
        `data-duration` = clip$duration_seconds[[1L]],
        lapply(seq_len(state$video_count), function(camera) {
          path <- if (state$video_count == 1L) filename else paste0("views/video_", camera, "/", filename)
          tags$video(
              controls = if (camera == state$primary) NA else NULL,
              muted = if (camera != state$primary) NA else NULL,
              preload = "metadata", playsinline = NA,
              tags$source(src = paste0(state$resource, "/", utils::URLencode(path, reserved = FALSE)), type = "video/mp4")
          )
        })
      ),
      p(class = "playback-error", role = "alert"),
      p(sprintf(
        "Rank %s · Time order %s · %s",
        clip$selection_rank[[1L]],
        clip$clip_order[[1L]],
        filename
      ))
    )
  })
  output$download <- downloadHandler(
    filename = function() "shared_clips.zip",
    content = function(file) {
      tryCatch(create_clips_zip(state$manifest, state$clip_dir, file), error = function(error) {
        showNotification(display_error(error), type = "error", duration = NULL)
        stop(error)
      })
    }
  )
}

shinyApp(ui, server)
