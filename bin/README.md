# FFmpeg runtime bundles

Install **both** `ffmpeg` and `ffprobe` for every supported platform in these project-root directories:

| Platform | Executables |
|---|---|
| Windows x64 | `bin/windows-x64/ffmpeg.exe`, `bin/windows-x64/ffprobe.exe` |
| macOS x64 | `bin/macos-x64/ffmpeg`, `bin/macos-x64/ffprobe` |
| macOS arm64 | `bin/macos-arm64/ffmpeg`, `bin/macos-arm64/ffprobe` |
| Linux x64 | `bin/linux-x64/ffmpeg`, `bin/linux-x64/ffprobe` |

The pipeline requires a build with `libx264` and AAC support; verify both with `ffmpeg -encoders` and test an actual clip. FFprobe is resolved from PATH and is set to the sibling bundled binary at startup. Make macOS/Linux binaries executable (`chmod +x`). Unsupported or missing bundles fail explicitly; system FFmpeg is not silently used.

The executables are **not stored in Git**. Download the matching archives listed in [SOURCES.md](SOURCES.md), verify each archive's SHA-256, and extract `ffmpeg` and `ffprobe` into the platform directory above. Verify the extracted executables against the hashes in SOURCES.md. The BtbN Windows and Linux archives also contain `LICENSE.txt`; keep it alongside the executables. For macOS/Linux, make both files executable (`chmod +x`). Install only the platforms you intend to run or package; startup fails if the current platform's pair is missing. Windows has been smoke-tested locally; Linux/macOS still require testing on their own OS/CPU. **Redistribution clearance is still pending**: `libx264` requires GPL-enabled builds and source/notice compliance; codec/patent obligations may also apply. Review https://ffmpeg.org/legal.html before release. The Electron scaffold is not a distributable build.
