# Inter Galactic Changelog

This changelog records app behavior and user-visible changes. Public release
highlights are maintained in `PUBLIC_CHANGELOG.md`.

## v0.8.2 (In Progress)

Current manifest: `0.8.2+1008`. This section remains in progress until release.

### Inbox, Rooms, And Messaging

- Added message forwarding for text, images, and links. Choose up to ten
  destination rooms with a searchable picker. An original-author label is a
  claim supplied by the forwarding sender, not a verified source-event link.
- Added Whisper to the composer message effects.
- Opening a conversation from the Inbox on mobile now brings its messages
  into view.
- Message previews, reactions, and poll results refresh as the conversation
  changes. Reply previews and thread summaries stay attached to the right
  messages and update as replies arrive, decrypt, or are removed.
- Read receipts for events outside the loaded timeline are handled safely.
  Search results and unread state also update more reliably as new messages
  arrive.
- Call-room chat can load older messages again, and its timeline refreshes with
  new history. Typing indicators clear after about 30 seconds if a stop update
  is missed.
- Link previews for TikTok, Instagram, and Reddit have separate controls for
  encrypted and unencrypted conversations. Direct requests are off by default.
  When enabled, the configured preview service and homeserver are tried first.
  Incomplete previews may fetch metadata or thumbnails from a provider; even a
  text-complete card may request its site icon if it has no image. Preview
  images and provider icons also display more consistently.
- Desktop composer shortcuts for Tab completion, image paste, sending, Escape,
  and editing now respond to the matching key press. Holding or repeating a key
  no longer causes unrelated typing, repeated sends, or repeated pastes.
- Favorite rooms now sync with your account and appear in other compatible
  clients, with existing favorites preserved during migration. Space rail order
  also syncs. Favorite categories, display preferences, and Frequently Used
  sticker recents remain on this device.
- Room and Space General settings make profile details available to members
  outside the Admin view. Reply highlights preserve custom chat backgrounds.

### Notifications

- On first launch after this update, choose whether notifications stay on or
  are muted for each account. The choice syncs with that account across your
  devices, can be retried if the server is unavailable, and the setup names
  the account it applies to.
- The choice to show full notification previews now remains in effect after
  account settings are refreshed, including when account preferences are
  reinitialized.
- Supported iOS notifications can show decrypted message text, sender, mentions,
  and images; a generic notification remains available when message content
  cannot be decrypted. Android notification image previews are clearer, and an
  Android notification-startup crash has been fixed.
- Reading or snoozing a room clears its corresponding alert more reliably.
- The iOS notification extension now bounds its encrypted-message backup
  request by the time it has left to deliver the notification.

### Messaging And Calls

- Forwarded replies no longer include the quoted author's Matrix ID in the
  visible fallback text.
- Streams play a sound when sharing starts or stops, and stream headers show
  avatars for people watching. On mobile, double-tap your local camera tile to
  switch between front and rear views.
- Windows microphone publishing recovers after sender changes and works when
  joining with Push to Talk enabled. The call tile and muted state appear as
  the call begins.
- Participant tiles are removed when connections change, preventing stale or
  duplicate tiles after reconnects. Call tiles also adapt more cleanly to
  different window sizes, and screen-share quality changes more gradually on
  unstable connections.
- Active, ringing, and joining calls now end when you sign out or quit the app.
- Windows Enhanced noise suppression now has an optional stability setting
  that adds a short hold and hysteresis to reduce rapid loud-speech protection
  changes. It is off by default; existing behavior is unchanged unless enabled.
  Its selected state now persists when the native audio processor is replaced.
- On the web app, a slow first load no longer starts a second encryption
  setup on top of the one still running. Retries now wait for the attempt
  already in progress, and only a genuine failure starts a fresh one.
- Decryption retry actions now explain when encryption is still preparing or
  could not start, rather than appearing available but doing nothing.
- Encrypted-history sharing now explains when a request is waiting for storage
  recovery and can be retried.

### Startup And Background Execution

- Windows verbose startup DNS diagnostics now compare bounded IPv4 and IPv6
  outcomes without overlapping unfinished family probes. Diagnostic errors are
  isolated from original failure observations; network request behavior is unchanged.
  Stack attribution recognizes Dart's anonymous-closure lookup frames.
- Relaunching Inter Galactic on Linux is more reliable after an unexpected
  close, including when a previous process left behind a stale connection file.
- Closing an account during a database reconnect now releases its database
  correctly. iOS resumes more reliably after backgrounding, and delayed
  background-execution work is cleaned up instead of accumulating.

### Accessibility

- Tooltip announcements no longer repeat unnecessarily in supported
  accessibility surfaces. Screen-reader behavior can still vary by platform.
- The in-app FAQ now includes current guidance for stories, soundboard, Desktop
  Companion, activity privacy, noise suppression, message effects, themes, and
  accessibility.

### Updates And Security

- Updated the Windows WebRTC component notice and rebuild instructions to
  identify the selected native source revision, preserving earlier release
  records and their source routes.
- Corrected iOS archive verification to recognize Xcode's archive settings query,
  and made native rebuild validation select the staged candidate explicitly.
- Separated factual public release records from private build-attempt ledgers.

- The Windows updater offers a download link only when it comes from a trusted
  update source and uses a standard secure web address.
- If message encryption cannot start, the warning now describes the session's
  initialization failure without assuming an encryption component is missing.
- Exception stack traces in exported diagnostics now pass through the same
  sensitive-information redaction as other log text.

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
