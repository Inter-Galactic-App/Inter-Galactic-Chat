# Windows FFmpeg Tool Staging

Windows story-video trim export expects an LGPL-only FFmpeg tool pair here:

```text
bin/ffmpeg.exe
bin/ffprobe.exe
```

Do not check the binaries into source. Release Pipeline should stage both files
from the approved LGPL-only FFmpeg build before the Windows Release CMake
install/package step. The app copies the pair into `tools/ffmpeg/` beside
`InterGalactic.exe`; runtime export prefers that bundled pair before developer
PATH fallback.

Current approved staging evidence:

- BtbN FFmpeg Builds release: `autobuild-2026-06-13-13-31`
- Asset: `ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip`
- FFmpeg source revision: `83e8541aa601935a610b1b8958d56e8d0331318b`
- Local evidence: `docs/release/evidence/ffmpeg/`

The release notice bundle must record the exact FFmpeg source revision or
release archive, build configuration, local patches if any, and source link. If
either executable is replaced, regenerate `docs/release/evidence/ffmpeg/` and
recheck that the reported configuration has no `--enable-gpl` or
`--enable-nonfree` flags.
