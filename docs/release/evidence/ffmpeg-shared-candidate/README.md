# FFmpeg `win64-lgpl-shared` candidate — provenance capture

Captured by **RELEASE PIPELINE**, 2026-08-09. Engineering provenance and release-packaging
assessment. **Not legal advice, and it closes no compliance gate.**

> ## SUPERSEDED 2026-08-15 — DO NOT EXECUTE THE PACKAGING PLAN IN THIS FILE
>
> Marked by S&C. **This candidate is moot and its instructions are now
> build-breaking.** On 2026-08-15 (app PR #174) `ffmpeg.exe` was deleted
> outright rather than swapped for a shared variant, story video trim was
> removed with it, and the whole `intergalactic/windows/third_party/` tree is
> gone. `intergalactic/windows/CMakeLists.txt` now raises `FATAL_ERROR` if
> **anything** is staged into `third_party/ffmpeg/bin/`, so the install rule
> this document says "must carry the DLLs" cannot be written, and staging the
> candidate to try it fails the build.
>
> Three specific statements below are false as of that date and are left in
> place only as the record of what was assessed on 2026-08-09:
> `third_party/ffmpeg/bin/` is **untouched** (the directory does not exist);
> the shipped binary **is still** the static `win64-lgpl` build (nothing FFmpeg
> ships on Windows now); and the runtime check `_toolRuns` in
> `intergalactic/lib/ui/organisms/home_screen/story_video_trim_exporter_io.dart`
> (that file is deleted).
>
> **The provenance and measurement content is still good and is why this is
> kept** — in particular the finding that BtbN's `lgpl-shared` leaves the 18
> components statically inside FFmpeg's own DLLs (1,015 `fftw_` matches in the
> candidate's `avformat-62.dll`), so the swap was never a compliance closer.
> That conclusion outlived the candidate and should not be relearned.

## Nothing was swapped

`intergalactic/windows/third_party/ffmpeg/bin/` is **untouched**. The shipped binary is still the
static `win64-lgpl` build described by `docs/release/evidence/ffmpeg/`. This directory describes a
*candidate* that has been identified and hashed, nothing more.

The swap is gated on a smoke gate that does not exist yet. The current runtime check
(`_toolRuns` in `intergalactic/lib/ui/organisms/home_screen/story_video_trim_exporter_io.dart`)
accepts any executable that exits 0 on `-version` — which a shared `ffmpeg.exe` with its DLLs
missing would *not* do, but which also proves nothing about whether an export succeeds. Until a
real gate exists, a swap is unverifiable.

## Why this capture exists

The staged binary came from BtbN release `autobuild-2026-06-13-13-31`. BtbN prunes its autobuild
releases, and that one is gone: `release_url` and `asset_url` both 404. Losing the tag lost the
build definition, and losing the build definition lost **the pinned upstream component versions** —
which is what currently blocks the corresponding-source bundles from filling `third-party/<dep>/`.

A current, unpruned release restores all three at once. That is the deliverable: provenance
captured while it still exists.

Per `docs/DECISIONS.md` → *"Record A Third-Party Binary's Builder Commit SHA At Staging Time"*
(2026-08-07), the **builder commit SHA** below was read from the tag object itself
(`GET /git/ref/tags/...` → `object.sha`). Last time it had to be inferred from commit timestamps
because the tag was already deleted. This one is proof.

## The record

| | |
| --- | --- |
| Release | `autobuild-2026-08-09-13-03` (**never** `latest`) |
| Asset | `ffmpeg-n8.1.2-34-g9b6c8969e0-win64-lgpl-shared-8.1.zip` |
| Asset SHA-256 | `2936E5449886641B4279CA3FC554B678C8E9A2D20DD0C0A34FE7208B254A0905` |
| Asset size | 70,708,855 bytes |
| Builder commit | `2437e7b868da3c11872367b15f3c613b87c24819` |
| FFmpeg revision | `9b6c8969e05b4f0b29f0f85cd501be6b3e582e6b` (`release/8.1`) |
| Version string | `n8.1.2-34-g9b6c8969e0-20260809` |
| Components enabled | 57, all with a recorded upstream pin |

The asset digest matches the digest GitHub records on the release asset, so the download was
verified against upstream rather than only against itself.

| File | What it holds |
| --- | --- |
| `provenance.json` | Structured record: identifiers, every digest, source revision, boundaries observed. |
| `BUILD-CONFIGURATION.txt` | The build's own reported configure line, plus the `--enable-gpl` / `--enable-nonfree` assertions. |
| `component-pins.json` | **The thing that was missing.** 57 components → upstream repo + pinned commit/tag/rev, plus 9 transitive build dependencies. |
| `component-pins-SHIPPED-BUILD.json` | The same, for the build **currently shipped** — all 58, recovered from builder history after the tag was pruned. |
| `component-set-diff.md` | Diff against the current 58-component inventory, and one finding that changes what the inventory says. |

### The shipped build's pins are recoverable too — read this before using the candidate's

The bundle work was blocked on the shipped build's component versions being
"unrecoverable" because the release tag was pruned. **They were not.** The tag was one route
to the build definition; the commit history is another, and commit `a9410e4be2b3` is still
there. All **58** pins for the shipped `win64-lgpl` build are in
`component-pins-SHIPPED-BUILD.json`.

Use that file, not `component-pins.json`, for anything describing the binary users already
have. Its confidence is lower and the file says so: `a9410e4b` is the last commit before the
build with zero commits in between, which is tight inference, not the live tag object the
candidate's SHA came from.

**Do not reuse one build's pins for the other.** Between the two builds, **41 of the 57 shared
components moved**, plus `fftw3` and the mingw toolchain. Component pins are per-build data,
not a property of "BtbN builds".

### Read `component-set-diff.md` before treating this as routine

Two results there matter more than the identifiers:

1. The component set differs by exactly one: **`whisper` is gone** (58 → 57). Nothing was added.
2. **FFTW (GPL-2.0-or-later) is statically present in the shipped binary**, reaching it through
   chromaprint's FFT backend — a *builder* choice the FFmpeg configure line never names. Measured
   at 1015 `fftw_`/`fftwf_` symbol matches in both the candidate's `avformat-62.dll` and the
   already-published static `ffmpeg.exe`. It is **not** introduced by the shared variant and
   **not** a failure of the earlier analysis, which could not see it without the build scripts.
   Routed to S&C / REVIEW; this lane makes no licence claim about it.

## Where the bytes are — deliberately nowhere durable

Both artefacts were downloaded to a **transient staging directory on the Windows capture machine**
that is gitignored and may be swept without warning. That location is **not named here on
purpose**: naming it would make this record cite disposable storage as its evidence, which is the
exact failure `AGENTS.md` → *"Durable Records Must Not Cite Disposable Storage"* exists to stop,
and which is how the last provenance capture was lost.

The durable evidence is the digests. Anyone can re-obtain both artefacts from the URLs in
`provenance.json` and compare hash-for-hash without trusting this machine.

- Release archive — SHA-256 `2936E5449886641B4279CA3FC554B678C8E9A2D20DD0C0A34FE7208B254A0905`,
  70,708,855 bytes.
- FFmpeg corresponding source, `ffmpeg-n8.1.2-34-g9b6c8969e0-source.tar.gz` — SHA-256
  `7E779215EAE16AD7E93DDAD59BD82822BD3D34E4DC61F9996F9481B2C0605BC3`, 16,903,934 bytes.
- Builder repository snapshot — SHA-256
  `F60B77676E5938A6E4767787B58F3703B6290BB9E3150FA339E218FC91C34430`, 101,760 bytes.

Neither is published. This is a candidate, not a shipped artefact. **If this build is ever chosen
for staging, the archive must be retained somewhere durable at that point** — the digests prove
identity but do not preserve bytes, and BtbN will prune the release.

## Packaging assessment: what shared DLLs would require

**Assessment only. Nothing here was implemented.**

`intergalactic/windows/CMakeLists.txt:105-109` installs exactly one file:

```cmake
install(FILES "${INTERGALACTIC_WINDOWS_FFMPEG_EXE}"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/tools/ffmpeg" COMPONENT Runtime)
```

A shared `ffmpeg.exe` imports **all seven** FFmpeg DLLs — confirmed from its PE import table, not
assumed: `avcodec-62`, `avdevice-62`, `avfilter-11`, `avformat-62`, `avutil-60`, `swresample-6`,
`swscale-9`. What would change:

1. **The install rule must carry the DLLs.** They belong in the same
   `${INSTALL_BUNDLE_LIB_DIR}/tools/ffmpeg` directory: Windows searches the executable's own
   directory first, and the Dart resolver already launches `<root>/tools/ffmpeg/ffmpeg.exe` by
   absolute path, so **no Dart change is needed** — the resolver and `_toolRuns` keep working
   unchanged.
2. **The staging directory becomes multi-file, and its guard has to follow.** The existing
   `FATAL_ERROR` on a stray `ffprobe.exe` exists because one stale file silently re-added ~173 MB
   to the installer. A directory that legitimately holds eight files needs a positive check — the
   seven expected DLLs present *and* nothing unexpected — not the current
   single-file-plus-one-forbidden-name shape. A shared build missing one DLL fails at process
   start, not at configure time, and `_toolRuns` would report it as a generic "tool not usable".
3. **`ffplay.exe` and the `lib/`, `include/`, `doc/` trees must not be staged.** The archive
   carries them; this project ships none of them.
4. **Version-identity and checksum surfaces widen.** Whatever enumerates the desktop payload for
   the release checksum file now has eight FFmpeg entries instead of one.
5. **The packaged licence notice gap does not close and gets slightly worse.** Queue row
   *"Desktop Native Third-Party Notices And AGPL Source Chain"* already records that
   `tools/ffmpeg` installs with no licence text beside it. Seven more covered files land in the
   same directory.

### The size argument is much weaker than the archive sizes suggest

| | Bytes | |
| --- | ---: | --- |
| Static archive (same release) | 145,937,826 | |
| Shared archive | 70,708,855 | **51.5% smaller** |
| Static **installed** payload (`ffmpeg.exe`) | 173,416,960 | |
| Shared **installed** payload (`ffmpeg.exe` + 7 DLLs) | 143,486,464 | **17.3% smaller** |

The archive halves; the installed payload does not. The archive comparison is flattered by the
static zip also containing `ffplay.exe` and `ffprobe.exe` as full standalone binaries, none of
which this project installs. Real saving is ~29.9 MB, not ~75 MB.

**This does not touch the other reason for the shared variant.** Dynamic linking still collapses
the LGPL-2.1 §6 / LGPL-3 §4 relink provision that static linking engages, and that reason was
always the stronger one. But if the size figure is being used to justify the work, it should be
17%, not 50%.
