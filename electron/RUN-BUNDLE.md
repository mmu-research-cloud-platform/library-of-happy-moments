# Run Library of Happy Moments (Windows x64)

1. Extract the **entire** ZIP to a writable directory. Keep `Library of Happy Moments.exe`, `resources/`, and all other files in `win-unpacked/` together; the EXE is not a standalone installer. No separate R or Node installation is needed.
2. Double-click `Library of Happy Moments.exe` in the extracted `win-unpacked` folder. This build is unsigned; Windows may show a publisher warning. Only run it if you trust the source of the archive.
3. Select one video (`mp4`, `mov`, `mkv`, `avi`) and two detailed FaceReader exports (`txt`, `xlsx`) whose Filename metadata matches the video. Choose **Process video**; then review and download the resulting clips.
4. Close the window to stop the local server. The app runs only on the local machine (`127.0.0.1`); process sensitive recordings only on a trusted computer. Uploads and clips use session temporary storage, not a cloud service.

If the window reports a startup error, ensure the entire archive was extracted and that security software did not quarantine files. The first launch can take some time. For provenance, third-party licensing, and outstanding redistribution checks, read `SOURCE-NOTICE.md` in this folder. **Do not redistribute until those checks are complete.**
