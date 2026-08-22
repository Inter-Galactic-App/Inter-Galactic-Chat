# FFmpeg Windows Story Export Evidence

> **HISTORICAL AS OF 2026-08-15. Neither binary is staged any more, and this
> directory must not be deleted.** `ffprobe.exe` was removed on 2026-08-07 and
> `ffmpeg.exe` on 2026-08-15, together with the whole
> `intergalactic/windows/third_party/` tree and the story video trim feature.
> This evidence is retained because releases `0.7.4+985` through `0.8.0+993`
> shipped the pair, the digests recorded here are what the **live** source offer
> answers for, and deleting them would orphan that offer. **Read the rest of
> this file in the past tense.** Tensed by S&C, which also corrected
> `manifest.json`'s `still_staged` field for `ffmpeg.exe` — it had read `true`
> for eight days after the deletion, while the sibling `ffprobe.exe` entry in
> the same file correctly read `false`.

This evidence covers the Windows desktop story-video export tool pair, formerly
staged under:

```text
intergalactic/windows/third_party/ffmpeg/bin/ffmpeg.exe
intergalactic/windows/third_party/ffmpeg/bin/ffprobe.exe
```

The staged binaries **were** release inputs only. They were ignored by git and
copied by `intergalactic/windows/CMakeLists.txt` into `tools/ffmpeg/` beside
`InterGalactic.exe` during Windows packaging. **That install rule is gone.** In
its place is a negative guard: if anything is left in
`third_party/ffmpeg/bin/`, CMake raises `FATAL_ERROR` on any build type. So
re-staging these binaries to match this document is a build failure, not a
restoration.

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
- `--enable-version3` is present, so record FFmpeg itself as
  LGPL-3.0-or-later, with notice evidence from the selected archive's LGPLv3
  text.

**Corrected 2026-08-09.** The line above told the reader to "record this as an
LGPL-only build". The four checks above it are correct and were correctly run,
but they read the **configure line**, which names direct externals and has no
vocabulary for their dependencies. Two GPL components reach this binary beneath
it: **FFTW** (GPL-2.0-or-later, via `chromaprint`'s FFT backend) and the
GPL-2.0-**only** part of **`libzvbi`**. Do not record the binary as LGPL-only;
`docs/policies/SOURCE_OFFER.md` is authoritative on its licence. This is the
method limit that produced two wrong public statements, and it is named here so
the next person running these checks knows what they do not cover.

Evidence files:

- `manifest.json`: archive, staged binary, source, and validation metadata.
- `ffmpeg-version.txt`: captured `ffmpeg.exe -version` output.
- `ffprobe-version.txt`: captured `ffprobe.exe -version` output.
- `LICENSE-LGPL-3.0.txt`: license file from the selected binary archive.
