# library-of-happy-moments
A shiny app proof of concept for building the library of happy moments. Acts as an interface for the facereaderconverter library.

## Recommended: clone and run from R

Run locally on a trusted machine rather than exposing this unauthenticated app as a public server. Install Git and R 4.1 or newer, then clone the repository:

```sh
git clone https://github.com/mmu-research-cloud-platform/library-of-happy-moments.git
cd library-of-happy-moments
```

Open R or RStudio with the cloned repository as the working directory. Install the app dependencies and the converter (tested with version 0.4). Installing the converter from source on Windows also requires the matching Rtools:

```r
install.packages(c("shiny", "bslib", "zip", "callr", "later", "remotes"))
remotes::install_github("mmu-research-cloud-platform/facereaderconverter",
                      upgrade = "never")
```

Install **both FFmpeg and FFprobe** with H.264/libx264 and AAC support in the platform-specific project `bin` directory, following [bin/README.md](bin/README.md). They are not stored in Git and are not installed by the R commands above. Then start the app from R:

```r
shiny::runApp(".")
```

See [SETUP.md](SETUP.md) for detailed setup, the optional Electron desktop shell, and the gated Windows release process.

## Multiple camera views

Start with one video input. Select **Add video** below it in the main sidebar for each additional camera. When multiple inputs exist, each has a **Remove video** button, including the first; removing one preserves the other uploads and renumbers their labels. The last input cannot be removed. Open **Advanced options > Multi-video** to adjust audio, duration tolerance and playback columns. **Reset multi-video** retains the first remaining video and FaceReader exports, removes other video inputs and restores those defaults. Upload exactly two detailed FaceReader exports, one per participant, shared by every view. Videos must already start at the same point; the app does not align recordings automatically.

**Audio source** lets you choose which video's audio is used for playback and downloads; it defaults to the first video added. Filename metadata in the FaceReader exports is checked against that video, with confirmation required for mismatches. Other videos are muted; a source without audio produces silent clips.

Empty video inputs are ignored. Processing requires at least one uploaded video and both FaceReader exports, with the usual format, duration and analysis-option checks still applying. Only uploaded videos appear in **Audio source**.

Durations of all videos **and both FaceReader exports** must match exactly by default. Set **Duration tolerance (milliseconds)** to allow a difference between the longest and shortest file; a larger difference blocks processing and lists the file durations. A FaceReader export's duration is its final `Video Time` plus one frame at the export's frame rate. Missing or invalid timestamps are blocking errors. Accepted differences use the shortest video timeline without padding or stretching.

Generated camera clips share play/pause, seeking and playback speed. **Playback columns** defaults to two and can be changed interactively; narrow screens use one column. The clip ZIP always contains one fixed two-column composite per moment and `manifest.csv`, preserving aspect ratios and leaving an odd final cell blank. Single-video clips remain full-frame. Changing uploads, audio source, or duration tolerance discards previous results and requires regeneration.

There is no fixed video-count cap, but the existing per-upload limit (1 GiB) and available memory, disk and processing resources still apply. Remove additional inputs before processing if needed.
