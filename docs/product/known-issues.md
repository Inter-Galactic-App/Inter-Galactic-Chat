# Beta Known Issues

This file is the user-facing known-issues format for beta testing. It should
only include issues that beta users need to know about, such as active
workarounds, rollout risks, or fixes that are pending validation.

Last updated: 2026-09-04

## Status Key

- `investigating` - We are collecting evidence or reproducing the issue.
- `accepted` - The issue is confirmed and queued for engineering work.
- `fix pending` - A fix exists but has not shipped or still needs validation.
- `resolved` - The fix shipped or the issue no longer reproduces.
- `closed` - No further action is planned.

## Severity Key

- `critical` - Data loss, security/privacy risk, login blocked, app crash loop,
  messaging fully unusable, or beta rollout must stop.
- `major` - Important feature is broken or very unreliable, but users have a
  workaround or only a subset of users is blocked.
- `moderate` - Noticeable bug that affects normal use but does not block the
  main workflow.
- `cosmetic` - Visual polish, wording, alignment, animation, or other minor UX
  issue that does not change functionality.

## Current Known Issues

### Windows Gameplay Streams May Still Need Native Handoff Validation

**Status:** investigating
**Severity:** major
**Affected platforms:** Windows desktop streaming / LiveKit calls
**Affected versions:** current beta stream diagnostics boundary
**First reported:** 2026-05-02
**Last updated:** 2026-09-04

**What users may see:**
Some gameplay or screen shares can run at lower FPS, stall during diagnostics,
visually "rubber-band" during fast camera motion, or fail to produce a
complete stream-test report while the Windows native NV12 encoder handoff is
still being validated.

**Workaround:**
Use the Smooth profile or lower stream quality when a share feels unstable.
Avoid changing advanced stream overrides unless asked for diagnostics.

**What we are doing:**
Engineering continues validating the BG3 D3D11/native-NV12 screen-share start,
publish, and report-completion boundary. A reconciled libwebrtc build recently
passed local BG3 D3D11 source, GPU NV12, and Media Foundation H.264 checks
(visible-proof and teardown confirmed) on a test-only artifact, but that build
has not replaced the app's canonical libwebrtc yet: a staged app-load check,
the BG3/WGC/remote-playback smoke matrix, and PR review are still outstanding.
This is not currently treated as a support-intake or metadata blocker, but
beta stream reports should keep the exact app build and stream-test request
id.

**Next update:**
After the reconciled libwebrtc build replaces the canonical build and clears
the BG3 D3D11/WGC/remote-playback smoke matrix.

### A Screen Share Can Keep "Sharing" After Its Window Is Closed

**Status:** accepted
**Severity:** moderate
**Affected platforms:** Windows desktop
**Affected versions:** current beta builds
**First reported:** 2026-08-17
**Last updated:** 2026-09-04

**What users may see:**
If the window or app you are sharing is closed instead of stopping the share
first, Inter Galactic keeps publishing a screen share for a source that no
longer exists. Other participants may keep seeing a frozen or dead
screen-share tile until you stop the share manually.

**Workaround:**
Stop the screen share from the call controls before closing the shared
window or app, rather than closing it first.

**What we are doing:**
A fix is planned that watches the shared window handle and automatically ends
the share when the window closes; it has not been implemented yet.

**Next update:**
After the window-close watcher lands and is validated on a rebuilt desktop
build.

### Shared Game Audio Can Be Silent When The Game Runs Elevated

**Status:** fix pending
**Severity:** moderate
**Affected platforms:** Windows desktop
**Affected versions:** current beta builds; games or anti-cheat software that
run with elevated/administrator privileges (for example EAC, BattlEye, or
Vanguard-protected titles)
**First reported:** 2026-07-20
**Last updated:** 2026-09-04

**What users may see:**
When sharing a specific game window while the game (or its anti-cheat) is
running elevated, other call participants hear no audio from the game even
though the share looks healthy and diagnostics report data flowing normally.
This is a Windows OS boundary that also affects other apps (for example
Discord) unless they run elevated too.

**Workaround:**
Run Inter Galactic as Administrator, or share your whole screen/display
instead of just the game window - a display share captures system audio
regardless of the game's elevation level.

**What we are doing:**
A fix that detects an elevated share target and shows a warning with the two
workarounds above is implemented on a branch and passes local checks, but it
is not yet merged. A native build confirmation and two-account runtime test
remain before it ships.

**Next update:**
After the fix merges and runtime validation confirms the warning and
workaround both appear correctly.

## Recently Resolved

Move resolved issues here after the fix ships and beta users no longer need a
top-of-page warning.

### Android Voice Messages No Longer Render As Video Attachments

**Resolved in:** 2026-05-20, user-verified
**Original severity:** moderate
**User action needed:** none on current builds

**Summary:**
The Android recorder's `audio/mp4` MIME type was being overwritten by a
filename/header-based guess that could misclassify `.m4a` audio as video,
so some Android-recorded voice messages appeared in the video-style
attachment surface instead of the compact voice-message bubble. Attachment
resolution now preserves the recorder-provided MIME type, and legacy `.m4a`
events with a video MIME are recognized as audio by filename so they recover
into the voice bubble. No data was ever lost; affected messages could still
be opened from the attachment surface.

### Rapid Call Join/Leave No Longer Locks Out Future Joins On Windows

**Resolved in:** 2026-08-17, owner-validated
**Original severity:** major
**User action needed:** update to a current build; if you still hit a full
call lockout that only clears with an app restart, please report it

**Summary:**
After several rapid join/leave cycles across call rooms, every later join
attempt could fail almost instantly and only a full app restart would restore
calling. The cause was a Windows networking check that could report "no
internet connection" from a single long-lived system state even on a healthy
network, which then blocked every LiveKit join regardless of actual
connectivity. A guard now overrides that false verdict when a real network
route is available; the owner validated 12 consecutive join/leave cycles with
zero lockouts afterward. The underlying engineering tracking item is
deliberately left open pending a second confirmation session on a different
day, which is why this note is not yet fully retired.

### Several Early-Beta Desktop Fixes (May 2026)

**Resolved in:** 2026-05-15, user-confirmed desktop runtime validation
**User action needed:** none on current builds

**Summary:**
Several early-beta desktop issues were fixed and user-confirmed in the same
2026-05-15 validation pass: Activity/Desktop-Matrix presence status clearing
after network or server errors, Desktop Companion avatar/count click routing,
and Desktop URL previews after the durable preview-cache work. The in-app
Report a Bug flow was also fixed the same day so submissions reach the live
support endpoint (`intergalactic@ourgalaxy.space`) instead of failing on
oversized payloads or unsupported attachments. These are several release
cycles behind the current beta and are kept only as a short historical
pointer.

## Listing Template

Copy this when adding another beta-visible issue:

### `<Short User-Facing Title>`

**Status:** investigating / accepted / fix pending / resolved / closed
**Severity:** critical / major / moderate / cosmetic
**Affected platforms:** Windows / Android / iOS / web / Linux / macOS / all
**Affected versions:** app version/build or release range
**First reported:** YYYY-MM-DD
**Last updated:** YYYY-MM-DD

**What users may see:**

**Workaround:**

**What we are doing:**

**Next update:**

**Maintainer tracking:** optional private tracker link; omit from public copies
unless it is safe for beta users to open.

## Update Communication Template

Use this when posting updates to beta users:

```text
Status update: <issue title>

What changed:
- <short user-facing change>

Who is affected:
- <platform/build/user group>

What to do now:
- <update, workaround, retry, or no action>

Next update:
- <when or what evidence we need next>
```
