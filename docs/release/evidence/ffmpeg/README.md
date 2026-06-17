# FFmpeg Windows Story Export Evidence

This evidence covers the Windows desktop story-video export tool pair staged
under:

```text
intergalactic/windows/third_party/ffmpeg/bin/ffmpeg.exe
intergalactic/windows/third_party/ffmpeg/bin/ffprobe.exe
```

The staged binaries are release inputs only. They are ignored by git and copied
by `intergalactic/windows/CMakeLists.txt` into `tools/ffmpeg/` beside
`InterGalactic.exe` during Windows packaging.

Selected binary provider:

- Provider: BtbN FFmpeg Builds
- Release: `autobuild-2026-06-13-13-31`
- Asset: `ffmpeg-n8.1.1-13-g83e8541aa6-win64-lgpl-8.1.zip`
- Variant: `win64-lgpl`, static executable pair

Local acceptance checks:

- `ffmpeg.exe -hide_banner -version`
- `ffprobe.exe -hide_banner -version`
- Confirmed no `--enable-gpl`.
- Confirmed no `--enable-nonfree`.
- Confirmed GPL-only libraries `libx264`, `libx265`, `libxavs2`, and
  `libxvid` are disabled in the reported configuration.
- `--enable-version3` is present, so record this as an LGPL-only build with
  LGPL-3.0-or-later notice evidence from the selected archive's LGPLv3 text.

Evidence files:

- `manifest.json`: archive, staged binary, source, and validation metadata.
- `ffmpeg-version.txt`: captured `ffmpeg.exe -version` output.
- `ffprobe-version.txt`: captured `ffprobe.exe -version` output.
- `LICENSE-LGPL-3.0.txt`: license file from the selected binary archive.
