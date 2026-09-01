# Inter Galactic Changelog

This changelog records shipped and user-facing Inter Galactic app work. Public
website release notes are maintained in `PUBLIC_CHANGELOG.md`.

## v0.8.1 (Released)

Build date: 2026-08-22
Released build: `0.8.1+1004`

### Inbox, Rooms, And Messaging

- Added a cross-platform Inbox catch-up surface for unread rooms and direct
  mentions, with muted-room filtering, read handling, adaptive desktop/mobile
  presentation, and cached media previews.
- Inbox rows now load permitted URL previews without requiring the room to be
  opened first. Encrypted-room preview preferences and locked direct-message
  boundaries are respected.
- Mention search now matches usernames, account display names, full user IDs,
  and the existing nickname fuzzy match.
- Pinned messages in encrypted rooms now use the normal decryption path before
  they are displayed.
- Read-receipt updates for events outside the loaded timeline are ignored
  safely instead of freezing or crashing the room view.
- Room timeline refreshes now preserve photo-stack anchors when live events are
  inserted, keeping grouped media attached to the correct messages.
- Temporary room notification snoozes now sync through the user's Matrix
  account data and apply across devices, while retaining a local fallback when
  a room is unavailable.
- Timeline history loading now stops when repeated requests add no displayable
  content and resumes when the user scrolls toward older messages. This removes
  the runaway loading behind lag and crashes in busy rooms and call rooms.
  Some call rooms may still not load their complete history.

### Calls And Audio

- Call-room side chat and full text chat are now mutually exclusive, preventing
  two chat surfaces for the same room from appearing together.
- Call-room chat no longer repeats call start, answer, end, and rejection
  events that are already represented by the call surface. Direct-message call
  history remains unchanged.
- Call server discovery is resolved once per synchronization pass instead of
  once for every participant update.
- Participant updates are coalesced per synchronization pass, reducing churn
  during active calls.
- Call-control failures now appear inline in the call menu and are announced to
  accessibility services instead of being sent to an unavailable global
  snackbar.
- Per-participant volume and mute choices now persist across calls with the
  same person, and returning a participant to the default volume no longer
  leaves a stale override behind.
- Call connectivity recovery no longer treats a transient or stale network
  verdict as a permanent reason to block calling.
- Live call connection cleanup closes sockets that finish after a timeout and
  leaves connections that completed on time untouched.
- Optional participant-loudness measurements now follow the call rather than a
  diagnostics page, remain available after that page closes, and distinguish
  quiet participants from sessions with too few usable samples.
- Android noise suppression now binds to its own WebRTC engine, reports when
  processing is applied, handles capture-channel metadata correctly, and avoids
  reloading the model on every attach retry.
- Android noise suppression refreshes its bundled model when the installed app
  build changes, allowing updated models to recover on existing installations.
- Automatic microphone gain control is enabled by default for supported audio
  capture profiles.

### Media, Emoticons, And Soundboard

- Photo preparation now removes embedded metadata by default before sending
  compatible images, including EXIF, ICC, XMP, and supported animated-image
  metadata, while preserving frames, orientation, and animation behavior.
- Image preparation now keeps bytes, filename, and MIME type consistent after
  conversion, recognizes the actual file signature when declarations are
  misleading, and sends the original file unchanged when safe preparation is
  not possible.
- Image and GIF attachment sending now uses a shared bounded preparation path
  across composers and preserves a usable fallback for unsupported inputs.
- Emoji and sticker packs now support account-scoped ordering with accessible
  move controls, stable ordering for newly discovered packs, and preservation
  of remotely added items.
- Emoji recent-history synchronization now interoperates with compatible
  clients without deleting entries the app cannot parse.
- Legacy soundboard packs now receive deterministic display labels when more
  than one is present, while user-renamed packs and stored pack identities stay
  unchanged.
- Protected soundboard mutations can safely retry the same request once when a
  retryable response is received, without replaying playback or treating a
  second user action as the same request.

### Notifications, Sharing, And Privacy

- Android inbound shares are staged as soon as the receiving activity receives
  them, preserving transient read access for cold, warm, and multi-image share
  flows.
- Android rich notifications now use a single foreground **Mute** action that
  opens the room's notification settings, where all supported snooze durations
  remain available.
- Android notification replies now open the app before sending, and image,
  GIF, and sticker events retain their media previews when the event data is
  valid, including encrypted attachments.
- Android notification preview files now grant the system UI read-only access,
  while private previews continue to remove semantic attachment data and media.
- iOS background notification handling now keeps response processing alive long
  enough to finish and avoids posting a duplicate generic alert after the
  specific notification has been delivered.
- Notification badges now bound counts without allowing large values to
  overflow or force the badge outside its layout.
