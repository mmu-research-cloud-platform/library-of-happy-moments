# FFmpeg and FFprobe binary provenance

This is a historical record of the 2026-09-28 downloads, **not** the provenance of a newly built Windows ZIP. The Windows bundler downloads the current upstream asset and embeds its verified release metadata and shipped-file hashes in `MEDIA-PROVENANCE.json` and `SOURCE-NOTICE.md` inside that ZIP. Consult those files for that particular build; the `latest` links and hashes below can become stale.

Downloaded 2026-09-28. Each target contains **only** `ffmpeg` and `ffprobe` in the directory expected by `locate_media_tools()`; original archives are kept locally in `bin/.downloads/` (git-ignored). These are third-party builds, **not** part of this project's MIT license. `libx264` requires GPL-enabled FFmpeg; distributing this software with the bundled binaries requires appropriate GPL source/notice compliance and a review of relevant codec patent obligations. See https://ffmpeg.org/legal.html. Do not release the desktop application without that review. `ffbinaries` repackages upstream evermeet.cx's macOS x64 binaries. The source/version link for the macOS arm64 binaries is from the release notes, not an independent source audit.

| Target | Archive URL (versioned filename; BtbN `latest` tag is mutable) | Archive SHA-256 | Hash basis |
|---|---|---|---|
| Windows x64 | https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n9.0-latest-win64-gpl-9.0.zip | `b745ed683204c8e154d627bf75f2e530b7b2eec51d14fabdc8771912423ba67e` | GitHub release asset digest, verified locally |
| Linux x64 | https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-n9.0-latest-linux64-gpl-9.0.tar.xz | `8e5f27f70c7926662b89e5a496adadab59d09899430ee2a02a262fec39c72534` | GitHub release asset digest, verified locally |
| macOS x64 FFmpeg | https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffmpeg-6.1-macos-64.zip | `ffcd56ce5ef50c4d36d675b0ee80674f5a0869f94746460ff5d058a33cbd3128` | Locally calculated; publisher has no SHA-256 digest |
| macOS x64 FFprobe | https://github.com/ffbinaries/ffbinaries-prebuilt/releases/download/v6.1/ffprobe-6.1-macos-64.zip | `878ab8787ca6c48a11cb668c01d544be4c1bf655637d719cdf3b3179841545f2` | Locally calculated; publisher has no SHA-256 digest |
| macOS arm64 FFmpeg | https://github.com/charlienovember/videobot-ffmpeg/releases/download/ffmpeg-n8.1.2/ffmpeg-n8.1.2-macos-arm64.zip | `7c3f9560d1d018746a3fbca4f89d597ad4d45739abc3efc45f6360c9add3e614` | GitHub release asset digest, verified locally |
| macOS arm64 FFprobe | https://github.com/charlienovember/videobot-ffmpeg/releases/download/ffmpeg-n8.1.2/ffprobe-n8.1.2-macos-arm64.zip | `d86c980604ab0d8c40b3c17c9c3fcb388fb341ea4bd470ab28f9d96c5f3fb812` | GitHub release asset digest, verified locally |

The Windows and Linux archives also include `LICENSE.txt` (GPLv3), copied alongside their binaries. The macOS sources did not include matching license files in the extracted archives; follow upstream notices and verify release obligations before distribution.

Extracted executable SHA-256 values:

| Executable | SHA-256 |
|---|---|
| `bin/windows-x64/ffmpeg.exe` | `f88e9ff0c15e44a38b3ae6d6542cb34b044f0faecb71fdedfb5d179cdea35fba` |
| `bin/windows-x64/ffprobe.exe` | `69ef9db5f509895f0af519da34586e55c266b8ef20d10e7f07575f9472254540` |
| `bin/linux-x64/ffmpeg` | `d6839ca391abb4e2da3b524e3b730bacebf43877e0b0e420d928ab4014a68961` |
| `bin/linux-x64/ffprobe` | `87e908ed4cfcf64259ffc316f161eed09d149d18d4e8aef9e24e0211edf0bc2a` |
| `bin/macos-x64/ffmpeg` | `ca8945e5eef946a246d29c943b21f10db345a2ef050dd7ea1c77f877277dc2fa` |
| `bin/macos-x64/ffprobe` | `82f8b544e9924aed20f691f4b1b1ad0ba7e31d2a2e856ac29a1b6a31537e7f1f` |
| `bin/macos-arm64/ffmpeg` | `102b0df2756be7b05d7fdb3f6664ad6f370fc3ad99f4747dfe47692e9a518484` |
| `bin/macos-arm64/ffprobe` | `eb85ba89aa58fcb29e8fbb6ed448bd9802c93aae7a1a833b728701335c718f6a` |

Windows bundle reports `n9.0.2-12-gc867e13549-20260927`. Local checks: `ffmpeg -version`, `ffprobe -version`, `libx264` encoder presence, sample H.264 encode, and FFprobe duration all passed. Linux/macOS executables have matching ELF/Mach-O architectures and execute bits, but must be **run on their respective target machines** before release. Linux static BtbN build is linked to the Linux loader and has a minimum OS/glibc requirement; check upstream compatibility. macOS may need Apple signing/notarization and may be blocked by quarantine on user machines. Re-check source availability and license notices for every upstream release before distribution.

Upstream source/build information: https://github.com/BtbN/FFmpeg-Builds (GPL builds include libx264); https://github.com/ffbinaries/ffbinaries-prebuilt/releases/tag/v6.1 (links to upstream evermeet.cx); https://github.com/charlienovember/videobot-ffmpeg/releases/tag/ffmpeg-n8.1.2 (states GPLv3 and `libx264`).
