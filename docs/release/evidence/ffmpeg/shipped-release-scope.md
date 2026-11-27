# Which releases shipped this `ffmpeg.exe` — measured, 2026-08-09

Recorded by REVIEW to close an open question on the FFTW disclosure: the
disclosure originally travelled *with the binary* rather than naming releases,
because nobody had verified how far back the binary went. This measures it.

## Method

Every desktop payload retained under `Desktop_Builds/Inter-Galactic/<version>/`
was opened as a zip and `tools/ffmpeg/ffmpeg.exe` hashed **from inside the
release artefact** — not from the staging directory, and not inferred from build
dates. Nineteen payloads, `0.7.2+980` through `0.8.1+1001`.

Reference digest, the staged binary and the one recorded in
`docs/release/evidence/ffmpeg/manifest.json`:

    C5C6E92D80884470A4D09C80A801989757DB1E80837E5018B636AF76DD826FEC
    173,416,960 bytes

## Result

| Builds | `tools/ffmpeg/ffmpeg.exe` |
| --- | --- |
| `0.7.2+980`, `0.7.3+981` … `0.7.3+984` | **absent** — FFmpeg was not bundled yet |
| `0.7.4+985` onward, all 14 payloads | **identical** to the reference digest |

There is no third case. Not one payload carries a *different* FFmpeg: the
binary appears at `0.7.4+985` and never changes again through `0.8.1+1001`.

`0.7.4+985` also carries `ffprobe.exe` at
`134B9BC17D0FE3B1F81ECA108615356F4C304C58C7750CE85592E8CFDBB3F523`,
173,210,624 bytes — matching the digest `manifest.json` records for it.

## What this settles

**`0.7.4+985` is the first release to bundle FFmpeg, and therefore the first to
carry FFTW.** Of the public releases, three are affected: `0.7.4+985`,
`0.8.0+992`, `0.8.0+993`. The `0.8.1` payloads carry it too but none is public.

Anything scoping the FFmpeg or FFTW obligation to `0.8.0+992`/`+993` alone is
**too narrow** and should name `0.7.4+985` as the start.

## Limits of this measurement, stated so it is not over-read

- It covers the payloads **retained on this machine**. It is strong evidence for
  what was built and shipped, but `Desktop_Builds/` is gitignored and is not an
  authoritative distribution record.
- It says nothing about builds that were never retained, and nothing about
  non-Windows targets.

  *Corrected 2026-08-15.* That second clause used to read "macOS and Linux
  resolve FFmpeg from `PATH` and bundle nothing". True of **this tool pair**,
  false as a statement about those platforms: only Linux bundles nothing.
  macOS, iOS and Android all bundle an FFmpeg through media_kit. Those are
  separate artefacts with their own obligations, and nothing in this file
  measures them.
- It establishes byte identity of the executable, not that the surrounding
  packaging was identical.

Reproduce by hashing `tools/ffmpeg/ffmpeg.exe` inside each
`Desktop_Builds/Inter-Galactic/<version>/*.zip` and comparing against the digest
above; no unpacking to disk is required.