- Bug reports no longer include the computer's device name.
- Encrypted-session recovery requests now use a single-flight callback gate so
  concurrent stale observations cannot trigger duplicate repairs.

### Appearance And Accessibility

- App tooltips now consistently use the app surface and theme, restore usable
  placement beside rail controls, avoid covering clickable icons, and expose a
  single accessible label instead of announcing controls twice.
- Button tooltip placement now adapts for controls near the top edge, keeping
  close and call controls readable without covering surrounding content.
- The desktop small-window control now appears in the title bar where the
  window state can be changed without opening the account panel.

## v0.8.0 (Released)

Build date: 2026-07-09
Released build: `0.8.0+993`

- Redesigned the Emoticon Creator with separate quick actions and a responsive
  editor for cropping, naming, usage, saving, background removal, mask cleanup,
  preview backgrounds, and drafts.
- Added image-only clipboard paste on desktop, Android, and iOS through the
  normal attachment review and preparation flow.
- Added Android audio diagnostics and the packaged enhanced voice-cleanup
  runtime used by supported builds.
- Added mobile call popout support, Android foreground call retention and
  picture-in-picture, and native iOS picture-in-picture for active video calls.
- Improved detached desktop call windows, transparent chrome, call controls,
  connection-health display, and participant layout behavior.
- Improved story and media rendering for video backgrounds, image stacks,
  animated media, letterboxing, drafts, upload, and save operations.
- Improved first-account profile refresh so the initial avatar appears more
  reliably after sign-in and account setup.
- Expanded accessibility semantics, settings structure, favorite-room category
  controls, and reduced-motion handling for animated media.
- Added clearer sender, receiver, renderer, and reporting boundaries to Windows
  gameplay-streaming diagnostics.
- GIF search now uses the managed Klipy relay by default, with local overrides
  still supported.

## v0.7.4 (Released)

Build date: 2026-06-13
Released build: `0.7.4+985`

- Restored categorized space ordering and removed the broken nested-space option
  from the summary add-room flow.
- Hardened thread attachment and deletion refresh behavior, room invitation
  handling, and notification/crash-report recovery paths.
- Improved URL-preview privacy and cache behavior for encrypted and supported
  public-provider links.
- Improved call media startup and teardown, screen sharing recovery, and
  participant audio handling.
- Added stronger Windows gameplay-streaming diagnostics and safer media,
  attachment, and notification redaction behavior.
- Refined iOS authentication, notification, camera, and screen-sharing paths.

## v0.7.3 (Released)

Build date: 2026-06-01
Released build: `0.7.3+984`

- Removed WAV/audio attachments from bug-report uploads; audio diagnostics stay
  local to the app's diagnostic workflow.
- Added consent-aware URL-preview behavior for encrypted rooms and durable
  preview caching for supported public providers.
- Improved story capture, video playback, rich presence, notification snoozing,
  account recovery, and call-session reliability.
- Improved iOS ReplayKit screen sharing and Android notification/pusher cleanup.
- Hardened attachment, stream, and plugin boundaries across supported platforms.

## v0.7.2 (Released)

Build date: 2026-05-30
Released build: `0.7.2+980`

- Improved desktop update verification and the consent path for unsigned
  update packages.
- Restored selected-account focus after restart and improved multi-account
  session restoration.
- Improved story notifications, call controls, URL previews, room navigation,
  and encrypted-history recovery.
- Added broader settings, accessibility, notification, and media safeguards.

## v0.7.0 (Released)

- Added the first broad Inter Galactic feature cycle for stories, calls,
  streaming, richer notifications, URL previews, account recovery, and
  diagnostic bug reports.
- Improved desktop navigation, settings organization, themes, profile editing,
  room invitations, forums, threads, and media attachments.
- Added safer notification previews, bounded diagnostic data, and platform
  fallbacks for Android, iOS, Windows, web, and macOS-capable surfaces.

## v0.6.6 (Released)

- Improved photo rooms, mobile appearance, background tasks, crash reporting,
  calendar interactions, call diagnostics, screen sharing, and media previews.

## v0.6.5 (Released)

- Added the Android port, improved notifications, mobile appearance, desktop
  UX, calls, attachments, threads, forums, room navigation, rich presence, and
  detached call windows.

## Earlier releases

- v0.6.1 improved iPhone PWA session durability and client lifecycle handling.
- v0.6.0 standardized the app namespace, call rooms, session-sync recovery,
  bundled themes, and forum room support.
- v0.5.2 improved Android bug reporting and application icons.
- v0.5.1 delivered the first Android app build.
- v0.5.0 established the initial Matrix client, room, messaging, media, and
  desktop foundations.
