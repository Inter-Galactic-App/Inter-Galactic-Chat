# Beta Response Snippets

Status: manual COMMUNITY helper
Last updated: 2026-06-16

Use these snippets for beta Matrix rooms, email replies, GitHub issue updates,
or release-testing notes. Keep them short, edit details before sending, and do
not promise a release date unless RELEASE PIPELINE has already scheduled it.

## v0.7.4+985 Beta Update Post

Maintainer note: the Windows desktop and Android `0.7.4+985` website release is
live, and Windows/Android update smoke passed. The current iOS/TestFlight
candidate is `0.7.4+986` and remains pending App Store/TestFlight availability.

Inter Galactic v0.7.4 build 985 is available for beta users.

Windows desktop:
- Use the in-app updater or download the installer:
  `https://app.ourgalaxy.space/downloads/InterGalactic-Setup-0.7.4+985.exe`
- This open-source beta does not use a paid Windows publisher certificate yet.
  The updater verifies the downloaded installer by checksum, and Windows may
  still show an unsigned publisher or UAC prompt. Continue only if you expected
  the Inter Galactic update.

Android:
- Download the direct APK:
  `https://app.ourgalaxy.space/downloads/InterGalactic-0.7.4+985.apk`
- This is a website APK download, not a Play Store update.

iPhone:
- Update through TestFlight once the current v0.7.4 build is visible there.
  The current iOS/TestFlight candidate is build 986.

Source:
- Public source repo:
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat`
- Current public source tag:
  `https://github.com/Inter-Galactic-App/Inter-Galactic-Chat/tree/v0.7.4%2B986`
- Build-matched `0.7.4+985` source archive:
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`.
- Public changelog:
  `https://app.ourgalaxy.space/updates/changelog/v0.7.4.md`.

Known beta caveat:
- Windows gameplay streaming is still in active beta validation. If a game or
  screen share feels unstable, try the Smooth profile or a lower quality level
  and send a report with the app build and stream-test/request details.

Need help:
- Use Help -> Report a Bug inside the app when possible so the report can
  include user-entered details and optional redacted diagnostics.
- If the app cannot open, email `intergalactic@ourgalaxy.space` with your
  platform, app version, steps, and any safe screenshots.

## Bug Received

Thanks for the report. I have the issue logged for triage.

If you can reproduce it again, the most useful details are the app version,
platform, what you were doing just before it happened, screenshots if safe, and
redacted logs from Help -> Report a Bug.

## Use In-App Report A Bug

Please use Help -> Report a Bug from inside Inter Galactic if the app can still
open. That flow shows the payload before sending and can attach recent redacted
logs and device/app details.

If the app cannot start, send the app version, platform, steps, and any safe
screenshots to `intergalactic@ourgalaxy.space`.

## Needs Reproduction Details

I need one more detail before this is actionable:

- app version/build
- platform and OS version
- exact steps to reproduce
- whether it happens every time or only sometimes
- screenshot or short recording if it does not expose private content

## Known Issue Acknowledged

This matches a known issue we are already tracking.

Current status:
- <investigating / accepted / fix pending>

Workaround:
- <short workaround or "none yet">

Next update:
- <what evidence or build we are waiting for>

## Feature Request Received

Thanks. I captured this as a feature request, not a bug.

The request is being framed around the user problem first:
- <user problem>

Current status:
- investigating

## Feature Request Rejected

Thanks for the suggestion. We are not planning to build this as requested.

Reason:
- <privacy risk / Matrix compatibility / product fit / maintenance cost /
  duplicate request / existing workflow>

Closest current option:
- <existing workflow or "none">

## Fixed In Next Build

A fix exists and is waiting for the next build.

What to do now:
- Use the workaround if needed until the next build is available.

Next update:
- We will update the known issue after the fixed build is released or smoke
  tested.

## Fixed In Current Build

This should be fixed in the current build.

Please update, retry the same steps, and report back if it still happens. If it
does recur, include the current app version/build and use Help -> Report a Bug
so the report includes fresh redacted diagnostics.

## Abuse Or Safety Report

Use the in-app Matrix report action when available because Matrix-native
reports go to the selected homeserver, which controls the account, room, and
moderation path.

For app-level issues, unavailable report flows, or routing help, contact
`intergalactic@ourgalaxy.space`. If there is immediate danger, contact local
emergency services.

## Security Report

Please do not post exploit details publicly. Send the report privately to
`intergalactic@ourgalaxy.space` with the affected version, impact, reproduction
steps, and any safe evidence.

## Privacy Or Account Deletion

Inter Galactic is a Matrix client. The selected homeserver controls account
deletion, deactivation, retention, and identity checks.

Use the selected homeserver's account or privacy process first. Contact
`intergalactic@ourgalaxy.space` for app-policy questions or routing help.
