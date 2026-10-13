library(shiny)
library(bslib)
source("R/app_helpers.R", local = TRUE)

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
      $('#clear_inputs, [id^=reset_]').prop('disabled', status.busy);
    });
    Shiny.addCustomMessageHandler('clear-upload-inputs', function(ids) {
      if (ids !== 'subject_map') $('#process').prop('disabled', true);
      (ids === 'subject_map' ? ['subject_map'] :
        ['video', 'first', 'second', 'subject_map']).forEach(function(id) {
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
  ))),
  sidebar = sidebar(
    card(
      card_header("Video"),
      fileInput("video", "Select video", accept = paste0(".", video_extensions))
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
            textInput(
              "optimised_subject",
              "Optimised subject (both or regex)",
              "both"
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
          tags$li("Upload one video (MP4, MOV, MKV, or AVI)."),
          tags$li(
            "Upload two distinct, detailed FaceReader exports (TXT or XLSX), ",
            "one for each participant. Their Filename metadata must match the video, ",
            "and both exports must use the same frame rate."
          ),
          tags$li(
            "Optionally adjust Advanced options in the sidebar. If using a subject ",
            "mapping CSV, include export_filename and subject columns."
          ),
          tags$li(
            "When all inputs pass validation, select Process video. ",
            "Review clips on the Clips tab, then download the clips ZIP."
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
    percent = NULL
  )
  worker <- NULL
  run_root <- NULL
  run_id <- 0L
  pending_cancel <- NULL
  metadata_confirmed <- reactiveVal(FALSE)
  notified_upload_warnings <- character()
  diagnostics <- FALSE
  observeEvent(
    list(input$video, input$first, input$second),
    {
      metadata_confirmed(FALSE)
      notified_upload_warnings <<- character()
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
    input$video,
    input$first,
    input$second,
    ffprobe
  ))
  upload_error <- reactive(upload_validation_result()$error)
  ready <- reactive(is.null(upload_error()))
  option_error <- reactive(tryCatch(
    {
      if (!ready()) {
        return(NULL)
      }
      pipeline_options(input)
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
      has_upload <- !is.null(input$video) ||
        !is.null(input$first) ||
        !is.null(input$second)
      if (!is.null(option_error())) {
        state$status <- conditionMessage(option_error())
      } else if (!is.null(error) && has_upload) {
        state$status <- conditionMessage(error)
      } else if (inherits(media_tools, "error") && !has_upload) {
        state$status <- conditionMessage(media_tools)
      } else if (is.null(error) && has_upload) {
        state$status <- "Inputs validated. Ready to process."
      }
    }
  })

  clear_inputs <- function() {
    session$sendCustomMessage("clear-upload-inputs", TRUE)
    state$manifest <- NULL
    state$clip_dir <- NULL
    state$index <- 1L
    if (!is.null(state$resource)) {
      removeResourcePath(state$resource)
      state$resource <- NULL
    }
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
    updateTextInput(session, "optimised_subject", value = "both")
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
      state$status <- conditionMessage(error)
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
    state$manifest <- manifest
    state$clip_dir <- clip_dir
    state$index <- 1L
    state$resource <- resource
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
    output_text <- worker$read_output()
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
      remaining_output <- worker$read_output()
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
        finish_processing(result = result)
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
    state$manifest <- NULL
    state$clip_dir <- NULL
    if (!is.null(state$resource)) {
      removeResourcePath(state$resource)
      state$resource <- NULL
    }
    state$status <- "Validating inputs…"
    tryCatch(
      {
        if (inherits(media_tools, "error")) {
          stop(conditionMessage(media_tools))
        }
        run_root <<- tempfile("run-", tmpdir = workspace)
        dir.create(run_root)
        uploads <- stage_uploads(
          input$video,
          input$first,
          input$second,
          file.path(run_root, "inputs")
        )
        options <- pipeline_options(input)
        diagnostics <<- isTRUE(options$verbose)
        state$status <- "Processing video…"
        arguments <- c(
          list(
            inpath = dirname(uploads[[1L]]),
            video_path = uploads[[1L]],
            output_dir = file.path(run_root, "clips"),
            output = "folder",
            overwrite = FALSE,
            ffmpeg = media_tools[["ffmpeg"]]
          ),
          options
        )
        worker <<- callr::r_bg(
          function(arguments, ffprobe_directory) {
            Sys.setenv(
              PATH = paste(
                ffprobe_directory,
                Sys.getenv("PATH"),
                sep = .Platform$path.sep
              )
            )
            do.call(facereaderconverter::synchrony_moments_pipeline, arguments)
          },
          args = list(arguments, dirname(media_tools[["ffprobe"]])),
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
      tags$video(
        controls = NA,
        preload = "metadata",
        width = "100%",
        tags$source(
          src = paste0(
            state$resource,
            "/",
            utils::URLencode(filename, reserved = TRUE)
          ),
          type = "video/mp4"
        )
      ),
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
      create_clips_zip(state$manifest, state$clip_dir, file)
    }
  )
}

shinyApp(ui, server)
