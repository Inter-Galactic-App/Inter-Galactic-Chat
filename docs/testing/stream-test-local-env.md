# Stream-Test Local Env

Status: current
Owner: EXPERIMENTAL for stream-lab behavior; REVIEW for public-safe local path
workflow
Last updated: 2026-06-21

The stream-lab wrappers need machine-local roots for runtime output, patched
WebRTC builds, and optional live app command files. Keep those roots in a local
env file instead of editing wrapper scripts, tests, or documentation examples.

## Setup

From the app repo root:

```powershell
Copy-Item stream-test.env.example .env.stream-test.local
```

Edit `.env.stream-test.local` for your machine. The file is ignored by git.

Minimum values:

```text
INTERGALACTIC_WORKSPACE_ROOT=<workspace root containing intergalactic-app, runtime, and webrtc-build>
INTERGALACTIC_STREAM_LAB_DIR=<workspace root>\runtime\stream-lab
INTERGALACTIC_WEBRTC_BUILD_ROOT=<workspace root>\webrtc-build
```

Optional values:

```text
INTERGALACTIC_STREAM_LAB_OUTPUT_ROOT=<stream-lab root>\local-results
INTERGALACTIC_STREAM_TEST_APP_DIR=%APPDATA%\Inter Galactic\Inter Galactic\logs\stream-tests
INTERGALACTIC_LIBWEBRTC_DLL=<path to libwebrtc.dll>
INTERGALACTIC_GAME_CAPTURE_HELPER_PATH=<path to intergalactic_game_capture_helper.exe>
INTERGALACTIC_GAME_CAPTURE_TARGET_PATH=<path to InterGalacticCaptureTarget.exe>
```

## How Wrappers Use It

The PowerShell wrappers under `tools/stream-lab/` automatically load
`.env.stream-test.local` from the app repo root. Environment variables already
set in the shell take precedence over values in the file.

To load the same file into the current PowerShell session before launching a
Debug app:

```powershell
. .\tools\stream-lab\stream_lab_env.ps1
Import-StreamLabLocalEnv -RepoRoot (Get-Location).Path
```

The app-side live tuning harness reads `INTERGALACTIC_STREAM_LAB_DIR` from the
process environment. When running a Debug app for live stream testing, launch
the app from a shell that has loaded the same values or set the variable at the
user/session level.

`tools/stream-lab/run_true_receiver_test.ps1` also loads this file. Its default
receiver reports go under:

```text
<INTERGALACTIC_STREAM_LAB_DIR>\receiver-results
```

If `INTERGALACTIC_STREAM_LAB_DIR` is not set, the fallback is:

```text
<INTERGALACTIC_WORKSPACE_ROOT>\runtime\stream-lab\receiver-results
```

Set `INTERGALACTIC_STREAM_TEST_ENV` only when you need to load a local env file
from a non-default location.

## Public Repo Hygiene

- Commit `stream-test.env.example` and docs only.
- Do not commit `.env.stream-test.local`.
- Do not create or preserve generated `runtime/` output inside the app repo;
  route stream-lab and capture evidence to the workspace runtime tree instead.
- Do not paste personal absolute paths, raw stream logs, source window titles,
  process ids, or Matrix identifiers into public docs or fixtures.
- Keep Dart stream-test redaction fixtures as repo-friendly relative paths;
  use the local env file only for runnable machine roots.
