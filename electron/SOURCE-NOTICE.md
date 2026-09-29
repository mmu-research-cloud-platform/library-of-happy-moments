# Source and third-party notices (Windows x64)

This application includes software from multiple authors. The app's own MIT license is at `resources/bundle/app/LICENSE`; it does **not** apply to the third-party components below.

## FFmpeg and FFprobe

`resources/bundle/app/bin/windows-x64/ffmpeg.exe` and `ffprobe.exe` are third-party GPL-enabled builds from BtbN/FFmpeg-Builds. The copy of the GPLv3 text shipped with that build is at `resources/bundle/app/bin/windows-x64/LICENSE.txt`. FFmpeg and FFprobe source and build information: https://github.com/BtbN/FFmpeg-Builds and https://ffmpeg.org/download.html. The upstream binary archive, SHA-256 values, build version and verification notes are recorded in `resources/bundle/app/bin/SOURCES.md`. The FFmpeg build includes `libx264`, which requires particular attention to GPL source and notice obligations. Those links and this notice **do not establish** that the corresponding source and all required notices have been supplied. Confirm the exact corresponding source and distribution obligations before sharing the archive; review codec/patent requirements separately. See https://ffmpeg.org/legal.html.

## R, Electron, and R packages

The bundle includes R and its base/recommended packages under `resources/bundle/runtime`, installed R packages under `resources/bundle/library`, and Electron/Chromium in the desktop shell. These have separate licenses and may have their own attribution or source-availability obligations. Look for bundled license files, including Electron/Chromium's `LICENSE.electron.txt` and `LICENSES.chromium.html`. Review and provide any missing third-party notices and corresponding source as required before redistribution. A successful build or local smoke test does not imply distribution clearance.
