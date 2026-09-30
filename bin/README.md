# FFmpeg runtime bundles

Install **both** `ffmpeg` and `ffprobe` for every supported platform in these project-root directories:

| Platform | Executables |
|---|---|
| Windows x64 | `bin/windows-x64/ffmpeg.exe`, `bin/windows-x64/ffprobe.exe` |
| macOS x64 | `bin/macos-x64/ffmpeg`, `bin/macos-x64/ffprobe` |
| macOS arm64 | `bin/macos-arm64/ffmpeg`, `bin/macos-arm64/ffprobe` |
| Linux x64 | `bin/linux-x64/ffmpeg`, `bin/linux-x64/ffprobe` |

The pipeline requires a build with `libx264` and AAC support; verify both with `ffmpeg -encoders` and test an actual clip. FFprobe is resolved from PATH and is set to the sibling bundled binary at startup. Make macOS/Linux binaries executable (`chmod +x`). Unsupported or missing bundles fail explicitly; system FFmpeg is not silently used.

The executables are **not stored in Git**. On a fresh GitHub checkout, obtain a trusted FFmpeg build for your OS/CPU with both `ffmpeg` and `ffprobe`, verify its publisher-provided checksum or signature, and place the pair in the directory in the table. Choose a build supporting H.264 (`libx264`) and AAC and retain its license, copyright notices, version, download URL and hashes. You may bring your own build; no system `PATH` fallback is used. For Windows x64, `npm run download:media:win` is an optional shortcut that fetches the current BtbN GPL build, checks its upstream SHA-256 and installs the pair and `LICENSE.txt`. For other platforms, use [SOURCES.md](SOURCES.md) only as a historical reference: verify the current archive and executable hashes against upstream release metadata (the `latest` asset can change), and extract both files into the table's directory. Keep any accompanying license/notice files with the tools. For macOS/Linux, make both executable (`chmod +x`). Only install platforms you intend to use; startup reports missing tools for the current platform. Windows has been smoke-tested locally; Linux/macOS require testing on their own OS/CPU. Redistributing downloaded binaries has obligations distinct from running this source checkout: review GPL source/notice and codec/patent requirements before sharing any bundle. See https://ffmpeg.org/legal.html.
