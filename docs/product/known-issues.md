# Beta Known Issues

This file is the user-facing known-issues format for beta testing. It should
only include issues that beta users need to know about, such as active
workarounds, rollout risks, or fixes that are pending validation.

Last updated: 2026-06-09

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

### Android Voice Messages May Render As Video Attachments On Older Builds

**Status:** fix pending
**Severity:** moderate
**Affected platforms:** Android
**Affected versions:** beta builds before the Android voice-message MIME fix ships
**First reported:** 2026-05-13
**Last updated:** 2026-05-15

**What users may see:**
Some Android-recorded voice messages can appear in a video-style attachment
surface instead of the compact voice-message bubble.

**Workaround:**
No data is lost. The message can still be opened from the attachment surface.
Update once a build containing the MIME preservation fix is available.

**What we are doing:**
The app now preserves recorder-provided audio MIME type and can recover some
older `.m4a` events into the voice bubble when filename metadata is present.

**Next update:**
Android runtime validation is still pending. Test a fresh Android voice message
and, if possible, an older `.m4a` voice message once the next Android build is
available.

### Windows Gameplay Streams May Still Need Native Handoff Validation

**Status:** investigating
**Severity:** major
**Affected platforms:** Windows desktop streaming / LiveKit calls
**Affected versions:** current beta stream diagnostics boundary
**First reported:** 2026-05-02
**Last updated:** 2026-06-09

**What users may see:**
Some gameplay or screen shares can run at lower FPS, stall during diagnostics,
or fail to produce a complete stream-test report while the Windows native NV12
encoder handoff is still being validated.

**Workaround:**
Use the Smooth profile or lower stream quality when a share feels unstable.
Avoid changing advanced stream overrides unless asked for diagnostics.

**What we are doing:**
Engineering is validating the BG3 D3D11/native-NV12 screen-share start,
publish, and report-completion boundary. This is not currently treated as a
support-intake or metadata blocker, but beta stream reports should keep the
exact app build and stream-test request id.

**Next update:**
After the next rebuilt-app BG3 Smooth stream-test confirms whether the runner
enters measurement and writes a completed report.

## Recently Resolved

Move resolved issues here after the fix ships and beta users no longer need a
top-of-page warning.

### Activity Status Clears Correctly Again

**Resolved in:** 2026-05-15 user-confirmed desktop runtime validation
**Original severity:** major
**User action needed:** none if running a build with the activity clear retry
hardening

**Summary:**
Activity status and Desktop/Matrix presence clearing are user-confirmed fixed.
The previous beta warning about stale game/activity status after network or
server errors can be removed from the current known-issues list.

### Desktop Companion Click Routing Is Confirmed Fixed

**Resolved in:** 2026-05-15 user-confirmed desktop runtime validation
**Original severity:** moderate
**User action needed:** none if running a build with the companion click-routing
fix

**Summary:**
Desktop Companion avatar/count click routing is user-confirmed fixed. The
companion now opens/focuses the expected notification room in the validated
desktop flow.

### Desktop URL Previews Work After The Durable Cache Fix

**Resolved in:** 2026-05-15 user-confirmed desktop runtime validation
**Original severity:** moderate
**User action needed:** none on desktop builds containing the URL-preview cache
fix

**Summary:**
Desktop URL previews are user-confirmed working after the durable preview cache
and stable loading-shell work. Keep watching future non-desktop validation if
URL preview behavior differs by platform, but the desktop beta warning is no
longer current.

### In-App Report A Bug Submission Now Reaches The Support Endpoint

**Resolved in:** 2026-05-15 bug-report endpoint/client attachment-contract fix
**Original severity:** major
**User action needed:** use Help -> Report a Bug on a build containing the
2026-05-15 fix

**Summary:**
The in-app bug reporter now sends user-entered fields and redacted logs to the
live support endpoint, which emails `intergalactic@ourgalaxy.space`. Earlier
upload failures from oversized JSON payloads and unsupported attachment shape
were fixed and user runtime testing verified the live endpoint accepts the
current flow.

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
