# Public Changelog

This app-repo copy mirrors the current public-safe release note entry for the
source archive and public repository. The release workflow publishes the same
public changelog section to the website update metadata.

Current public changelog target:

- `https://app.ourgalaxy.space/updates/changelog/v0.7.4.md`

Previous published changelog:

- `https://app.ourgalaxy.space/updates/changelog/v0.7.3.md`

Internal engineering history belongs in `CHANGE_LOG.md`.

---

# Inter Galactic v0.7.4 Beta

Build date: 2026-06-16
Build identity: v0.7.4+985 for Windows desktop and Android direct APK;
v0.7.4+986 for the refreshed iPhone TestFlight candidate.
Status: Beta update for Windows desktop, Android direct APK, and iPhone
TestFlight release flow.

## Highlights

### Top Changes

- Spaces are easier to organize: categorized room lists now keep the Matrix
  space order inside each category, and adding a room from a space no longer
  offers a broken nested-space creation path.
- Threads, attachments, and media previews are more reliable. Attachment-only
  thread sends no longer report a false failure after upload, thread deletes
  refresh sooner, and recent social link thumbnails are less likely to vanish
  after leaving and reentering a room.
- Calls and notifications have fewer noisy failure states. Local call mute,
  push-to-talk, deafen, and speaker-volume changes handle stream churn more
  safely, desktop notifications clear better after a room is read elsewhere,
  and ordinary nonfatal runtime errors are less likely to appear as critical
  next-launch crash prompts.
- Privacy and support surfaces are clearer. New installs get an explicit
  encrypted-room URL preview choice, website feedback is separated from
  diagnostic bug reports, and public support, privacy, terms, abuse, and
  third-party notice links are better aligned for the beta release flow.
- Windows gameplay streaming and story video tools continue to improve for
  beta validation. Gameplay-stream diagnostics now distinguish more sender,
  encoder, and host-load limits, while story video upload and recording paths
  have more platform-aware trimming and export handling.

### Messaging, Spaces, And Media

- Space category ordering now follows the current Matrix space-child order
  inside each category instead of using only category assignment order.
- The space add-room picker keeps normal room types available while hiding the
  nested Space option from that flow.
- Thread uploads and attachment-only sends are less likely to show confusing
  failure dialogs after the upload already succeeded.
- Deleting a thread upload refreshes the open thread more consistently, even
  after the redacted event loses its thread relation data.
- Recent social URL preview thumbnails can now survive a short room reentry
  window without making those expiring CDN thumbnails part of long-lived
  durable preview data.

### Calls, Audio, And Notifications

- Call audio control updates now snapshot active sessions and streams before
  applying mute, push-to-talk, deafen, and speaker-volume changes, reducing
  failures when participants or streams change at the same time.
- Desktop notification cleanup now follows remote read state more closely, so
  native notifications, the companion overlay, and room read state can converge
  after another device reads the room.
- RNNoise replay checks for the latest supplied voice samples passed objective
  pop/cutout gates for the current production presets, while further tuning
  remains available for background noise and popping edge cases.
- Crash reporting now keeps ordinary app-zone and platform-dispatcher runtime
  errors in diagnostics without turning them into a critical crash prompt on
  the next launch. Fatal startup and headless/background failures still create
  crash prompts.

### Stories, Streaming, And Diagnostics

- Story video upload and recording paths have more intentional platform
  behavior, including mobile trim/export handling and desktop recording/trim
  support for beta validation.
- Windows gameplay streaming diagnostics now show clearer evidence for native
  frame handoff, sender delivery, encoder timing, host load, and source-adapter
  behavior so remaining quality work can be tuned from better reports.
- The current Windows gameplay path remains a beta validation area. Smooth
  720p30 gameplay streaming has improved in recent validation, but stream
  quality can still vary with hardware, game, and host load.

### Updates And Install Flow

- Windows desktop and Android direct APK artifacts continue to use
  build-stamped filenames, checksums, source archives, and update metadata.
- Android release evidence now includes refreshed Gradle runtime dependency,
  Firebase/FlutterFire package, and Google OSS Licenses baseline records for
  the `v0.7.4+985` APK.
- The iPhone TestFlight candidate was refreshed as `v0.7.4+986` for App Store
  Connect export-compliance metadata while keeping the same v0.7.4 beta
  feature set.
- Public release notes, source-offer records, third-party notice evidence, and
  release readiness docs have been tightened for the next beta publication.

### Known Issues

- Windows may still show an unverified-publisher or untrusted-certificate
  prompt for this open-source beta installer. Use the in-app updater or website
  download only when you expected the Inter Galactic update.
- Android remains a direct APK download, so installing or updating may require
  approving installation from the browser or file manager.
- Windows gameplay streaming remains in active beta tuning. If a game or
  screen share feels unstable, try the Smooth profile or a lower quality level
  and send a Report Issue entry with the app version and stream details.
- iPhone distribution remains through TestFlight for this beta flow, so iPhone
  availability may depend on TestFlight processing and the tester's enrolled
  channel.
