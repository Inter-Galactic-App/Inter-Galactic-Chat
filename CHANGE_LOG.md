# Inter Galactic Changelog

---

## v0.8.0 (In Progress)

Build date: 2026-06-30

Version boundary: v0.8.0 starts after the app version advanced from
`0.7.4+986` into the `0.8.0` development cycle. Current metadata targets
`0.8.0+992`. v0.7.4 release-cycle history continues below.

### Stability And Review Fixes

- Published the v0.8.0+992 supplemental desktop-native source evidence in the
  public source repository. The release record now marks the 992 desktop plus
  Android website publication as complete, keeps the public repo on the 992
  baseline, and links the desktop-native notice/source proof under
  `docs/release/evidence/desktop-native-notices/0.8.0+992/`.
- Hardened the PR #72 review-response batch. Android call picture-in-picture
  controls now require the active call session id and a signature-level
  receiver permission, Matrix security feedback actions route errors through
  the existing dialog flow, notification companion cleanup always tears down
  the window controller, and public release records now avoid maintainer-local
  evidence details.
- Fixed a shutdown hang in client teardown. Direct-message aggregation and
  call-manager disposal no longer await broadcast stream close futures that
  can never complete once a past subscriber has unsubscribed, which could
  stall `ClientManager.close()` indefinitely during logout, account removal,
  or app shutdown.
- Removed the hard-coded visual Favorites parent wrapper from the narrow
  favorites rail. User-created favorite categories now render as top-level
  groups instead of looking like subcategories under a non-editable placeholder,
  while the local favorites category storage and editable starter category stay
  unchanged.
- Fixed a startup crash in the floating background-task overlay. The overlay
  now waits for its floating child to finish layout before measuring and
  snapping, and background-task rows use a stable bounded width, preventing
  render failures and the black-UI cascade they could trigger on launch.
- Fixed v0.8.0 beta integration stability issues.
  The update keeps full detached call tiles on normal rounded panel geometry,
  adds bounded native cutout/PiP platform-channel failure paths, preserves
  Emoticon Creator draft/manual-mask state, restores Flutter iOS build-number
  substitution, fixes photo-stack preview visibility, and tightens PR/docs
  wording. It also keeps Recent drafts current after failed pack updates,
  restores editor controls after failed save/delete operations, and maps manual
  cutout brush edits to the visible image bounds for non-square previews.
  Focused cutout/draft/mobile-PiP/call-view tests, targeted analyzer, and
  Android debug Kotlin compile passed.
- Refined iPhone composer picker spacing. The custom emoji/sticker/GIF picker
  now treats the existing iOS composer keyboard gap as empty space above the
  picker panel instead of extra picker height, so the picker sits with the same
  breathing room as the native keyboard while keeping the total reserved
  composer footprint unchanged. Android keyboard and picker behavior is
  unchanged.
- Added Android composer parity for the recent iPhone camera/picker fixes,
  with an Android-only Inter Galactic photo/video choice before native capture.
  The mobile Camera attachment now opens the app photo/video sheet, then routes
  the selected kind through the native Android camera bridge so photo and video
  captures return the same attachment payload shape as iOS. Android also keeps
  the emoji/sticker/GIF picker reservation alive when the plus menu opens over
  it, preventing the picker from collapsing to the message pill. Automated
  checks passed; on-device Android validation for this change is still
  pending, so treat the camera parity behavior as beta until the rebuilt
  Android smoke completes.
- Fixed iOS native call PiP live video. The final green iPhone build uses the
  active video-call PiP controller with sample-buffer rendering and an iOS-only
  app-level keepalive `CallWidget` so LiveKit adaptive video keeps producing
  frames when the user changes pages or backgrounds the app. `RTCMTLVideoView`
  was tested inside native PiP and received frames but froze visually, so it is
  not the release path. Signed `0.8.0+992` direct install and user smoke passed.
- Fixed iOS native call PiP activation. Live iPhone logs showed the selected
  WebRTC track, sample-buffer renderer attachment, and first frame were all
  healthy, but AVKit still failed `startPictureInPicture` because the
  `AVSampleBufferDisplayLayer` was not anchored to a visible UIKit source. The
  iOS PiP coordinator now attaches that layer to a temporary host view over the
  mounted call surface using the Dart source rect before starting PiP, then
  removes the host during cleanup. A rebuilt signed `0.8.0+992` iPhone install
  logged PiP `will_start`, `did_start`, restore, `will_stop`, and `did_stop`.
- Added the iOS native LiveKit/WebRTC-backed call PiP bridge. iOS now prepares
  the selected existing native WebRTC video track, feeds it into an AVKit
  sample-buffer PiP source, and only marks the call as PiP after native start
  succeeds. The earlier plan to show the in-room popped-out placeholder on iOS
  was superseded by the iOS keepalive path because unmounting the `CallWidget`
  can starve LiveKit adaptive video; Android/desktop placeholder behavior is
  unchanged. No-codesign iOS Release xcodebuild validation passed.
- Added explicit mobile call surface state for popout/PiP lifecycle follow-up.
  Flutter-owned secondary call surfaces now carry the active session id, reuse
  the existing popped-out room placeholder, render a compact live call layout,
  and expose semantic close, return, hang-up, and fullscreen restore controls.
  Android now reports popout session identity through the mobile call channel,
  and iOS reports AVKit PiP session identity/exit requests while preserving the
  current snapshot-source guard. The iOS in-room placeholder remains deferred
  until a native LiveKit/WebRTC renderer or sample-buffer PiP bridge can keep
  AVKit live independently. Focused tests were updated; Dart format and local
  test execution were deferred for that change.
- Fixed the latest iPhone story camera, composer picker, and PiP surface smoke
  issues. Story camera preview/captured video drafts now use the iPhone
  landscape canvas when the story composer is rotated, the composer plus menu
  no longer collapses an already-open emoji/sticker/GIF picker on iPhone, and
  the iPhone picker reservation now matches the native keyboard height more
  closely. iOS call PiP now waits for AVKit readiness before manual start,
  removes the text placeholder overlay from the mirrored call feed, keeps AVKit
  PiP separate from the normal Flutter app surface, removes the non-interactive
  fake native controls from the PiP mirror, and routes system PiP restore back
  to the active call room through the mobile call popout channel. Dart format,
  no-codesign iOS Release compile, signed bundle verification, and direct
  iPhone install of `0.8.0+992` passed.
- Fixed the latest iPhone smoke issues for PiP, settings chrome, and image
  stacks. iOS call PiP now mirrors the active Flutter call surface instead of
  showing only the black placeholder label, mobile settings headers sit on a
  solid surface behind the pinned back/account controls, and timeline image
  stacks keep grouping even when preview pixels are disabled. Dart format,
  no-codesign Release iOS xcodebuild, signed Flutter iOS Release build, and
  direct install of Runner/Broadcast Extension `0.8.0 (992)` passed; automatic
  launch was blocked only because the phone was locked.
- Improved iPhone settings, camera attachment, and composer picker behavior.
  Settings pages now use iOS-native swipe-back capable routes, Camera opens one
  native iPhone capture surface for photo or video before returning to the
  existing attachment preview, and the composer keeps a stable keyboard-sized
  reservation when switching from the keyboard or emoji/sticker/GIF picker to
  the plus/effects menu. Android picker behavior is unchanged. No-codesign
  Release iOS xcodebuild validation passed.
- Polished iPhone settings and composer layout behavior. Mobile settings root
  and subpage headers now use explicit top safe-area placement, the iPhone
  jump-to-latest button sits slightly closer to the composer, and the
  emoji/sticker/GIF picker stores the same iOS keyboard-plus-gap reserve used
  by the real keyboard path. Android keyboard reservation was intentionally
  left unchanged.
- Fixed an iOS 0.8.0+991 direct-install launch crash in Flutter WebRTC native
  event dispatch. The iOS Podfile now reapplies guarded Flutter WebRTC
  event-sink dispatch and ReplayKit broadcast socket teardown patches during
  `pod install`; the rebuilt iPhone install kept build number `991`, survived
  the console launch smoke, and produced no fresh Runner crash report.
- Fixed iOS direct-install packaging for the Broadcast Extension. The extension
  target now carries the current `991` build number instead of resolving an
  empty `$(FLUTTER_BUILD_NUMBER)` value outside the Runner target, and the iOS
  release helper now repairs either numeric or Flutter-variable extension
  versions before archive/export. A rebuilt direct install verified Runner and
  the Broadcast Extension both report `0.8.0 (991)`.
- Hardened Windows detached call and stream popout transparency and shortcut
  handling. Transparent native popout roots now use a fully transparent Flutter
  boundary to avoid native white edge blending, full detached call participant
  tiles keep their normal rounded call-panel geometry, transparent call and
  stream menus stay inside the detached window's local overlay, the stale
  persisted transparent-chrome preference scaffold was removed, and
  mouse-button shortcut capture is Windows-only. Focused Flutter tests,
  targeted analyze, and scoped diff checks passed.
- Refined desktop shell controls for the v0.8.0 review batch. Windows desktop
  builds now use the custom title-bar path from the app shell, the thread side
  panel close control was tightened, and the add-account sign-in route uses a
  compact close affordance that does not steal normal form focus.
- Fixed v0.8.0 integration stability issues.
  Call-health summaries now distinguish connecting state, direct-call stats
  feed health diagnostics, favorite-room starter categories avoid empty first
  seeds, encrypted-message retries re-check after session requests, and desktop
  navigation/title-bar focus paths have targeted regression coverage. Later
  follow-ups tightened demo story video previews, theme import/edit recovery,
  macOS notification sound gating, LiveKit partial-join cleanup, mobile
  call-room rail restore behavior, login completion resilience, and redacted
  developer log exports.
- Hardened v0.8.0 mobile call popout state cleanup, encrypted-history retry
  placement, story refresh ordering, LiveKit retry teardown, preference image
  storage sizing, call-view PiP/screenshare visibility, categorized space
  ordering, cross-signing disposal safety, and calendar edit rollback. Final
  review follow-ups also tightened favorite-order reconciliation, space banner
  and category state resets, calendar edit redaction recovery, receiver-probe
  pipe normalization, and stream-lab preflight geometry validation.
- Hardened stream-test publication handoff behavior. Stream-test
  publication handoff profiles now keep minimum bitrate at or below the
  resolved maximum, and the patched WebRTC installer now prefers the app-local
  Dart package graph while mapping every installer-created backup suffix back
  to its original rollback target. Validation passed with Dart format, targeted
  Flutter analyze, a PowerShell syntax parse, and rollback suffix sanity checks.
- Hardened discover publication and timeline lifecycle behavior. Discover publication
  updates now reject opposite publish/unpublish mutations while one is in
  flight, join and knock preview prompts route through localization, deferred
  timeline scroll recovery re-checks widget lifecycle, stale history-load
  completions no longer clear loader flags for replacement timelines, Matrix
  room teardown cancels subscriptions before closing room streams, and room
  visibility writes wait for room sync before notifying listeners. Knock
  notifications now also respect room notification rules. Public changelog wording
  was also tightened for source and platform metadata
  entries. Validation passed with Dart format, focused Flutter test, targeted
  Flutter analyze, and scoped diff check.
- Confirmed source-offer public route remains `Inter-Galactic-Chat` (publicly
  reachable label); `Inter-Galactic` is currently private.
- Added direct Matrix join-preview coverage for knock-only rooms so
  `joinRoomFromPreview` returns a `knockRequested` result without running the
  normal join/sync path. Validation passed with Dart format, a focused Flutter
  test, and targeted Flutter analyze.
- Hardened discover page caching and supplemental restricted-room state. Discover page caching is now
  bounded, successful joins invalidate cached directory state, request copies
  preserve pagination unless explicitly cleared, and supplemental restricted
  space-child rows are kept account-scoped while successful refreshes remove
  stale supplemental rows. Knock room previews use localized request-to-join
  copy, unknown space-hierarchy join rules stay neutral instead of being
  labeled public, visibility equality has matching hash codes, knock
  notification surfacing catches transient member-fetch failures, mobile panel
  keyboard shortcuts require panel focus, and timeline history recovery stays
  tied to the timeline that loaded the page. Validation passed with Dart
  format, targeted Flutter analyze, focused non-widget Flutter tests, and a
  PowerShell syntax parse of the patched WebRTC installer helper.

### Calls And Streaming

- Call connection details now use Matrix display names for remote participants
  in LiveKit call rooms and direct calls when available, while keeping raw user
  IDs out of exported call-health diagnostics. Remote stream tiles also show a
  compact four-bar signal-strength indicator from call connection quality when
  tile hover controls are visible, with the same chip shown on
  mobile/forced-control surfaces. Focused call-health tests and targeted
  Flutter analyze passed.
- Pinned the mobile call hang-up control when the bottom call-control rail
  overflows. Mobile calls now split the red Leave call button into a trailing
  slot when the combined controls exceed the available dock width, while
  compact mobile rows and desktop controls keep the existing horizontal control
  behavior. Validation passed with Dart format, focused call-view control
  tests, and targeted Flutter analyze.
- Added macOS local notification and Desktop Companion support for the desktop
  windowing build. macOS now uses a local Darwin notifier for message, story,
  call, membership, invite, error, and calendar notifications without Matrix
  push-token registration, and the opt-in Desktop Companion can create a
  separate macOS `RegularWindow` while Windows-only overlay styling remains
  behind Windows guards. macOS falls back to in-app call popouts plus normal
  Darwin notifications when runtime windowing is unavailable. The macOS
  noise-suppression bridge keeps RNNoise linking while Enhanced DeepFilterNet
  remains Windows-only.
- Suppressed the infinite refresh/loading ring in call rooms when they are used
  as text chats. The embedded call-room chat side rail no longer auto-pages
  timeline history/future boundaries or paints boundary loading spinners, while
  normal primary room chat pagination and LiveKit/call media behavior remain
  unchanged. Focused side-rail tests and targeted Flutter analyze passed.
- Added desktop call-control cleanup for compact and detached call surfaces,
  including shared call action controls and stream popout panel structure.
  Windows and desktop streaming diagnostics continue to keep sender, receiver,
  renderer, and local profile evidence separated for review.
- Added custom Windows title bars for opaque native detached call and
  per-stream popouts. The title bar provides drag, dock, minimize,
  maximize/restore, close, pin, and transparent-chrome controls on the detached
  popout window, while transparent mode hides the title bar and keeps the dark
  hover controls. Detached popout roots now paint explicit non-white surfaces
  so Flutter's default white background does not appear beneath call tiles. The
  root safety boundary now wraps the local popout overlay itself, ensuring
  tooltip/menu overlay entries inherit the transparent Material/background in
  opaque and transparent modes.
- Tightened call-room side-rail and detached stream-popout controls. Collapsed
  transparent popout chrome now keeps the water-drop opacity control centered in
  its circular target, and call-room headers add Chat and Members quick actions
  after the invite slot so users can swap the right side rail between room chat
  and members. Rooms with existing unread chat/mention state auto-open the chat
  rail once on first selection. Focused detached-window and side-rail tests plus
  targeted Flutter analyze passed; rebuilt desktop smoke remains pending.
- Added mouse-button shortcut bindings for desktop shortcut settings and Push
  to Talk. Shortcut settings can record mouse buttons 3, 4, and 5, persist them
  alongside keyboard bindings without breaking legacy hotkey JSON, and route
  Windows polling through the same binding path used by normal shortcuts and
  call PTT hold/release. Focused shortcut/navigation/CallManager tests and
  targeted Flutter analyze passed; rebuilt Windows smoke remains pending.
- Added Android mobile-call background retention through a call foreground
  service and enabled Android picture-in-picture from the call popout control.
  Call session state now keeps the platform background service in sync with
  active microphone/camera use. Focused Dart and Android Kotlin validation
  passed; real mobile device call-background smoke remains queued before
  treating the path as fully validated.
- Split the stream-test runner into smaller diagnostics, receiver-probe,
  reporting, scoring, summary, and coverage modules. The automation path now
  supports receiver-probe configuration, publication handoff caps, protected
  external probe credential handoff, and in-process render probe diagnostics
  without keeping all logic in one file.
- Routed local stream-lab roots through `.env.stream-test.local` and the
  local `runtime/` directory, with a committed `.env.stream-test.example` and
  setup guide. The app repo now ignores generated local runtime output.
- Extended the patched Windows WebRTC installer with shared-preferences dev
  profile routing and optional native renderer frame diagnostics so stream
  validation can separate sender, receiver, renderer, and local profile state.
- Hardened follow-up review issues across call/session lifecycle and
  stream-test diagnostics: aggregate call-start listeners now emit, async
  Matrix/client callbacks guard closed state and stale indices, receiver-probe
  artifacts redact local IPC handoff details, and Android PiP aspect-ratio
  clamping was tightened for the supported Android range.

### Appearance And Themes

- Added Dark Matter as the new built-in dark default theme and Cosmic Stardust
  as an additional dark theme, while preserving Nebula, Sol, Eclipse, Aurora,
  Grand Master, and Dark Lord under their stable saved IDs.
- Custom theme selections now use a `custom:<id>` preference namespace. Existing
  custom themes whose IDs collide with new built-in IDs migrate to the
  namespaced selection, so an update cannot silently replace a selected custom
  theme with a newly shipped built-in theme.

### Media, Stories, And GIFs

- Added reduced-motion/accessibility handling for animated media surfaces so
  story, message, attachment, GIF, sticker, and preview paths can respect
  pause-animation preferences without removing the media affordance.
- Replaced inherited call and notification sounds with an original Inter
  Galactic sound pack by Renzo Mayo aka Renzo!. Android notification raw sounds
  were regenerated from the new masters, release provenance now points to the
  Renzo sound-pack evidence, and the README includes public creator credit.
- Defaulted public GIF search to the managed Klipy relay at
  `https://api.ourgalaxy.space/klipy` without embedding a direct provider API
  key. Saved user relay/API-key settings still override the bundled relay, and
  release docs now describe the managed/unmanaged build controls.
- Reduced story image draft work during capture/import by generating preview
  canvases first and regenerating full-size output only when needed for upload
  or save. Story photo save now reuses the shared platform Photos helper, and
  an opt-in preference can auto-save successfully uploaded photo stories.
- Tightened desktop story recording camera selection and failure handling so
  device discovery/start failures clear loading state and restore the live
  preview instead of leaving composer controls locked.

### Calendar, Spaces, And Media

- Added accessibility and favorites-settings foundation work for v0.8.0,
  including accessible interactive regions, Tiamat control semantics coverage,
  settings navigation updates, and favorite-room category preferences.
- Bounded calendar event dialogs so recurring-event forms use a real scroll
  viewport in the app popup, and invalid Submit taps now show inline feedback
  instead of being silently ignored.
- Fixed shared LOD image loading so space banners with a cached low-resolution
  thumbnail still autoload the full-resolution Matrix media image instead of
  staying blurred or pixelated.

### Release And Platform Metadata

- Reviewed open Dependabot PRs and applied the safe CI-only workflow updates:
  `actions/checkout` now uses the pinned v7 SHA, and
  `subosito/flutter-action` uses the 2.23.0 pinned revision. Android
  Gradle/Kotlin/Gradle-wrapper and `intl_translation` updates remain deferred
  for coordinated toolchain validation.
- Advanced app metadata to `0.8.0+990`, refreshed app-facing public changelog
  notes for the current beta branch, and kept Android license/evidence outputs
  tied to the latest generated release evidence available in the repo.
- Advanced app metadata to `0.8.0+991` for the current call/noise review batch
  and aligned release-note/package-gate references to the staged build.
- Refreshed macOS project metadata and kept the
  managed GIF relay behavior wired into `build_release.dart`.
- Aligned release/security docs with the owner-selected native DeepFilterNet
  path for the current Windows package candidate. The Windows CMake bundling of
  `df.dll` plus `DeepFilterNet3_onnx.tar.gz` is intentional for that candidate,
  but production release remains gated on final package/source archive proof,
  notice-surface verification, and local-only privacy validation.

## v0.7.4 (In Progress)

Build date: 2026-06-13

Version boundary: v0.7.4 starts after the app version advanced from
`0.7.3+984` to `0.7.4+985`. v0.7.3 release-cycle history continues below.

### Messaging, Rooms, And Notifications

- Restored categorized space room ordering so room order inside each category
  follows the current Matrix space-child order, while category membership
  remains in the Inter Galactic custom category state event. The space summary
  reorder surface now saves category-local drag order through the existing
  Matrix child-order path and mirrors the saved order to the local sidebar
  preference.
- Removed nested-space creation from the space summary add-room picker so that
  flow offers normal room types without exposing a broken nested-space option.
  Top-level space creation through the side rail remains available.
- Hardened thread attachment and deletion refresh behavior. Attachment-only
  thread sends no longer report a false send failure when the upload succeeds,
  text thread sends still aggregate into the root timeline, and tracked thread
  replies keep refreshing after a later redaction removes their relation data.
- Preserved recent volatile social URL-preview thumbnails in a short-lived
  transient cache field while keeping durable metadata sanitized. This lets
  recent social previews survive room reentry without treating expiring CDN
  thumbnails as long-lived durable preview data.
- Cleared desktop native notifications when remote read sync removes matching
  Desktop Companion entries, so sidebar/main chat state, the companion overlay,
  and Windows notification-center state can converge after reading a room on
  another device.

### Diagnostics And Crash Reporting

- Tightened pending-crash report boundaries so ordinary app-zone and platform
  dispatcher runtime errors stay in diagnostic logs without creating a
  next-launch critical crash prompt. Fatal startup and unhandled headless or
  background entrypoint failures still create pending crash reports.
- Snapshotted active call sessions and streams before applying mute,
  push-to-talk, deafen, and speaker-volume effects so LiveKit stream churn
  cannot mutate the collection during per-stream audio control updates.

### Calls And Streaming

- Advanced the DX11 gameplay streaming review branch through native NV12
  sender-handoff diagnostics and source-adapter validation. Two BG3 Smooth
  1280x720@30 live runs crossed the average 720p30 gate with visible output,
  clean network basics, native NV12 failures at zero, CPU-I420 fallback at
  zero, and source-adapter drops at zero; remaining productization work stays
  focused on classifier/report nuance and native tail-spike attribution.
- Added stream-test sender handoff diagnostics for the live D3D11 game-hook
  boundary, including WebRTC OnFrame timing, native NV12 readiness/fence
  counters, VideoBroadcaster and VideoStreamEncoder timing, Media Foundation
  native-input timing, encoded-callback timing, and sender drop counters.
- Added local stream-lab isolation wrappers for native capture to Media
  Foundation, WebRTC source OnFrame delivery, native sender handoff comparison,
  and dummy NV12 live-sender validation. Dummy NV12 stream-test configs now
  emit `config.gameCaptureSourceMode=dummy-nv12-live-sender` alongside
  `dummyNv12LiveSender=true` so durable reports distinguish generated NV12
  sender isolation from BG3/helper proof.
- Tightened CodeRabbit follow-ups for stream diagnostics docs and wrappers:
  failed native sender wrapper runs no longer resolve historical reports,
  stream archive wording now matches the current readiness-policy terminology,
  URL-preview diagnostics policy no longer allows logging target hosts, and
  explicit zero-FPS live sender evidence now counts as degraded instead of
  passing the sustained-FPS gate. Passing native sender wrapper statuses now
  exit explicitly with code 0.
- Added the Windows stream-test dummy NV12 live-sender mode and source
  placeholder selection path so the existing LiveKit/WebRTC/Media Foundation
  sender can be tested with generated native NV12 frames without launching or
  proving a game-helper capture target.
- Confirmed the Dennis RNNoise sample replay matrix for current production
  presets and fixed the replay wrapper so controls-plus-production runs no
  longer need a dummy experimental candidate table.

### Release Readiness

- Scrubbed public-mirror path fixtures and debug defaults after the user
  approved keeping the test fixtures and likely decision items while replacing
  maintainer-local paths. Stream-lab and game-capture defaults now use
  repo-relative paths, the live stream-lab harness supports
  `INTERGALACTIC_STREAM_LAB_DIR`, Emojibase regeneration notes use
  placeholder workspace-cache paths, and path/redaction/story/update/stream
  tests use repo-friendly fixtures while preserving Windows-style placeholder
  path coverage. Focused validation passed outside the Dart/Flutter sandbox.
- Replaced personal-looking placeholder Matrix identities and workstation
  fixture labels in public-mirror-facing tests and the developer mobile preview
  with neutral sample values before mirror publication. This does not change
  real account identity, homeserver selection, notification behavior, or
  runtime privacy defaults.
- Addressed PR #41 CodeRabbit release-readiness comments by removing
  workstation-specific staging and mirror paths from the v0.7.4 release record,
  correcting the `0.7.4+986` iOS/TestFlight wording to "waiting for upload"
  until App Store Connect evidence exists, and broadening Android evidence
  report path redaction so Windows, WSL, and Linux-style `file:///...` URIs
  normalize to public redacted file references.
- Refreshed the iOS/TestFlight candidate to `0.7.4+986` after the user-reported
  Apple export-compliance guidance changed the required plist route. Runner now
  declares `ITSAppUsesNonExemptEncryption=false`, the Broadcast Extension build
  number matches `986`, and the release record distinguishes this iOS candidate
  from the already-published Windows/Android `0.7.4+985` artifacts. Matrix E2EE
  and runtime encryption behavior are unchanged.
- Reconciled the final `0.7.4+985` release-blocker wording after S&C completed
  its prerelease pass. The current website/TestFlight rollout now treats
  third-party notice/provenance evidence, notice access, rollback proof,
  runtime redaction, Windows unsigned/untrusted consent, and current S&C
  findings as closed or explicitly accepted/deferred for this scope. Push
  provider payload proof, public App Store metadata, advisory-alert coverage,
  counsel/legal review, public GitHub visibility, and release.bat rollback
  archive automation remain future or post-release follow-ups rather than
  pre-publish blockers.
- Prepared the public `v0.7.4` changelog for build `v0.7.4+985` and mirrored
  the current public-safe release-note entry into the app repo
  `PUBLIC_CHANGELOG.md` for source archives/public repository readers. The
  release-batch extraction rule now produces a non-placeholder
  `dist/updates/changelog/v0.7.4.md` output headed
  `# Inter Galactic v0.7.4 Beta`. Final package/source archive generation still
  needs a rerun after changelog/evidence freeze so the distributed artifact set
  includes this release-note state.
- Reconciled the Android `0.7.4+985` release evidence after the user-run
  Android release build. The APK hash matches the dry-run checksum, Gradle
  runtime evidence is complete for 171 modules with 0 missing records, FCM
  evidence covers 7 packages with 0 missing license files, and the Google OSS
  baseline records 3 generated files, 228 parsed notice names, and 229
  dependency modules. The Android evidence collectors now emit UTF-8 without
  BOM using LF line endings, and the OSS baseline collector normalizes local
  Gradle report file URLs to public redacted file references. The final
  package/source archive still needs a rerun after evidence freeze so the
  source archive includes this reconciliation.
- Made Windows Release packaging fail closed when the approved story-export
  FFmpeg tool pair is not staged. The Windows CMake install step now hard-fails
  Release configuration/install packaging without both `ffmpeg.exe` and
  `ffprobe.exe` under `intergalactic/windows/third_party/ffmpeg/bin/`, while
  non-Release builds keep a warning-only path so developer PATH fallback remains
  available for local testing. Rebuilt Windows packaging/story-export smoke is
  still required before closing the release gate.
- Recorded the owner-provided App Store Connect privacy-label screenshots from
  2026-06-14 in the app privacy inventory and public release tracker. The
  labels declare linked Identifiers, User Content, and Search History;
  not-linked Diagnostics plus unlinked User Content; and the collected data
  types User ID, Device ID, Emails or Text Messages, Photos or Videos, Audio
  Data, Other User Content, Customer Support, Search History, Crash Data,
  Performance Data, and Other Diagnostic Data. A follow-up Audio Data
  screenshot shows Audio Data linked to the user's identity and used for App
  Functionality, so the App Store privacy-label tracker item is now closed.
  Encryption export, notice-surface exposure, rebuilt Windows FFmpeg
  story-export smoke, push payload verification, rollback proof, and
  public-GitHub exposure settings remain separate owner/release gates.
- Completed the S&C final release-readiness cleanup pass over public licensing,
  security, privacy, and compliance docs. The pass redacted remaining
  maintainer-local paths from public release evidence, aligned support/abuse
  and App Store privacy-manifest status wording with the public release
  tracker, added direct README links to privacy/terms/community/abuse docs, and
  kept remaining owner decisions explicit for notice-surface exposure, rebuilt
  Windows FFmpeg story-export smoke, encryption-export answers, push payload
  verification, rollback proof, and public-GitHub exposure settings if that
  channel enters scope.

### Calls And Streaming

- Added the host-load sampler startup/cleanup budget to the stream-test
  runner's automatic batch timeout calculation so customized sampler timeouts
  are not cut short by the outer batch guard.
- Hardened call media teardown and startup edge cases for the current review
  branch: LiveKit audio visualizer plugin failures are logged without breaking
  call audio, iOS ReplayKit screen-share startup rolls back if no screen-share
  video publication appears, direct Matrix/WebRTC video renderer initialization
  errors no longer leave the call UI in a spinner-only state, and the stream
  test runner records fresher native frame-drop/overwrite timing evidence for
  capture and delivery pacing analysis.

### App Surface

- Added hosted feedback and third-party-notice links to Help/Policies and
  Settings search so the public website feedback form and release notice bundle
  are reachable from the app without attaching diagnostics.
- Renamed the login shader wrapper from the old Star Trails naming to the
  project-owned Constellation background path after replacing the imported
  shader provenance risk.
- Improved calendar event editing by keeping recurring submissions anchored to
  their start weekday/month day, showing a retryable save failure message, and
  allowing the event editor content to scroll on constrained surfaces.

---

## v0.7.3 (In Progress)

Build date: 2026-06-01

Version boundary: v0.7.3 starts after the public `v0.7.2+980` release. New
agent work should be recorded under this section instead of extending the
completed v0.7.2 release cycle.

### Release Readiness

- Removed the failed RNNoise WAV bug-report submission feature after review.
  The app no longer exposes Audio WAV test report templates or Report WAV
  actions, RNNoise WAV capture summaries stay local-only, bug-report payload
  generation omits audio attachments and `rnnoise_wav_artifacts` metadata, and
  the server mirror rejects `audio/wav` attachments again. Privacy, support,
  architecture, and public-release notes now describe WAV/audio diagnostics as
  local developer artifacts rather than bug-report uploads.
- Generated the S&C third-party license and asset provenance evidence bundle for
  `v0.7.3+984`: `docs/release/THIRD_PARTY_LICENSES.json`,
  `THIRD_PARTY_NOTICES.md`, `ASSET_PROVENANCE.md`,
  `LICENSE_AUDIT_REPORT.md`, and `LICENSE_RELEASE_CHECKLIST.md`. The pass
  accounts for the Commet AGPL/fork notices and records the app icon as
  project-owner-created per user confirmation. The tracker stays open for
  owner decisions on native/mobile notices, incomplete asset provenance, and
  complete app/release notice access.
- Classified the submitted `v0.7.3+984` URL-preview privacy gate: encrypted-room
  previews default on, use Matrix homeserver preview API first, and have no
  Inter Galactic preview endpoint evidenced in release logs/default source.
  Provider-limited direct fallback remained guarded for supported public
  providers. This historical classification is superseded for current release
  candidates by consent-aware encrypted-room preview gating and default-off
  behavior for new installs.
- Fixed BUG-224 locally by redacting Matrix API request URLs as
  `[MATRIX_API_URI]` and covering URL-encoded Matrix identifiers in the central
  log redactor. Focused redactor tests and targeted analyzer passed, and S&C's
  fresh Call Diagnostics support-artifact scan closed the separate BUG-210
  WebRTC diagnostics redaction gate. Rebuilt crash/report resampling remains
  required before closing BUG-224.
- Updated the root Code of Conduct for public GitHub readiness: removed the
  remaining Commet enforcement contact, aligned attribution with Contributor
  Covenant 2.1, and clarified that the policy applies to Inter Galactic
  project-maintained spaces such as GitHub issues, pull requests, discussions,
  documentation contributions, official support channels, and maintainer-run
  events or accounts. Independent Matrix homeservers, rooms, spaces, DMs, and
  communities remain governed by their own homeserver, room, or community
  administrators.
- Tightened CodeRabbit plugin/native review coverage before merging PR #37:
  `.coderabbit.yaml` now has dedicated instructions and explicit path filters
  for `plugins/intergalactic_game_capture/**`,
  `plugins/intergalactic_noise_suppression/**`, plugin Windows native code, and
  plugin tooling so streaming/RNNoise/game-capture changes receive first-class
  review instead of relying only on broad shipped-code coverage. REVIEW also
  expanded the final merge gate to cover plugin Dart APIs/tests and the
  in-repo `tools/stream-lab/**` plus `tools/game-capture-target/**` validation
  surfaces while excluding generated plugin/tool build outputs from review
  noise.
- Prepared public release-readiness surfaces for CodeRabbit review: refreshed
  README, SECURITY, CONTRIBUTING, GitHub issue/PR templates, CodeRabbit path
  instructions, and read-only GitHub workflow permissions for beta release
  audit coverage.
- Fixed the PR security-review workflow for public-repo readiness: the
  repo-owned security gate now finds the required release gate filenames in the
  release checklist, and GitHub Dependency Review now defaults on for public
  repositories while staying opt-in for private/unsupported repositories through
  `ENABLE_DEPENDENCY_REVIEW=true`.
- Opened the next local development/review boundary by bumping the app identity
  and MSIX identity beyond the released `v0.7.2+980` artifact. The current
  local review build identity is `0.7.3+982`; this boundary remains
  intentionally local-only until the next release-cycle sync.

### Development Tooling

- Added a docs/changelog secret-scan GitHub workflow for public-release
  hygiene and archived stale planning documents out of the public app repo.
  Current architecture/design docs now point to implemented guidance instead
  of completed plan files, and the RNNoise tuning baseline lives under
  `docs/architecture/`.
- The debug-only D3D11 game-capture POC helper now fails closed when remote
  hook loading times out, fails, or does not leave the hook DLL loaded in the
  target process, preventing misleading successful local capture result folders
  when injection did not actually attach.
- Stream-test diagnostics can now compare window-GDI capture methods for
  window sources and reject faster methods that only return black or
  low-variance output. This remains diagnostic-only and does not change normal
  stream defaults, bitrate, codec, fallback, or LiveKit publishing behavior.
- The patched-libwebrtc installer now requires the window-GDI diagnostic API
  before accepting a native artifact, so local Windows test builds fail fast if
  the stream-test method selector cannot reach the native capturer.
- Video-only desktop share sessions now still resolve Windows process metadata
  for PID-based stream-test automation without enabling shared-content audio,
  and game-hook readback-drop scoring now requires corroborating latency,
  ratio, or frame-gap evidence before it becomes a high-confidence
  frame-pacing diagnosis.
- Custom navigation shortcuts persist fallback hotkey metadata with the
  shortcut definition, allowing call-room hotkeys to restore after debug app
  restarts even when the separate system hotkey preference is missing.

### Review / Reliability Hardening

- Addressed the plugin-aware PR #37 CodeRabbit follow-ups: the story capture
  control restores Enter/Space activation while preserving press-and-hold
  recording, video story drafts merge visual mention overlays into uploaded
  mention metadata, story fallback routing preserves notification versus normal
  open origin, the iOS story fallback test now asserts the queued story request
  carries the fallback room route, occurrence-only recurring calendar deletes
  remain visible, patched-libwebrtc backup failures report all exhausted
  strategies, RNNoise replay sample rates are bounded before fixture
  generation, and the D3D11 game-capture hook publishes captured-frame sequence
  indices instead of Present counts so intentional throttling does not inflate
  missed-frame diagnostics.
- Addressed the next plugin-aware PR #37 CodeRabbit follow-ups: story media MXC
  parsing now rejects malformed URIs without authority/media ids, story video
  controllers are disposed when the viewer swaps or closes stories, desktop
  story video trimming no longer invokes FFmpeg through a Windows shell, the
  D3D11 helper guards invalid `--hook-target-fps` input, and the RNNoise replay
  script rejects ambiguous `-InputPath` plus `-Fixture` runs.
- Addressed remaining plugin-aware PR #37 CodeRabbit summary follow-ups before
  merge: dependency-review now defaults on for public repositories while staying
  opt-in for private/unsupported repositories and can still be explicitly
  disabled, video
  story notification docs include the canonical video event type, demo video
  stories preserve their configured background color, optimistic uploaded video
  stories use parsed Matrix video providers when available, video story rooms are
  included in sendability refresh, shared video players rebind listeners when an
  external controller changes, native story recording stops are serialized, story
  video pick/import continues through per-file failures, notification story
  retries preserve deep-link fields before client readiness, patched-libwebrtc
  rollback avoids stale backups from failed pre-extraction runs, the game-capture
  hook tolerates malformed integer config, RNNoise replay fixtures require
  caller-validated sample rates, calendar recurrence edits clone submit-time
  rules, and client manager tests close clients through tear-down.
- Addressed the final still-valid PR #37 CodeRabbit threads before merge:
  shared video player controller APIs no longer force-call nulled callbacks
  after disposal, desktop story video FFmpeg exports now kill timed-out child
  processes before partial-output cleanup, and the video-story composer test now
  proves visual mention overlays are included even when no explicit mention list
  is passed. The story capture button also keeps hold-record end/cancel
  callbacks wired after recording starts so release/cancel can stop the active
  recording.
- Stabilized the Developer Logs -> Report Issue bug-report dialog handoff in
  PR #37 CI by removing an intrinsic-layout-sensitive `LayoutBuilder` from the
  desktop report dialog content sizing path. The dialog still sizes to the
  available desktop window, but focused Flutter tests no longer risk rendering
  only the popup title during static-analysis.
- Addressed PR #37 CodeRabbit second-pass follow-ups: video players no longer
  restart when only presentation fit changes, autoplay intent is passed through
  first-frame decoding, story retry cursors now advance only after fully
  delivered uploads, the desktop bug-report dialog sizes against available
  constraints, and the stream optimization report header reflects the latest
  June evidence.
- Addressed PR #37 CodeRabbit follow-ups across video stories, stream
  diagnostics, report dialogs, and the compact calendar editor. Story media and
  overlays now reject invalid/non-MXC payloads earlier, video-story retry
  upload state tracks photo and video queues separately, player/error lifecycle
  paths reset cleanly, unknown Windows window titles fall back to the safer
  compatibility path, public architecture docs no longer expose workstation
  paths or exact build fingerprints, and calendar delete/submit actions guard
  null events plus post-dispose async UI work.
- Addressed CodeRabbit public beta release-readiness follow-ups by sanitizing
  workstation-local paths from public app docs, normalizing the MSIX identity to
  the required dotted version format, and tightening reviewed edge cases in
  Matrix activity presence, lifecycle presence retries, encrypted history
  sharing, stream-test automation, screen-share metadata, helper teardown, and
  custom shortcut persistence.
- iPhone story photo-library import now uses the native image picker with
  bounded JPEG quality before draft normalization, so camera-library HEIC/HEIF
  photos do not fail with the generic "could not add these photos" banner while
  screenshots still succeed. Desktop/web story album picks keep the existing
  FilePicker path, and failed story photo imports now emit a redacted
  `media/stories` diagnostic for future bug reports.
- Addressed GitHub CodeRabbit follow-up findings across rich presence,
  notification snooze cleanup, account recovery settings, URL preview durable
  cache behavior, iOS ReplayKit activation results, receive-quality muting,
  encrypted chat-open retry cooldowns, history-sharing target validation, room
  member saves, story uploads, and secret redaction. The fixes are intentionally
  scoped to current review comments and validated with focused analyzer and
  Flutter tests.

### Activity / Rich Presence

- Matrix activity presence now honors Matrix `M_LIMIT_EXCEEDED` / HTTP 429
  retry-after responses. When Synapse asks the app to wait, the publisher
  defers future writes until that window, coalesces newer Spotify/Steam emits
  to the latest requested status, and stops the current multi-account
  publish/clear pass after the first rate-limit signal instead of immediately
  trying every account again.
- Matrix presence writes now use the authenticated Matrix session user id when
  available and log rejected `setPresence` attempts with compact redacted
  diagnostics: hashed user id, status mode, status-message length, Matrix
  errcode/HTTP status, and sanitized error text. The diagnostic path preserves
  retry/failure behavior while avoiding raw status summaries or Matrix ids in
  logs.
- Matrix activity presence cleanup now uses a persisted last-published summary
  marker instead of a broad summary-shape heuristic, so Inter Galactic clears
  only statuses it can prove it wrote and preserves user-authored statuses such
  as "Playing guitar".

### URL Previews

- Durable social-preview thumbnail refresh now retries the direct provider path
  without re-running the Matrix/server preview fetch when cached metadata is
  still usable but the volatile thumbnail cannot be restored after restart.

### Rooms / Calls

- Matrix room role saves now strip immutable room-version-12 creator entries
  from `m.room.power_levels` before writing member role changes, reload member
  state after save, and keep custom power levels distinct from built-in role
  buckets.
- Room display-name permissions now follow the configured Inter Galactic state
  event write level directly, so rooms that intentionally allow members to edit
  display names do not hit a stale local moderator/redaction gate.
- Forum/thread timelines now delegate read-marker updates to their parent room
  timeline so opening a thread can clear the containing room unread state.
- iPhone ReplayKit screen share setup now declares the matching app group and
  routes broadcast activation through the publish path with logged failures,
  avoiding duplicate picker activation before LiveKit publishes the track.

---

## v0.7.2 (Released)

Build date: 2026-05-30

Version boundary: v0.7.2 covers the remaining dirty-diff review split after
the DM stories PR. Older v0.7.0/v0.7.1 notes remain historical release-cycle
context below.

### Release Readiness

- QA aligned desktop auto-update validation wording in the release test matrix
  and testing docs. Windows update checks now distinguish trusted signed
  installers from the approved open-source unsigned consent fallback, including
  HTTPS plus SHA-256 verification, Authenticode `Valid` for the trusted path,
  explicit `allow_unsigned_auto_update` plus user approval for unsigned or
  untrusted installers, and clean cancellation behavior.
- Multi-account focus now restores after restart. If a user switches from the
  merged account view to one account, the main shell and side rail retry the
  saved `filter_client_id` as Matrix clients finish restoring and keep the app
  scoped to that account on reopen.
- REVIEW split the remaining dirty diff onto a fresh `origin/main` branch after
  the DM-scoped stories PR merged, excluding stale story-overlap source files,
  local `.vscode` state, and the iOS handoff source archive from the new PR.
- iOS push notification recovery now forces Matrix pusher reconciliation after
  APNs token refresh/registration callbacks and adds same-install APNs
  stale-pusher coverage.
- Login, composer, settings, shortcut, and timeline polish are carried forward:
  the sign-in form now supports show/hide password, bracket typing support is
  wired through preferences/tests, and mobile/timeline obstruction handling has
  matching utility coverage.
- RNNoise and call-audio diagnostics are staged for CodeRabbit/CI review with
  capture-profile preferences, native diagnostic directory handling, replay
  tooling, WASAPI sidecar capture scaffolding, and focused service/profile
  tests.
- REVIEW addressed PR follow-up on the remaining dirty-diff split: direct
  WebRTC capture constraints now preserve RNNoise 48 kHz/mono optional hints,
  tap-order AGC diagnostics are distinct, diagnostic hook overrides clear on
  service dispose, malformed LiveKit focus data falls back safely, call view
  async callbacks guard unmounted state, desktop popouts use stable tile IDs,
  and composer bracket spacing only exits an actual bracket pair.
- Release/readiness documentation now records the v0.7.1+978 artifact review,
  build-signing expectations, settings architecture updates, iOS handoff notes,
  and native media/plugin boundaries.

---

## v0.7.0 (In Progress)

Build date: 2026-05-05

### Release Readiness

- DM-scoped 24-hour photo stories are implemented and smoke-tested: Home now
  shows story rings for existing DM contacts, supports encrypted Matrix media
  delivery in encrypted DMs, hides story custom events from normal timeline and
  badge surfaces, and lets users view, mark seen, delete, and expire stories
  through the Home story UI.
- REVIEW CodeRabbit follow-up on DM stories: story deletion now keeps retry
  outbox state until every redaction succeeds, picked-photo thumbnails decode
  at display size, the viewer timer waits for the current image to resolve,
  Home status accessibility copy is localized, demo uploads mirror the real
  size guard, and story-driven DM/space badge refresh listeners stay bounded.
- REVIEW CodeRabbit follow-up on PR #25: invite acceptance no longer fails when
  optional shared-history import fails after a successful join, password-reset
  and encrypted-history HTTP probes now time out instead of hanging, mobile
  share/download UI state resets on failures, shortcut room opens no longer
  look like notification opens, and call diagnostics avoid logging raw call URLs.
- REVIEW dirty-diff startup fixes: invite components now cancel their client
  sync listener during disposal, Android FCM pusher migration treats missing
  `data_only` format as stale instead of already migrated, and notification
  room-open retry diagnostics hash the room target before logging.
- Desktop message input keeps focus after sending a message, so users can send
  with Enter and keep typing without re-clicking the composer. The mobile
  keyboard-unfocus behavior is unchanged.
- LiveKit local mute and bug-report preview hardening: remote participant mic
  volume/mute overrides now survive participant joins and LiveKit stream object
  refreshes while the call view is active, and Report a Bug preview generation
  now guards recursive/deep diagnostic metadata before JSON preview or upload
  encoding.
- Mobile focused media now adds app-native controls over focused images:
  close, quick react, reply, native share, and a photo-room thread shortcut.
  Mobile photo-room stack taps open the swipeable stack viewer first instead of
  going straight to comments, while desktop photo-room behavior is unchanged.
- REVIEW follow-up fixed two dirty-diff review findings: Android FCM pusher
  cleanup now classifies globally stale legacy app IDs and URL push keys before
  same-install matching, and stream-test frame pacing now counts zero-delta
  counter windows as stale sampled gaps so freezes affect p95/max interval and
  average FPS evidence. Focused regression tests were added for both paths.
- Favorites and iPhone media/report polish: Favorites banner images now render
  contained instead of being cropped again by the header, iPhone image
  attachment downloads save through the native Photos add-only bridge while
  non-images still use Files, and the Report a Bug form adds mobile
  keyboard-aware padding plus dismiss controls so Preview/Submit stay reachable.
- Streaming review fixes are addressed for the PR handoff: Windows adaptive/live
  screen-share republish now clears screen-share state when a replacement
  capturer fails after the previous Windows video sender was stopped, window
  publish diagnostics keep the source-adjusted single-layer profile for window
  shares, and stream-test JSON/Markdown reports now parse native
  `native_window_rect`, `content`, and `canvas` geometry markers. Focused VoIP
  streaming tests and targeted dirty-file Flutter analysis passed with
  workspace-local AppData.
- URL preview direct fallback is now provider-limited: TikTok, Instagram, and
  Reddit can still use client fallback when a homeserver lacks useful preview
  support, but generic arbitrary-host URLs now rely on the optional Inter
  Galactic preview service and the Matrix homeserver preview API instead of a
  direct client fetch.
- Remaining non-streaming PR #14 CodeRabbit threads are addressed: developer
  fake-notification actions now fail closed without a signed-in room, Steam
  artwork URLs accept only HTTP(S), demo encrypted-room and photo-album
  lifecycles are aligned, biometric recovery-key writes handle missing native
  plugins, direct URL preview fallback validates resolved DNS addresses, Matrix
  redaction covers homeserver ports, and emoji/GIF picker nits are fixed.
  Streaming/call work remains intentionally untouched.
- Focused PR CI fallout is now cleaned up: direct URL preview fallback timeouts
  no longer throw when a provider returns a non-nullable preview future, timeline
  scroll callbacks ignore detached controllers during tutorial teardown, and the
  newly routed focused tests match the current demo local-media/emoticon data.
- The GitHub security-review workflow now keeps the GitHub Dependency Review
  advisory job behind `ENABLE_DEPENDENCY_REVIEW=true`, because the current
  repository reports Dependency Review as unsupported. The repo-owned
  `security-review.py` gate remains required on pull requests.
- URL preview direct fallback now applies the same privacy boundary before
  document, JSON, HTML, thumbnail, and redirect fetches. Unsafe schemes,
  localhost and `.local` style hosts, metadata-service hostnames, and
  private/link-local/reserved literal IP ranges are rejected before the durable
  cache can persist preview metadata.

- `launch_intergalactic_detached.ps1` now uses Task Scheduler run level
  `Limited` for the non-elevated detached desktop launch path. This fixes the
  previous `LeastPrivilege` enum mismatch that caused the build menu to fall
  back to shell launch when started from Desktop/taskbar shortcuts.
- REVIEW closed the Stable Diagnostic Logging and Hot Reload Layout Hardening
  coordination items after confirming the diagnostic logging boundary stays
  redacted/bounded and diagnostics-only, and accepting the final Windows
  hot-reload summary with two completed reloads, no exceptions, and no lost
  device connection.
- `release.bat` now publishes desktop-only by default and only includes
  Android/mobile artifacts when `--include-android`, `--all`, or
  `--auto-android` is selected. `build_menu.bat` exposes that release-scope
  choice before running release packaging, and its post-build desktop launch
  now uses a one-shot Windows Scheduled Task so shortcut-launched build menus
  do not keep the app tied to the command window.
- Workspace-root `build_menu.bat` now provides a local interactive
  build wrapper for desktop, Android, web, or all-target runs. The wrapper asks
  whether the run is for release packaging, keeps desktop version ownership in
  `build.bat` so the bump prompt still appears, can run `release.bat` after the
  selected builds, and can launch the newly built desktop executable from
  `Desktop_Builds`. The launch path now delegates to the workspace-root
  `launch_intergalactic_detached.ps1` helper, which starts the
  executable through Task Scheduler and keeps shell launch only as a
  last-resort fallback.
- Workspace-local release identity consistency is now enforced before local
  build/package work. Windows, Android, web, and release packaging entrypoints
  call `intergalactic/scripts/verify_release_identity.ps1` against full
  `vX.Y.Z+build`; web bundles embed the full tag; Android/iOS helper builds
  pass the build metadata as the mobile build number; the iOS Broadcast
  Extension project fields are aligned with `pubspec.yaml`; and release
  manifests/artifact filenames are checked before upload.
- REVIEW confirmed the remaining `dist` artifacts pass the artifact-mode
  security review after the scanner-flagged source archive was removed. Signed
  release automation stays workspace-local for now, and the next release
  pipeline task is release identity consistency across pubspec, local scripts,
  artifact names, update manifests, diagnostics, and store/version fields.
- PR static analysis now includes path-aware focused Flutter test routing.
  `.github/scripts/resolve-focused-tests.sh` maps changed app/test paths to
  targeted focused test files, validates selected tests exist, emits GitHub
  `count`/`path` outputs, and makes unrelated documentation-only PRs a
  no-op for Flutter tests. Dependency or CI routing changes run the full
  configured focused test set.
- REVIEW closed three follow-up findings from the non-call/stream pass. URL
  preview metadata can no longer retarget preview taps to a different host,
  iOS biometric recovery-key status now flags stored keys that are no longer
  readable after biometric-state changes, and CI routing-file changes now run
  the configured focused suites instead of the whole Flutter test tree.
- REVIEW spot-checked the new app-side architecture, release, testing, and
  product docs against current app paths, release scripts, diagnostic logging
  code, and media/message-effect code. The pass added message-effect coverage
  to the media pipeline, clarified workspace-level operations/security runbook
  ownership, refreshed app doc-folder/plugin discovery, removed empty duplicate
  app-side operations/security placeholders, and closed the architecture and
  QA/test documentation review queue items.
- QA added a dedicated testing workflow under `docs/testing/`, extended the
  release test matrix with platform/device and high-risk regression gates, and
  added focused regression coverage for screen-share scaling, onboarding
  persistence edge cases, and activity visibility/preferred-source reset
  behavior. Focused Flutter tests, focused analysis, formatter, and
  `git diff --check` passed.
- Release management documentation now has a dedicated `docs/release/`
  runbook set covering the release checklist, rollback plan, artifact and
  `latest.json` validation, release test matrix, versioning policy,
  build/signing flow, and release-notes template. The existing release-targets
  architecture note now links to the detailed release docs.
- Help -> Report a Bug now builds a redacted JSON diagnostic payload, lets the
  user toggle logs and diagnostics, previews exactly what will be sent, asks
  for confirmation, and submits to
  the configured support API endpoint. Developer Logs
  exception rows use the same reporter, fatal startup details copy through the
  bug-report redactor, and `docs/architecture/bug-reporting-flow.md` documents
  the privacy and payload boundary.
- Help -> Report a Bug upload handling now bounds included logs to a recent
  redacted tail before preview/upload, applies recent-log byte caps to
  in-memory plus file logs, and records redacted `app/bug-report` diagnostics
  for server rejection or transport failures. Redaction now also covers JSON
  Authorization headers, proxy Authorization headers, and camelCase token
  fields without growing already-redacted values on a second pass.
- Help -> Report a Bug now targets a 90 KB total JSON payload cap after live
  logs showed the correct endpoint rejecting a 102 KB report with HTTP 400.
  Included logs default to 64 KB and are trimmed again when metadata would push
  the encoded payload over the cap; detailed diagnostics are omitted as a last
  resort with an explicit placeholder. The previewed JSON also includes flat
  support-intake fields such as `title`, `description`, `message`,
  `app_version`, and `platform`, and rejection logs now include a short
  redacted server response message.
- Help -> Report a Bug now matches the `intergalactic-api` attachment
  contract. Redacted logs and diagnostics are sent as JSON attachment entries
  with `name`, `mimeType`, and `contentBase64` instead of preview-only summary
  rows, empty log attachments are omitted, API camelCase field aliases are
  included, and successful API responses display the returned `reportId`.
- Log-derived Matrix activity hardening now retries failed Matrix activity
  presence publish/clear attempts with bounded backoff, so a transient
  `setPresence` failure does not leave an app-owned `Playing ...` status stuck
  forever. Lifecycle presence, read markers, space hierarchy refreshes, and
  widget relation reads now contain transient Matrix API failures with
  categorized diagnostics. Optional Steam and URL-preview provider fetch misses
  now stay in verbose diagnostics instead of filling stable logs as errors.
- URL previews now keep event-cache state separate from a sanitized durable
  normalized-URL cache, so stable desktop sessions can reuse previews after
  restart without persisting Matrix event contents or token-bearing URLs. Valid
  entries use a five-day TTL, stale entries render while refreshing in the
  background, invalid sentinels cache briefly, the optional Inter Galactic
  preview service can be enabled at build time, and loading previews reserve
  the real preview-card shell to reduce timeline jumps.
- Desktop account popup surface layering now matches the AccountPopup
  reference: the popup shell uses `surfaceContainerLow`, activity and
  action/menu cards use `surface`, and the secondary stacked activity card uses
  `surfaceContainer`.
- Desktop composer, effects, attachment/poll popup actions, GIF picker active
  frames, and the account popup edge highlight now derive their highlight
  strokes from `ColorScheme.outline` so custom themes can adapt those chrome
  accents consistently. The design docs now record outline-token usage for
  desktop edge highlights and active frames.
- Composer plus, slash-command, and effects menus now use a
  composer-anchored overlay, so they sit over the chat timeline like the
  emoji/sticker picker instead of expanding the composer and pushing messages
  upward. The effects menu now matches the slash-command popup height and
  scrolls within that frame. Follow-up corrected the overlay child sizing so
  the visible popup card anchors directly above the composer instead of far up
  the timeline.
- The composer now has an effects menu: desktop gets a sparkle button beside
  emoji, while mobile opens it from long-press on the mic/send button. The menu
  exposes confetti, rainbow, snowfall, space invaders, hidden, loud, cuddle,
  googly, and hug using the existing slash-command/message-effect send paths.
- Desktop emoji/sticker/GIF picker search text now sits centered inside the
  desktop search bar, and the account popup panel has a stronger visible edge
  highlight around its outer boundary.
- Android voice messages now preserve the recorder-provided `audio/mp4` MIME
  type during attachment resolution, and `.m4a` timeline events are parsed as
  audio before video fallback so they render through the compact voice bubble.
  The desktop emoji/sticker/GIF picker search field now centers its text inside
  the search bar.
- Desktop user-bar clicks now open an anchored account popup with compact
  profile details, editable status, activity view, Edit Profile, and Switch
  Accounts/Add Account actions. Local Spotify/Steam activities can now rotate
  which source is primary, so the popup activity view and existing activity
  card can swap when multiple activities are active.
- Steam game activity now accepts proxy-provided game artwork/thumbnail URLs
  before falling back to deterministic Steam CDN artwork, emits a clear when
  Steam no longer reports an active game, and clears Matrix activity presence
  with an explicit empty status message so stale `Playing ...` text does not
  survive on the homeserver.
- REVIEW closed the user-verified integration queue items for Steam activity,
  desktop account popup/activity swap, desktop chat polish, audio voice-message
  bubbles, mobile app-emoji send state, and Room Nicknames settings. Streaming
  diagnostics and the Windows hot-reload/compiler smoke item remain open.
- The desktop account-popup artwork helper keeps data-URI image byte handling
  focused and analyzer-clean for activity/profile artwork.
- Windows `build.bat` now prompts before changing version metadata. Normal
  interactive runs can keep the current pubspec version, bump build metadata
  only, or bump patch/minor/major from the prompt; scripted runs can still use
  `--bump build|patch|minor|major` or `--no-bump`.
- Desktop chat UI polish now gives the composer a framed input bar, shows plus
  and slash-command choices as compact popup tiles, anchors a smaller
  emoji/sticker/GIF panel from the composer, reduces desktop sticker tile size,
  adds breathing room below the Room Members Nicknames button, and makes app
  scrollbars thinner so thumbs do not cover selected-row highlights. Follow-up
  polish added side breathing room and an edge highlight to the desktop
  composer, corrected emoji button spacing, fixed the picker overlay anchoring,
  shifted plus/slash popup styling toward desktop panel cards, and replaced
  Liquid Glass-style desktop highlights in the composer, plus popup,
  slash-command popup, and emoji/sticker/GIF picker with desktop panel borders,
  compact top picker tabs, and smaller desktop search/pack chrome. The latest
  pass removes the desktop send button, lowers and tightens the composer frame,
  moves emoji/sticker/GIF search into the pinned desktop picker header, adds a
  Create action that opens the current room's Emoticons settings, and gives the
  scrollable picker body stronger desktop section dividers.
- Audio and voice-message attachments now render as compact in-message voice
  bubbles with a play/pause button, generated waveform, duration label,
  message-tail alignment, and the existing `media_kit` playback path instead of
  the previous wide utility player panel.
- Mobile composer app emoji send-state now updates after picker insertion:
  programmatic composer text changes use the normal text-updated path so app
  emoji/sticker shortcodes switch the microphone button to send.
- Windows hot-reload disconnect follow-up: the captured `run_dev.bat` log
  showed hot reload completing successfully before the background task overlay
  threw an unbounded `RenderFlex` assertion and Flutter lost the device
  connection. Background task rows now shrink-wrap safely in unconstrained
  overlay placements while preserving expanding labels in bounded parents.
- Hot-reload log-noise hardening now awaits GUI emoji/localization/date
  initialization sequentially, treats missing calendar room state as pending
  state instead of throwing through `calendar!`, and defers timeline child-key
  updates through rebuild frames so reload/sync churn does not flood warnings.
- Web attachment download task status now treats successful browser
  byte-backed `FilePicker.saveFile` dispatch as completion even though the web
  plugin returns `null` after starting the download. Android/iOS cancellation
  detection still depends on a returned destination path.
- Public-release policy, support, abuse, App Store, and in-app Help & Safety
  contact surfaces now use `intergalactic@ourgalaxy.space` instead of the
  previous placeholder contact. The release checklist still requires manual
  confirmation that the inbox is monitored before public submission.
- The public-release readiness tracker now points to the moved workspace audit
  report at `docs/AUDIT_REPORT.md`.

### Onboarding

- REVIEW kept the guided tutorial desktop-only while the mobile tutorial path
  remains unfinished. Mobile layout now skips automatic tutorial launch, hides
  Settings > Help > Tutorial and its search entry, and shows a desktop-only
  notice if the tutorial page is reached directly. FAQ copy now points replay
  to desktop settings.
- First-run onboarding now appears after successful non-demo login/session
  restore, stores local versioned completion state, supports Skip/Finish, and
  can be replayed from Settings > Help > Tutorial.

### Design System

- Added the Inter Galactic design documentation set under `docs/design/`,
  converting `docs/plans/uiGuidelines.md` into durable guidance for visual
  principles, UI implementation rules, theme usage, layout/spacing standards,
  and reusable component patterns. REVIEW corrected stale component anchors and
  linked the design docs from the required app change guide and codebase map.
  No app behavior changed.

### Settings

- Room Settings now has a Matrix-room **Nicknames** tab that shows each
  member's normal display name alongside any room nickname, lets users set
  their own nickname when permitted, and enables moderator/admin edits for
  other members while dimming non-editable cards. The outside-settings Room
  Members pane now includes a pinned Nicknames button that opens the new tab
  directly.
- Mobile settings polish now keeps the Account & Profile account selector from
  clipping long developer account identifiers, and the Space Soundboard upload
  form stacks file guidance above action buttons on narrow screens so supported
  audio formats no longer render vertically.
- Settings UI overhaul is user validated from the DESIGN lane. Active DESIGN
  ownership is released and the completed settings integration items are ready
  for REVIEW handoff.
- Contextual settings polish now matches the app-level settings treatment more
  closely: Room/Space notification mode uses the three selectable cards,
  privacy overrides use compact dropdown selectors, soundboard upload/join
  sound rows, emoticon packs, permission rows, and draggable member lists use
  `surfaceContainerLow` cards, member scrollbars stay on the settings popout
  edge, and app/room Appearance exposes sent and received bubble colors on
  desktop as well as mobile.
- Room and Space Settings now follow the proposed contextual organization.
  Notifications contains notification mode, read receipts, typing indicators,
  and desktop sound overrides; Admin Settings contains identity, Matrix
  addresses, visibility, room events, and encryption where supported. Room
  Appearance is focused on room-local message background/bubble styling, and
  contextual search keeps legacy General/Appearance/Security aliases.
- Settings search now understands row-level settings entries instead of only
  category/tab labels. Search results can surface matching rows such as Read
  receipts, Minimize on close, Account State JSON, or Selected account while
  keeping aliases for moved/renamed labels like Privacy, Advanced, Manage
  Accounts, and Window Behaviour. Account Security also no longer wraps Cross
  Signing, Message Backup, and Run Decryption in an extra card.
- The App Settings Developer tab now uses the Developer localization key instead
  of the stale Advanced key, Developer places Account State JSON directly below
  Logs, Help & Safety cards now match the newer settings surfaces with a deeper
  red Block User action, and Account Security aligns Cross Signing & Backup plus
  Account Deletion with the current settings card design while leaving the
  Sessions list mostly intact.
- Phase 6 developer consolidation moved Logs and Developer Utils into
  collapsible App Settings > Developer panels, placed Developer Utils at the
  bottom of the Developer tools list, added descriptions for developer utility
  groups/actions, and moved Show call/stream stats into the Voice and Video
  developer controls.
- Settings polish follow-up centered the Emoticons quick-reaction slots,
  normalized Emoticons, Soundboard, Notifications, Desktop Companion, and
  Developer panel cards to `surfaceContainerLow`, and made Notification plus
  Voice and Video developer diagnostics collapsible under Developer. RNNoise
  diagnostics and Audio Processing now render in bordered status cards.
- Voice and Video now keeps everyday device, mic check, screen-share quality,
  and normal noise suppression setup in the main page. STUN fallback, RNNoise
  diagnostics/custom tuning, stream override controls, adaptive fallback,
  manual stream codec/bitrate/FPS/resolution controls, and WebRTC debug tools
  moved behind Advanced/Developer with existing preference keys and call
  runtime behavior preserved.
- Hot reload no longer trips the recent Settings layout assertions from
  unconstrained Tiamat text buttons and the Account & Profile two-pane
  scrollbar. Tiamat text buttons now shrink-wrap without flex children when
  width is unbounded, and the Account & Profile scrollbar no longer keeps an
  always-visible interactive thumb while hot reload temporarily reattaches the
  scroll view.
- Desktop App, Room, and Space settings now open in an adaptive overlay over
  the live app instead of replacing the whole window. The desktop settings
  shell adds overlay chrome, a close action, an account header, centered
  content width, and first-pass modernized toggle/slider/dropdown row patterns
  for core app settings while preserving the current settings IA and mobile
  full-page flow. A follow-up fixed the string option dropdown row syntax that
  could stop Windows builds during Flutter assemble.
- The desktop Settings overlay typography is now lighter and closer to the
  reference: section headings use normal 24px text, page/setting titles use
  normal 18px text, descriptions use 12px text, the main settings surface uses
  `surfaceContainer`, and the Check for updates row aligns with the rest of
  General. The shared section/row treatment now covers Appearance, Activity,
  Advanced, Voice & Video, Shortcuts, and Window Behaviour as well as General.
- Settings typography now uses the bundled Roboto Regular family throughout
  the desktop and mobile settings shells. The desktop sidebar uses
  `surfaceContainerLow`, the right content pane uses `surfaceContainer`, and
  the account header now shows the user's profile avatar with the existing
  initial fallback.
- The Experiments settings tab is now visible when experiment definitions are
  visible to the current user. The internal `Profile badge testing` toggle is
  developer-mode only and injects local Inter Galactic sample badges into the
  old Commet profile badge picker for testing only while developer mode is
  enabled, while real Commet badges still require the existing signature
  validation.
- Custom theme editing now opens as a larger Theme Workshop on desktop so edit
  controls and the live preview stay visible together. Mobile keeps the same
  draft state but uses swipeable Edit/Preview and preview sub-panes for narrow
  space. Preview selections now show token swatches with abbreviations, "On"
  color labels were renamed to clearer accent/text labels, and the color
  picker keeps hue/saturation stable while changing brightness.
- Default themes were refreshed with stable IDs preserved: Light is now Sol
  with Inter Galactic blue accents, Dark is now Nebula with darker blue
  accents, Amoled is now Eclipse with blue/teal link and code highlights, and
  the new dark Aurora theme is available. Light Side and Dark Side bundled
  themes are now Grand Master and Dark Lord, with legacy name aliases migrated
  so saved selections survive restart. The custom-theme starting point picker
  now includes all default themes and scrolls with the mobile token editor.
- Appearance settings now keep bubble-message and right-aligned-message
  toggles in the Message Appearance block on desktop and mobile, app icon
  previews use the rounded icon assets, and the Eclipse theme swatch reads as
  mostly black to match the theme.
- Activity settings now start with Spotify and Steam connection setup rows and
  render configured source cards with disconnect controls and source-specific
  toggles. Setup/configure opens a two-step instruction/input popout, Steam
  game activity now supplies Steam app artwork when available, Spotify/Steam
  cards prefer fetched account display names when available, and Windows App
  Settings has a new Desktop Companion tab for companion avatar and behavior
  preferences. The Activity setup/configure buttons now stay on one line, and
  the older duplicate companion controls were removed from Notifications.
- Settings reorganization Phase 3 continued with Emoticons and Soundboard.
  Emoticons now lives in App Settings with quick reactions, personal packs,
  favorite packs, and room/space pack discovery. Soundboard now has its own App
  Settings tab for local playback volume and joined-space soundboard discovery,
  and Voice & Video no longer duplicates the soundboard volume row. Windows
  shortcuts also gained a Toggle Desktop Companion target.
- Shortcuts now supports local custom room/space navigation targets. Users can
  enter a room or space ID, alias, or Matrix link, optionally scope it to a
  signed-in account, and assign a system-wide hotkey. Soundboard discovery cards
  now include a Manage action that opens the owning space directly to its
  contextual Soundboard settings tab.
- PR review follow-ups hardened settings and companion edge cases: push-to-talk
  key release now restores microphone safety state, notification/push/GIF and
  space banner async paths clear loading state on failure, room notification
  cards expose choice semantics, custom shortcut account scoping can be cleared,
  companion settings copy uses localization getters, and discovered emoticon
  packs now use collision-safe identity keys while favorite-toggle failures are
  surfaced instead of bubbling out of the settings UI.
- The custom room/space shortcut dialog now keeps text entry separate from
  hotkey recording. Label, target, and account fields no longer capture
  shortcuts until the user presses `Record shortcut`, and clearing a shortcut is
  explicit.
- Editing an existing custom room/space shortcut target no longer crashes the
  client. Re-saving the unchanged hotkey now leaves the current registration in
  place instead of unregistering and re-registering itself.
- A static Settings UI architecture map now documents the current settings
  entry points, desktop/mobile shells, categories, reusable components,
  persistence paths, platform differences, UX pain points, and overhaul risks
  at `docs/architecture/settings-ui-map.md`. No app behavior changed.
- Settings UI overhaul phase 1 now has a documented information-architecture
  baseline at `docs/architecture/settings-information-architecture.md`. Current
  Settings shells stay intact while future work uses defined everyday,
  account, support/about, advanced/developer, and room/space groups plus risk
  tiers and space-specific copy policy. No app behavior changed.
- Settings now has a desktop and mobile search field that filters categories
  and tabs by label plus helpful keywords like themes, notification sounds,
  emoji packs, screen sharing, privacy, and support.
- Settings reorganization Phase 0/1 started. The Account category now opens
  with **Account & Profile**, combining account selection/actions with profile
  editing and a desktop live preview, while Account Deletion moved into
  Security as a Matrix homeserver handoff. The staged app-settings migration
  planning notes have since been archived after implementation.
- Account & Profile received the first visual follow-up from the settings
  reference notes: account actions were removed from the form, avatar/banner
  uploads and badge selection now live on preview hover affordances, profile
  text/color/timezone edits use a pinned unsaved-changes bar, dividers are more
  visible, and Logout moved to the Settings sidebar with an account picker
  confirmation dialog.
- Account & Profile received a regression follow-up: the desktop live preview
  stays pinned while the form scrolls, the preview card again has the requested
  profile-color border and shadow, the timezone row uses the shared switch
  design, disabling timezone no longer errors the preview, and Settings header
  dividers are more legible. Custom theme JSON loading now preserves bundled
  base theme extension settings when a saved custom theme omits those fields,
  so default-theme starting points keep their outline/space-menu styling.
- Account & Profile now hides the extra automatic scrollbar inside the
  two-pane editor, shows Color as two described swatches for profile/display
  name color and local display-name override, and draws the live preview border
  outside the profile card so the selected profile color is visible. Custom
  theme saves now include a full color-scheme snapshot from the selected base
  theme before editable overrides, preventing stale non-editable Material color
  slots from making Dark Lord custom starting points appear lighter after
  save/apply.
- The Account & Profile live preview now applies the selected profile accent
  to the lower profile-card background again, matching the older profile card
  behavior shown in `ProfileCard.png`.
- The Account & Profile settings preview no longer wires display-name clicks to
  the draft save path, preventing accidental saves from a preview-name click.
  Custom theme starting-point selection now warns before replacing unsaved
  token edits and lets the user keep editing or start over.
- Settings reorganization Phase 2 started with General. General now contains
  updates, media, direct message lock, app behavior, and window behavior in the
  proposed order. GIF search requires a configured relay or locally saved user
  KLIPY API key, media previews use a single None / Private chats only / All
  chats picker, sticker compatibility moved out of Advanced, read
  receipts/typing indicator and DM lock moved out of Account Privacy, and
  Window Behaviour is no longer a separate App Settings tab.
- General no longer opens to a white error screen after the Phase 2 settings
  move. The new GIF API-key description now has its own localization key
  instead of colliding with the legacy GIF proxy-url description, and the
  settings metadata test covers the generated message lookup.
- Settings reorganization Phase 2 continued with Appearance. Appearance now
  separates Style, App Icon, Theme, Message Appearance, Scaling, and Other
  Options; app icon selection previews the chosen light/dark/system artwork;
  themes are selected from gradient swatches next to theme names; the theme
  action row includes import and export controls together; App Scale and Text
  Scale use the two-column slider treatment and apply on release; and desktop
  small-window mode plus layout override moved into Appearance.

### Desktop

- Windows notification companion review follow-ups fixed two release risks:
  disabling the companion now clears pending companion display state and keeps
  later room cleanup state emissions from recreating the overlay, and the
  pending menu renders every newest-first message through the existing bounded
  scroll area instead of truncating the list before scrolling.
- Windows notification settings now include an opt-in notification companion
  overlay for approved message notifications. The MVP is Windows-only, keeps
  call/calendar toasts and notification sounds unchanged, can redact previews,
  hides previews for newly approved notifications while local screen sharing is
  active, and opens rooms through the existing notification click route. Message
  toasts are suppressed while the companion host is active so approved messages
  are not shown in two desktop surfaces at once.
- The Windows notification companion now uses selectable transparent light/dark
  avatar PNG artwork, switches to matching blank artwork with a pending-count
  overlay while notifications remain uncleared, shows the newest message in a
  system-theme bubble for 10 seconds, and includes a caret menu for the pending
  room/sender list.
- The companion layout is now about 30 percent smaller and closer to the latest
  reference: the message bubble is right-aligned near the avatar with the tail
  artifact removed, the notification count is smaller, the caret sits closer to
  the die, and idle motion pauses while dragging. A follow-up anchors drag
  movement to the Windows cursor, switches the drag region to the grab/grabbing
  cursor, and opens the bubble/menu inward from nearby screen edges. The latest
  follow-up uses the Windows hand cursor mapping and resolves edge placement
  per monitor instead of against the full virtual desktop. The expanded caret
  menu now grows and scrolls away from the companion icon as pending
  notifications increase, and the avatar picker labels are now `Light Side
  Icon` and `Dark Side Icon`. The message bubble now anchors to the corner
  nearest the avatar and grows away from it in each screen-edge position, the
  companion restores its last dragged location on app reopen, and Windows
  message toasts are suppressed while the companion host is active so messages
  are not visually delivered twice.

### Mobile UI

- Android mobile composer sends no longer flip the focused text field into
  read-only mode while the message is in flight, so the system keyboard should
  stay open after send. Android timeline short flicks now use chat-specific
  lower fling thresholds so small swipes coast instead of stopping abruptly,
  and the Android composer blur is restored because it was not the scroll root
  cause.
- The message input now reports its measured height as the pill grows, and the
  mobile timeline uses that live height for bottom clearance so multi-line
  drafts do not overlap the latest message cards.
- Mobile emoji, GIF, and sticker picker panels now contribute their panel
  height to the reported message-input obstruction, so the latest timeline
  card clears custom picker panels as well as expanded composer drafts.
- Mobile slash-command suggestions now appear in a scrollable glass popup above
  the composer instead of stretching the composer stack underneath it. The
  mobile plus menu uses the same popup treatment, orders actions as Take a
  photo, Gallery, File, and Poll, and the composer padding is tightened for a
  shorter MM4-style bar.
- The mobile chat timeline now scrolls behind the composer layer, popup cards
  no longer create an opaque host sheet behind them, the system-keyboard gap
  matches the popup-to-composer spacing, blur/gradient is limited to the
  message input pill, and the timeline reserves dynamic composer/keyboard
  space for the latest messages. A follow-up pass restored actual backdrop blur
  behind the input pill, moved the bottom spacer back to the newest-message
  edge so the latest chat card can scroll fully above the composer, and removed
  extra Flutter keyboard inset animation so the composer tracks the system IME.
  The final neutral-position pass now treats keyboard open as an explicit
  request to restore the latest message above the composer, lets messages
  scroll behind the composer afterward, avoids repositioning while typing with
  the keyboard already open, and returns to neutral after sending a mobile
  message. Chat scrolling no longer dismisses the keyboard; a downward swipe on
  the composer area now handles intentional keyboard/panel dismissal. The
  expanded-keyboard timeline clearance now matches the compact
  collapsed-composer spacing so the latest message sits close above the
  composer instead of leaving a large gap.
- Double tapping or double clicking a message now applies the first reaction
  from the user's customized quick reaction slots when the message can be
  reacted to.

### Reliability

- Mobile attachment downloads now pass file bytes to `FilePicker.saveFile` on
  Android, iOS, and web, matching the plugin requirement that mobile saves use
  an in-memory payload. Desktop downloads keep the existing path-based save
  flow.
- Fallback direct-message classification now requires a complete local
  participant snapshot and a Matrix room summary reporting exactly two joined
  members before treating a room missing `m.direct` account data as a DM. This
  prevents unopened multi-person rooms with partial member caches from briefly
  appearing as DMs while preserving explicit `m.direct` rooms.
- Offline demo desktop rooms now provide local empty emoji/sticker packs so
  Demo Lounge and forum thread composers no longer hit the null emoji-picker
  crash while preparing app-guide screenshots.
- Offline demo mode now seeds sample direct messages with Mira, Theo, and Nova
  through a local DirectMessagesComponent so the desktop DM rail/list has
  realistic guide content.
- URL previews now warm and reuse recent synced link previews when chats load
  or receive latest-message changes. Preview data is cached by Matrix
  room/event ID during the app session, direct-preferred providers no longer
  wait for the homeserver path before trying the direct fallback, and preview
  expansion keeps the timeline pinned only when the user was already at the
  latest message.
- Android FCM background notification handling has been returned to the
  build-929 decrypt-capable notification manager after device validation showed
  the lightweight decrypt path still did not render encrypted message previews.
  FCM remains data-only through the configured push gateway, and the app still
  fetches/decrypts locally before showing the notification.
- Android FCM wake handling is hardened around the working build-929 path:
  malformed Firebase payloads are ignored before Matrix startup, background FCM
  messages are serialized and reuse one manager inside the Firebase isolate,
  and Matrix background-service clients run one bounded wake sync instead of
  keeping continuous background sync enabled.
- Android notification power-user hardening now persistently rate-limits full
  Matrix background wake syncs per client, ignores duplicate FCM deliveries for
  the same room/event inside the Firebase isolate, and serializes notification
  inline replies before sending. Android bubble entrypoints also use the same
  limiter for bursty startup syncs while the normal main app startup path stays
  unchanged. This keeps the build-929 decrypt-capable path while reducing
  repeat session-key/one-time-key pressure on Synapse.
- Saved review-backlog findings for PR #12 were applied: stale Android
  pushers can now fall through to the Android push-key fallback before device
  display-name matching, background Matrix wake syncs pass the timeout into
  the Matrix SDK sync itself, account-management homeserver links ignore
  hostless and non-HTTP(S) homeservers, current-version release notes use a
  canonical version key, and the patched-libwebrtc installer preserves the
  target source file newline style while patching.
- Additional PR #12 CodeRabbit follow-ups now keep demo direct-message caches
  in sync when rooms are left, preserve post-login onboarding/setup retries if
  an unawaited UI handoff throws, avoid recreating screen-share thumbnail
  refresh timers after picker disposal, and make homeserver website/deletion
  copy match the actual launchable-URL behavior.
- PR #12 CodeRabbit follow-ups now keep URL-preview warmup cache entries
  available under both normalized and original event links, rerun timeline
  warmups when new work arrives mid-pass, and avoid rendering an invalid
  dropdown when a string preference has no options. Follow-up review fixes also
  snapshot timeline events before awaited URL normalization and trim local
  event-cache maps alongside the long-lived event cache.

### Calls / Streaming

- Direct Matrix camera disable now releases camera capture by muting Matrix
  call metadata, then removing and stopping local video tracks from the
  usermedia stream while leaving microphone audio active. This follows the
  unexpected camera-activation audit, which ruled out settings mic check,
  non-call capture outside the explicit "Take a photo" action, and the LiveKit
  camera disable path. Direct-call camera enable/disable operations are now
  serialized so rapid off/on toggles cannot let stale disable cleanup remove the
  camera track after a newer re-enable.
- Desktop stream popouts and detached call windows now start opaque every time.
  Transparent chrome is kept in memory for the currently open popout/window
  only, so an older transparent toggle cannot make the next stream popout open
  directly into the white/blank transparent-state failure. The transparency
  button still works after the popout has rendered.
- LiveKit camera stop/re-enable now clears stale local camera publications by
  explicitly unpublishing and stopping camera tracks, then publishing a fresh
  single-layer VP8 camera track. Camera toggles are serialized, the call UI
  awaits camera enable, and track publish/unpublish transitions are logged so
  dead zero-frame camera senders can be diagnosed.
- PR #12 CodeRabbit follow-ups now keep screen-share contain-fit dimensions
  even and encoder-valid, clear sender packet-send-delay samples on screenshare
  teardown, merge observed screenshare sizes by per-axis maxima, and restore
  screenshare-audio volume per stream instance instead of once per user.
- Additional PR #12 call/release follow-ups now use the same source-id hash in
  screen-share picker and share-session diagnostics, initialize LiveKit receive
  quality labels from the default priority, and restore the Flutter WebRTC
  capture source backup if patched-libwebrtc installation fails after mutating
  the package cache source.
- Windows RNNoise now has configurable tuning presets. `Gentle` preserves the
  previous rollback baseline, `Balanced` is the default stronger profile,
  `Strong` catches short transients more aggressively, and developer mode can
  expose custom VAD, grace, closed-gain, and transient-sensitivity controls.
- RNNoise native diagnostics now report the active tuning values, and the
  native gate can fast-close on transient noise while keeping smoother opening
  behavior to avoid clipping speech.
- Adaptive gameplay stream fallback now keeps the stricter WebRTC-label
  corroboration rules while still rescuing truly collapsed sends. A raw CPU
  quality-limitation label with healthy encode/drop/send-delay counters is
  ignored, but missing-counter CPU labels and severe FPS collapse can still
  trigger fallback after hysteresis.
- Added a Windows capture-to-publish investigation baseline, documenting why
  crop-style resolution enforcement is unsafe and why future stream fixes must
  use aspect-preserving pre-encode scaling instead. Those planning notes have
  since been archived after implementation.
- Developer call diagnostics now split streaming FPS/size by pipeline stage:
  native desktop capture, WebRTC source/pre-encode, encoded sender frame, sent
  packets, received/decode, and render. This should make Smooth 1280x720
  validation and future low-FPS investigations evidence-based.
- The patched Windows libwebrtc artifact has been rebuilt and installed with
  native desktop-capture FPS diagnostics so fresh call logs can show whether
  FPS loss starts before WebRTC encoding.
- Stream planning/report docs have been moved into `docs/architecture/` so the
  workspace root stays reserved for coordination and build/workspace material.
- Added `docs/architecture/fluxer-media-pipeline-research.md`, a read-only
  Fluxer reference pass covering its LiveKit/Electron streaming, WebRTC-native
  noise suppression, stream preview pipeline, subscription policy, diagnostics,
  and backend topology, plus what is useful or unsafe to port to Inter
  Galactic.
- VoIP settings now show the active processed-audio capture profile and native
  RNNoise status, plus a local processed mic check that uses the same WebRTC
  audio constraints as calls.
- ShareSession diagnostics now identify the selected source type, short
  source-id hash, resolved process id, requested shared-audio mode, and
  shared-audio state/reason while keeping window/source titles redacted unless
  developer stream diagnostics are enabled.
- Screen-share/shared-content audio volume now persists locally per room and
  remote stream user, clamped to `0.0..2.0`, without persisting normal
  microphone participant volume.
- Receive-priority application now has a pure LiveKit quality-label mapping
  helper and logs focused/high, medium, low, and disabled video subscription
  transitions when developer stream diagnostics are enabled.
- Gameplay adaptive fallback now detects when requested lower sender
  resolutions are not reflected in encoded frames. In that state it logs the
  requested-vs-encoded mismatch and holds the current fallback instead of
  repeatedly cutting bitrate/resolution while the sender keeps encoding the
  larger frame.
- The desktop screen-share picker now keeps the existing source previews alive
  more reliably by logging thumbnail availability, waiting longer for native
  thumbnail events, and asking the capturer to refresh source thumbnails before
  falling back to placeholder icons.
- Screen-share picker thumbnail refreshes are now coalesced per source type so
  many thumbnail-less tiles do not all ask the native desktop capturer to
  refresh window/screen sources at the same time.
- Windows advanced stream override now defaults to the same single-layer H.264
  hardware-first path as the normal presets while preserving developer bitrate,
  FPS, and resolution controls. Developer mode also exposes a hardware encoder
  toggle and an active override summary alongside codec/simulcast controls for
  faster live log capture.

## v0.6.6 (In Progress)

Build date: 2026-04-30

### Documentation

- Public release policy docs now default abuse reporting to Matrix-native
  homeserver pathways, document block/ignore as Matrix ignored-user account
  data, and use `intergalactic@ourgalaxy.space` as the public Inter Galactic
  contact address.
- Settings now includes Help & Safety and Policies tabs above About, with
  Matrix-native message, room, and user report submission plus Matrix
  ignored-user block/unblock controls for the selected account.

### Photo Rooms

- Photo rooms now have a second visual polish pass: desktop cards use cleaner
  depth, refined stack layering, and a quieter media-surface background, while
  mobile photo rooms use the app's rounded glass-style card, add-menu, and
  upload-review treatment.
- Desktop photo rooms now use a more polished media-grid surface with calmer
  spacing, card borders/shadows, hover fullscreen controls, stack badges,
  comment/reaction indicators, and an empty state.
- The photo-room add button now opens a first-step menu for choosing either an
  individual photo or a photo stack. Individual uploads pick one image; stack
  uploads pick multiple images and require at least two photos.
- Photo stacks are grouped with `chat.intergalactic.photo_stack` metadata on
  each image event. The index-0 image acts as the stack root for comments and
  root-level reactions, and Matrix thread replies are filtered out of the album
  grid so comment attachments do not become album photos.

### Mobile Appearance

- Spotify connection settings now keep the connection status and action buttons
  left-aligned with the rest of the Activity settings menu.
- Scaled mobile URL previews down in both bubble and non-bubble message modes
  without changing the preview content selection or image aspect ratio.
- Native Android and iOS login screens no longer expose account registration
  for app-store compliance, while desktop and web keep Create Account
  available.
- Favorites now uses a space-like local banner header, and custom themes can be
  exported as import-compatible theme archives.
- Login-page offline demo mode is hidden by default behind App Settings and now
  uses platform-neutral copy.
- Dragging a mobile timeline dismisses the keyboard, and URL preview expansion
  keeps the timeline pinned to the bottom when the user was already at the
  latest message.
- Android can now record and send voice messages from the same mobile composer
  microphone UI used on iPhone.
- Bubble-mode grouped avatars now anchor to the bottom/last message in a sender
  run, matching the visual rhythm of mobile chat bubbles.
- Desktop small-window mode no longer renders the persistent activity/soundboard
  panel in the compact rail, and space-list room indicators reserve room for the
  scrollbar.
- Transparent call popout chrome is no longer exposed as a pre-popout settings
  toggle; it remains available from the actual call popout controls.

### Reliability

- Android FCM background notification handling now uses the lightweight
  background room/event reader instead of initializing full Matrix SDK clients
  in a headless isolate, preventing duplicate one-time-key uploads when a
  background push races the active foreground or bubble session.
- Android FCM encrypted-message notifications now decrypt through a narrow
  background Matrix SDK client that uses the local crypto database and waits
  for one wake sync before rendering the local notification. This gives Matrix
  sync/to-device processing a chance to ingest room keys for the pushed event
  without restoring full background client startup.
- Android FCM Matrix pushers now carry a lightweight-background registration
  schema and are replaced on startup when an updated install still has stale
  current-device pusher metadata, avoiding the sign-out/sign-in workaround.
- Local Firebase options are no longer tracked in git. Owner-specific
  `intergalactic/lib/firebase_options.dart` files stay available for local
  Android builds while public source control ignores the generated config.
- Repo-root Windows builds now run the explicit package-resolution step before
  asking `build_release.dart` to skip Flutter's internal pub step, so
  `build.bat` can recover from pub.dev advisory decode failures with its
  cached-package retry without changing the default behavior of other release
  callers.
- Desktop and web registration now follows Matrix UIA more closely: it submits
  username/password first, prompts for an invite code only when the homeserver
  requires `m.login.registration_token`, preserves that UIA session for retry,
  and completes open-registration `m.login.dummy` handshakes without showing a
  token field.
- Registration-token retries now stay inside the same Matrix UIA flow when the
  homeserver requires an additional stage after accepting the token, instead of
  converting that second challenge into a generic registration error.
- Accepting or declining the last pending room invitation now clears the
  temporary orange `!` sidebar tile immediately instead of leaving a stale
  cached invitation count.
- Bundled Light Side and Dark Side theme selections now survive app restart by
  saving stable asset IDs and migrating the older display-name preference IDs.
- Favorite rooms now persist across account restore/update paths by saving an
  account-stable Matrix user/room key while still reading legacy client-local
  favorite IDs.
- Automatic update checks now default to enabled, and users who inherited the
  old first-run "off" value are migrated back onto the update notification
  path once.
- Update alerts now include a brief public release-notes summary from
  `latest.json`, and the current version's notes are shown once after an
  updated install first opens.
- Successful Matrix logins and restored sessions now use a basic MXID-backed
  profile if startup/profile warmup fails, avoiding generic `Error` account
  labels until restart.
- Screen and window sharing now defaults the Share audio option on while still
  allowing users to turn it off per share.
- Demo thread timelines fall back to the room timeline when local sample data
  does not provide a dedicated thread timeline.
- LiveKit call views filter stale remote streams against active MatrixRTC
  membership state and hide developer loopback identities from normal
  participant diagnostics.
- Call soundboard playback now reaches receivers more reliably during limited
  Matrix sync batches and short call-session registration races.
- Manual soundboard button presses are no longer swallowed immediately after a
  user's join sound because playback cooldowns now separate join, manual, and
  preview sources.
- Encrypted call-room soundboard events are now resolved before playback, local
  presses play immediately before the Matrix send completes, and the remaining
  per-sender soundboard cooldown was removed.
- Soundboard uploads now include a shared per-sound volume setting, and
  uploaders/admins can tune existing clips so loud sounds fit the server library
  without overriding each listener's local soundboard volume.
- Windows RNNoise keeps WebRTC's built-in microphone cleanup enabled during
  warmup or guard failures, then takes over after verified native frames so the
  toggle has an audible effect without losing fail-open safety.
- Windows RNNoise now uses the native VAD score to gate residual and
  transient low-confidence output after the fail-open guard, reducing keyboard
  taps and desk bumps without treating bad native frames as valid speech.
- Windows RNNoise no longer treats strong low-confidence noise attenuation as a
  suspicious-output failure, so keyboard taps and desk bumps can be muted
  instead of forcing the microphone path back into mostly video-call fallback
  processing.
- Windows RNNoise now requires higher native speech confidence before marking
  collapsed output as suspicious, and the VoIP settings readout includes latest
  VAD/input/output/ratio values for loopback tuning.
- Windows RNNoise no longer treats strong relative attenuation by itself as a
  suspicious-output failure, and active LiveKit calls refresh their microphone
  capture profile once RNNoise becomes healthy so WebRTC's built-in suppression
  actually yields to the native path.
- Existing CodeRabbit PR findings were addressed for demo room cleanup, scoped
  Android pusher pruning, LiveKit token timeouts/cancellation, loopback toggle
  error handling, demo login hardening, stable audio-device IDs, voice-recorder
  teardown/null-save feedback, poll-send feedback, reaction event targeting and
  bounds checks, update manifest validation, and platform-consistent space
  header typography.
- Follow-up CodeRabbit pass hardened Firebase push misconfiguration errors, demo
  call session cleanup, MatrixRTC participant identity parsing, Matrix HTTP
  client disposal, favorites banner storage limits, URL-preview auto-scroll
  thresholds, and async VoIP settings updates.
- Follow-up review fixes now keep poll creation pinned to the originating room,
  cancel native voice recording after stop/start failures, debounce Matrix
  device-name refreshes, avoid reaction init bounds crashes, and prevent
  stale LiveKit loopback enables from winning after the user disables loopback.

### Calls / Developer Tools

- Voice and Video settings now include a local soundboard volume slider.
- Voice and Video settings now show RNNoise native status reason, frame counts,
  bypass/gate counters, resampler use, and guard flags on Windows.
- The LiveKit developer overlay has a copy action for visible diagnostics.
- Developer mode now adds an in-call diagnostics menu with call/RNNoise/
  shared-audio summary, stream stats, and related call/media log entries in one
  copyable place.
- The in-call diagnostics menu now also has a save action that exports the same
  summary, stream stats, and related logs as a text file from inside an active
  call.
- The developer logs panel can save a text log bundle with build, device, log,
  and stack-trace details.
- Developer mode now has a separate Show timeline diagnostics toggle, so raw
  Matrix events, reactions, hidden events, and parse failures stay out of normal
  room timelines unless explicitly enabled.
- CodeRabbit PR follow-up now retries soundboard plays when the referenced
  space has not materialized locally yet, and encrypted VoIP-room soundboard
  plays are decrypted before active-session checks so startup/reconnect races
  can queue instead of dropping the event.
- Latest stream diagnostics prove Windows hardware-first H.264 requests reach
  LiveKit but still select `OpenH264 hw:false`; the next stream fix needs to
  inspect or patch the `flutter_webrtc` / `webrtc-sdk/libwebrtc` Windows
  encoder factory instead of changing Dart bitrate/profile settings again.
- The Windows hardware-encoder proof path now lives in a local
  `webrtc-sdk/libwebrtc` fork that enables the wrapper's Intel Media SDK /
  oneVPL H.264 encoder-factory path by default and logs native factory
  selection/fallback. The fork still needs a packaged Flutter WebRTC
  `libwebrtc.zip` before app builds can prove GPU encode.
- Windows builds now have a patched-libwebrtc preparation step in the root
  `build.bat` workflow. It can install a hardware-encoder `libwebrtc.zip` into
  the resolved Flutter WebRTC package cache, warn-and-continue in normal auto
  builds when the artifact is absent, or fail strict validation builds with
  `--require-patched-libwebrtc`.
- The Windows libwebrtc fork now produces a strict-build-consumable
  `libwebrtc.zip` artifact for release-managed builds. The first artifact kept
  the Intel Media SDK patch encoder-only, left video decode on WebRTC's built-in
  factory, and completed the strict patched-libwebrtc Windows build path.
- RNNoise now bridges valid non-48 kHz microphone callbacks with a native
  Hann-windowed sinc resampler into RNNoise's 48 kHz / 480-frame shape, then
  resamples back to WebRTC's capture frame count. Diagnostics show the
  resampler mode, rates, and frame counts, and the production stateful
  resampler plan is documented.
- RNNoise no longer rejects 48 kHz WebRTC callbacks just because the audio
  processor reports its internal three-band 48 kHz metadata. Those frames now
  enter the RNNoise processor instead of failing open as
  `capture_format_mismatch(split_bands)`.
- Latest `v0.6.6+921` call diagnostics used the patched Windows WebRTC DLL but
  still reported `OpenH264 hw:false`; the local test host has NVIDIA RTX 2070
  and DisplayLink devices with no Intel Quick Sync device, so the Intel Media
  SDK proof path is expected to fall back. The next native encoder path should
  target Windows Media Foundation or vendor-backed H.264 for NVIDIA/AMD hosts.
- The patched Windows WebRTC artifact now tries a Media Foundation hardware
  H.264 encoder factory before the Intel Media SDK proof path and OpenH264
  fallback.
- Follow-up call diagnostics showed the NVIDIA Media Foundation path needed
  asynchronous output draining, so the libwebrtc fork now drains
  `METransformHaveOutput` events before falling back.
- Latest `v0.6.6+926` diagnostics confirm Windows screen sharing is now using
  `MediaFoundationH264 hw:true`. Stream bitrate math now normalizes native
  LiveKit/WebRTC microsecond timestamps before calculating bps, and adaptive
  fallback no longer treats a startup `availableOutgoingBitrate` estimate alone
  as proof of a network bandwidth problem.
- Normal screen-share presets now all support automatic adaptive fallback:
  Smooth remains the 720p/30 default, Balanced/High Quality can still be chosen
  for higher quality, and only the developer Advanced Override path stays
  manual unless fallback is explicitly forced on.
- Repo-root `build.bat` now requires the patched Windows `libwebrtc.zip` by
  default, so normal Windows builds use the hardware-encoder WebRTC path
  without needing `--require-patched-libwebrtc`. Deliberate stock WebRTC builds
  can still pass `--no-patched-libwebrtc`.
- Fresh Smooth, High Quality, and Advanced Override logs showed Windows presets
  using `MediaFoundationH264 hw:true` but falling back too aggressively on a
  clean direct UDP route. The first Windows hardware-first retune used gameplay
  bitrate ceilings of 5 Mbps for Smooth, 8 Mbps for Balanced, and 12 Mbps for
  High Quality, and adaptive fallback ignores uncorroborated below-target
  bitrate while waiting for a severe FPS collapse before using FPS alone.
- Follow-up gameplay logs showed clean hardware-encoded streams still
  downshifting too far. Windows hardware-first Balanced and High Quality now
  get additional bitrate headroom at 10 Mbps and 18 Mbps respectively, low
  available-outgoing bitrate alone no longer corroborates network fallback,
  and hardware streams wait for a more severe FPS collapse before FPS alone
  triggers fallback.
- Fresh v0.6.6+932 diagnostics showed High Quality hardware-first stayed active
  in the app fallback controller, but WebRTC's own `bandwidth` adaptation still
  pushed the single-layer hardware stream down to thumbnail resolution.
  Windows hardware-first H.264 now publishes with maintain-resolution
  degradation, and sender-limit reapplication remembers the largest observed
  share size instead of following degraded output dimensions downward.
- Fresh v0.6.6+933 diagnostics showed `MediaFoundationH264 hw:true`, but Smooth
  still hit a WebRTC `cpu` limiter because Flutter WebRTC fed 2560x1440 game
  frames into the encoder after Smooth requested 1280x720. The patched WebRTC
  build helper now also patches Flutter WebRTC's Windows desktop capture bridge
  so requested capture dimensions are applied before frames reach the encoder.

### Screen Sharing

- The desktop share picker now opens on window/app sharing before full-screen
  sharing, requests explicit preview thumbnail sizes, retries missing
  thumbnails per tile, and uses a stable placeholder icon when a window cannot
  produce a preview.

---

## v0.6.5

Build date: 2026-04-28

### Documentation

- Rewrote the README to describe Inter Galactic's current Matrix-native scope, active platform targets, feature set, build paths, and credits for upstream Commet and RNNoise.

### Commands

- Added `/inviteall` for server/space admins. The command invites joined members of the current channel's containing space into the channel, skips users already joined or invited, and fails closed when the channel has no unambiguous Matrix space context or the user lacks required permission.

### Reliability

- Added an offline demo account. The login screen can create a local-only
  `DemoClient` with a sample space, chat room, forum room, voice room, and
  calendar room, without connecting to a Matrix homeserver or push service.
- Added a client-component disposal hook so the direct-message component cancels Matrix sync, selected-room, room-add, room-remove, timer, and stream-controller resources when a Matrix client is closed.
- Hardened the Matrix client lifecycle so restored clients initialize direct-message room tracking after database restore, while Matrix sync/status subscriptions are cancelled before component teardown during close.
- Shared native login now reuses stored Matrix device IDs for password and
  SSO login, bringing Android/native login closer to the retired web/PWA
  device-preservation behavior.
- Update availability now compares manifest versions before falling back to
  build dates, so installing the advertised app version clears the
  update-available alert even if build timestamps drift.
- Matrix events with explicit `@room` mention metadata now force local
  notification eligibility, and unread room-wide mentions propagate to child
  room rows plus parent spaces with the orange attention badge treatment.

### Builds

- Build and release helpers now preserve pubspec build metadata in release
  tags and hosted filenames. Android APKs are written as
  `InterGalactic-{version+build}.apk`, Windows installer/source/checksum assets
  are build-stamped during `release.bat`, and `latest.json` includes
  `version_name` plus `build_number` for website/updater consumers.
- Android and web build scripts now use an explicit Google Services source
  toggle: Android release builds enable Firebase/FCM by default, while web
  builds disable those Android-only dependencies before resolving packages.
- Android release builds strip a dev-only `integration_test` plugin
  registration from Flutter's generated release registrant before Java
  compilation, preventing release builds from depending on the test plugin.

### Notifications

- Added local room-specific desktop notification sounds. Windows and Linux
  message notifications now use a per-room sound override when one is set in
  Room Settings > Notifications, otherwise they fall back to the app-wide
  notification sound.
- Android FCM notifications now use the decrypt-capable Matrix background
  notification path before displaying local message notifications, preventing
  generic or diagnostic Firebase payloads from appearing as user-facing
  notification text.
- Android message notifications now support inline replies and route
  cold-launch taps through the shared notification response handler so actions
  target the correct Matrix room.
- Android FCM builds now stop the embedded-push foreground service on startup,
  keeping the fallback-only "Listening for message notifications" notification
  from lingering in Firebase builds.
- Android FCM pusher refresh now removes stale Android URL/legacy pushers
  before per-device matching, and still performs that safe cleanup when the
  current FCM token is temporarily unavailable.

### Mobile Appearance

- Added mobile-only local message backgrounds with an app-wide default in Appearance settings and a room-specific override in Room Appearance settings.
- Added a brighter mobile liquid-glass rim highlight to shared section cards,
  pill controls, the message composer, and picker chrome.
- Fixed native custom-theme refresh so newly created/imported/edited themes appear in the theme list and can be selected immediately.
- Android chat views now keep the message composer just above the keyboard
  while typing without leaving a large empty gap.
- Android system keyboard avoidance now ignores the custom picker focus gate,
  so the message bar still moves above the normal text keyboard.

### Desktop UX

- Added a persisted desktop small-window mode with a settings toggle and
  user-bar quick toggle. Compact desktop windows now keep desktop navigation,
  timeline, and composer behavior while reducing rail/header/user-bar chrome
  and collapsing the default members panel only below the compact width
  threshold.
- Tightened small-window mode for short horizontal monitors: room navigation
  and room members now collapse into hover-reveal panels, the room header is
  shorter, primary message text is 1.5x larger without enlarging URL preview
  text, the settings switch tracks user-bar quick-toggle changes, and F11
  fullscreen hides/restores the Windows title bar.
- Compact desktop rail mode now opens local activity/music controls from the
  current-user avatar when lower-left activity panels are hidden.
- Desktop chat rooms now honor the same local default and per-room message
  background images/opacities already used on mobile.

### Calls

- LiveKit token requests now include Inter Galactic client metadata so the
  MatrixRTC auth service can grant screen-share publishing only to current
  Inter Galactic builds while limiting legacy clients to microphone/camera
  publishing.
- Tuned Smooth LiveKit gameplay streaming for multi-stream rooms: the preset
  keeps a 30 FPS motion target, uses lighter bitrate/lower-layer resolution,
  and always keeps preset VP8 simulcast enabled regardless of stale hidden
  advanced simulcast preferences.
- Implemented the LiveKit research follow-up: Android screen-share capture and
  publish options now use the selected profile, room defaults use the same
  capture profile as a safety net, LiveKit stats are scheduled by the session,
  diagnostics expose richer sender/receiver fields, and adaptive fallback
  reduces resolution before reducing frame rate.
- Added transparent desktop call popouts that hide chrome until hover, with a
  VoIP setting and popout toolbar control for game-overlay use. Native
  detached Windows popouts now also remove the Win32 titlebar/frame while
  keeping a lighter hover-safe backdrop, move window controls to a centered
  pill away from video-tile hover actions, and keep the call layout stable
  while hover controls appear.
- Fixed desktop per-stream popout frames so popped-out streams keep a stable
  video area instead of collapsing into a blank panel when transparent chrome
  is enabled.
- Re-enabled the RNNoise native capture hook with health guards: WebRTC
  microphone suppression stays active during RNNoise warmup, only yields after
  verified processed frames, and suspicious native output is bypassed instead
  of being written into the mic buffer.
- Added a developer-only LiveKit server audio loopback control in active calls.
  It opens a second subscriber-only SFU connection so developers can hear their
  microphone after RNNoise, publish, server routing, and receive playback,
  without waiting for another person to join.
- Improved desktop soundboard playback for additional uploaded audio MIME
  aliases and known file extensions, with MIME/local-path logging when
  `media_kit` cannot open a resolved sound.
- Reduced call visualizer/stat polling cadence, removed noisy call-stream debug prints, cleaned up direct/LiveKit stream renderers and listeners when streams leave, and stopped volume slider drags from rebuilding the full call surface.
- Hardened direct-call and LiveKit teardown/receive-priority paths so screen share/audio capture cleanup is serialized, hidden developer-only stream overrides are ignored when developer mode is off, and LiveKit receive-priority changes cannot complete out of order.
- Updated LiveKit default screen-share publish options to honor the selected screen-share quality profile instead of always falling back to the smooth profile.
- Hardened call soundboard behavior so play events are scoped to the owning space, async playback failures are logged and surfaced, self join-sound preferences use private per-room account data, and member uploads no longer make per-user soundboard room state member-writable.
- Hardened soundboard playback and emoji handling after review: local cache filenames are now media-aware and hash-derived, truncated downloads are rejected, shared player operations are serialized, post-dispose player recreation is blocked, stale call overlays cannot target an old session, the shared player is disposed with the app view, custom emoji lookup avoids nullable shortcode crashes, and soundboard emoji search ranks exact/prefix matches ahead of substring matches while scanning the full candidate set before returning the top 50, including slug-only custom emojis.
- Fixed uploaded soundboard sounds playing silently by resolving MXC audio into soundboard temp files with audio extensions and playing through a persistent local player, added the app emoji picker to the sound upload emoji field, and changed the desktop in-call soundboard into a compact anchored popover.

### Media / Attachments

- Added image spoiler send/render support and safer Matrix spoiler fallbacks so
  plain `body` text does not expose hidden spoiler content to simple clients or
  notifications.
- Bubble-mode timelines now render photos, URL previews, and reactions outside
  the text bubble while keeping URL previews in a compact message-card style.
- URL previews now reserve layout space while loading, cache longer during the
  app session, hide duplicate URL-only message text, and default to enabled for
  friend-chat convenience.
- Encrypted-room URL previews now have explicit opt-out guidance in Settings >
  General > Third-Party Services so users can disable homeserver preview
  fetches when they prefer stricter link privacy.
- Photo stacks now respect disabled media previews, keep per-photo reaction keys unique, and only expose the mobile bottom-sheet long-press menu on mobile builds.

### Threads / Forums

- Fixed mobile reaction long-press so reaction-user tooltips can open again,
  mirrored thread reply pointers for right-aligned sent bubbles, and wrapped
  the pinned original thread message in a clearer panel.
- Forum tag labels now use the app's native emoji fallback path so emoji render
  more reliably on iPhone.
- Fixed mobile forum post creation so the keyboard no longer traps the sheet or covers the Post action; the mobile compose sheet now has explicit Close/Cancel controls, a scrollable form body, a sticky Post footer above the keyboard, viewport-aware sizing for cramped layouts, and dismissal locks while a post is being created.
- Forum post creation failures are now logged and surfaced with an in-app retry message while preserving the draft text.

### Room Navigation / Invitations

- Hardened sidebar invitation counts and dialogs so stale account filters are cleared when accounts are removed, invitation component snapshots are reused consistently, locally resolved invites do not immediately reappear while sync catches up, and one-to-one DM fallback refreshes are coalesced during membership-heavy syncs.
- Sidebar invitation buttons now expose explicit screen-reader labels and tap hints for pending invitation counts.

### Activity / Rich Presence

- Added the source-owned Spotify control bridge for previous, play/pause, and next through Spotify Web API player commands.
- Added Spotify saved-track polling plus a like/unlike activity-card control backed by the current track URI and Spotify library endpoints.
- Expanded Spotify OAuth scopes for playback control and library read/write; users with older read-only session tokens need to reconnect Spotify before controls enable.
- Switched Spotify polling to the playback-state endpoint with an available-devices fallback so track-transition or desktop-client restart gaps show `Spotify ready` when a Connect device exists instead of sticking on `No active Spotify device`.
- Added secure Spotify token persistence through `flutter_secure_storage`, so reconnecting should not be required after a normal app restart.
- Wired Windows release builds to pass Spotify OAuth config from `build.bat` into `BuildConfig`, including command-line, environment, and local `.env` sources.
- Wired Windows release builds to enable Steam game activity from `STEAM_ACTIVITY_API_BASE_URL`, with a private/internal `.env` fallback that derives the direct Steam summaries endpoint from `STEAM_WEB_API_KEY`.
- Shortened Spotify activity polling so external skips and natural song changes refresh faster.
- Added an opt-in Matrix presence publisher for simple `Listening to...` and `Playing...` status messages.
- Hardened Matrix activity publishing so status clears keep the last owned target until cleared, publishes are serialized, the existing Matrix presence state is preserved, and transient per-account failures do not stop other accounts.
- Moved Steam game activity to a server-side proxy contract using the `steamids` query parameter, with timeout/logging safeguards and no client-shipped Steam Web API key.
- Localized the new Spotify/Steam Activity settings strings and added disposal/lifecycle guards for activity sources and connection status streams.
- Prevented soundboard play events from replaying from limited Matrix timeline backfills after app restart or room rejoin.

### Windows Detached Call Windows

- Promoted native detached full-call windows to the default Windows build path after user validation confirmed the second call window works.
- Kept standard startup intact: Windows still starts through the normal runner and `main.dart` always calls `runApp(...)`.
- Converted the detached call implementation into a `ViewAnchor` host that creates secondary `RegularWindow`s only for full-session call pop-outs; per-stream pop-outs remain in-app overlays.
- Added `build.bat --no-detached-call-windows` as an emergency overlay fallback while default Windows builds enable Flutter windowing.
- Validated Windows debug builds and startup smoke. The mainline windowing executable opened exactly one visible `Inter Galactic` top-level window, so the old blank companion window did not reproduce.

### Windows Share Sessions

- Added a foundation ShareSession layer for Windows screen/window sharing so shared-content audio is owned by the selected share target instead of the microphone path.
- Added a dedicated Windows native plugin surface for Application Loopback capability/status, visible window/process target discovery, and explicit shared-audio session start/stop/dispose ownership.
- Preserved the current desktop screen-video path and added video-only fallback while the PCM-to-WebRTC/LiveKit publication bridge remains a documented follow-up.
- Kept RNNoise scoped to microphone capture only.

### iOS Authentication Cleanup

- Removed the old iPhone Home Screen web-session bootstrap, recovery screens, and installed-PWA auth guards now that iPhone support is centered on the native IPA path instead of the retired PWA flow.
- Kept post-login encrypted-session recovery in the shared login flow so native sign-in can still prompt for Matrix recovery immediately after a successful login when a recovery key is supplied.
- Retired the old web-only developer diagnostics panel for iPhone PWA session state and replaced it with guidance to use native platform logs and Matrix security screens for troubleshooting.
- Tightened the shared login flow so recovery keys are forwarded directly into post-login recovery instead of being cached on page state across retries or auth-flow switches.
- Simplified the retired developer diagnostics stub into a stateless presentation page now that it no longer loads or refreshes runtime diagnostics.

---

## v0.6.1

Build date: 2026-04-20

### iPhone PWA Session Durability

- Added a web-only bootstrap and recovery flow so iPhone Home Screen launches can distinguish between healthy restores, crypto-recovery cases, and browser storage loss instead of dropping straight back to the login screen.
- Session repair on web was reduced to lightweight health checks during normal focus/visibility churn, while heavier recovery is now reserved for genuine token-loss or corruption cases.
- Web push preview enrichment was hardened so hidden PWA notification handling no longer tries to wake a degraded Matrix client into destructive repair work.
- Client ownership rules were tightened so duplicate live `MatrixClient` instances cannot compete for the same restored web session.

### Client Lifecycle and CI

- `ClientManager` now detaches clients by instance identity during replacement and logout cleanup, preventing an older async detach from accidentally removing a newer replacement client with the same identifier.
- Successful account logout now closes the local client deterministically before final detach, matching the existing forced-cleanup path used after logout failures.
- The active GitHub Linux build job was archived from `.github/workflows/build.yml`; Windows, Android, web, static analysis, and integration review paths remain active.

---

## v0.6.0

Build date: 2026-04-18

### Namespace Standardisation

- Internal package name standardised to `intergalactic` across all Dart packages, imports, and platform identifiers.
- Active repo moved to `intergalactic-app/inter-galactic` (hyphenated) to match the new convention.
- App ID updated to `chat.intergalactic.app`. Deep-link scheme remains `space.ourgalaxy` for auth callback compatibility.
- All `package:commet/...` import paths replaced with `package:intergalactic/...`.

### Call Room Fixes

- **Ghost participants** — Users who left a voice room no longer remain visible in the participant grid. `getCurrentParticipants()` now correctly filters out state entries where `m.calls` is an empty list (modern MSC3401 leave path) and entries where `m.expires_ts` has elapsed, in addition to the existing empty-content check.
- **Hide streams locally** — A new toggle button (camera icon) appears in the call controls while connected. Tapping it hides all remote video and screenshare tiles for the local user without affecting what other participants see. Audio continues playing in the background. Useful for performance on lower-end devices or when bandwidth is constrained.

### Session Sync Error

- **Dismissible error banner** — When a client session becomes disconnected and cannot sync, the background-task sidebar entry now shows a red ✕ dismiss button. Tapping it removes the banner immediately. The Matrix SDK continues its automatic reconnect attempts in the background; the banner reappears if the client reports another status change.
- `BackgroundTaskManager` gained a public `removeTask()` method used by the dismiss callback.

### Bundled Themes

- **Jedi** — Deep navy/teal theme inspired by the light app icon. Dark navy backgrounds (#0D1626 → #274060), bright teal/cyan primary (#00B4D8), off-white text with a slight blue cast. Based on the dark theme.
- **Sith** — Near-black theme inspired by the dark app icon. Near-black surfaces (#0A0A0A → #2D2D2D), deep crimson primary (#DC2626), near-white text. Based on the dark theme.
- Both themes appear in Settings → Appearance → Themes between the built-in defaults and any user-created custom themes.
- Bundled themes cannot be edited or deleted. A note below the list clarifies this.
- Bundled themes persist across restarts — `resolveTheme()` recognises the `bundled:<name>` preference key and loads the matching asset on launch.

### Forum Room Type

- **New room type: Forum** — A Discord-style forum channel can now be created from the "Create Room" flow. Select "Forum" from the room type list.
- Forum rooms are identified by `m.room.create` content `type = "chat.intergalactic.app.forum"`.
- Each post is a Matrix thread. The thread root event carries `ig.forum.title` (post title) and `ig.forum.tags` (list of tag strings). Tags available in the room are stored in room state event `chat.intergalactic.app.forum.tags`.
- **Forum view** — Replaces the standard chat view for forum rooms. Shows a search bar, a horizontal scrollable tag-filter chip row, and a card list of posts. Each card shows: tag chips, bold title, author avatar + name, body excerpt, reply count, and relative timestamp.
- **New Post dialog** — Title field, tag multi-select, and body composer. Sends the thread root with the Inter Galactic forum fields.
- **Thread view** — Tapping a post card switches to the full thread chat view. Back navigation returns to the post list.

---

## v0.5.2

Build date: 2026-04-18

### Android Bug Fixes

- **Room list visible on home screen** — The home screen on Android now shows all joined rooms (including rooms inside Spaces), not just orphan rooms.
- **Space room list now renders correctly** — Tapping a Space in the navigation drawer now shows the channel list. A `SingleChildScrollView` wrapper was conflicting with `ReorderableListView`'s own scroll controller, causing it to lay out at zero height.
- **URL preview layout** — Link previews on Android now stack vertically (image on top, context text below) instead of side by side.
- **Navigation bar safe area** — The Home and Favorites icons no longer render behind the status bar.
- **Quick reactions** — The long-press reaction picker now displays all 8 configured custom reactions (cap raised from 5 to 8, layout switched to `Wrap`).
- **Custom theme editor** — Color rows in the theme editor no longer clip label and description text on mobile. Switches to a two-row layout on narrow screens.

### Android Icons

- Deployed new Inter Galactic app icons designed for Android.
- **Light mode** — teal/blue d20 icon with blue orbital lines.
- **Dark mode** — black d20 icon with orange/red orbital lines. Automatically selected by the OS via `drawable-night-*` resource qualifiers.
- Icons scaled and deployed across all five Android density buckets (mdpi → xxxhdpi).
- Adaptive icon background colours updated: `#0C2D44` (light) and `#111111` (dark).

---

## v0.5.1

Build date: 2026-04-14

### Android Port

- **Initial Android build** — First working Android APK. App ID changed to `space.ourgalaxy.intergalactic`.
- **Rebranding** — App name set to "Inter Galactic" across strings, manifest, and build config.
- **Embedded push notifications** — UnifiedPush removed. Push is handled by a built-in HTTP SSE subscriber connecting to the configured push gateway.
- **Adaptive icons with dark mode** — Launcher icon respects device light/dark mode via `mipmap-anydpi-v26`.
- **Poll fix** — Fixed crash in poll widget (`BoxBorder.all()` → `Border.all()`).
- **Local build script** — Added `build_android.bat` with `--debug`, `--setup-key`, and `--skip-codegen` flags.
- **CI/CD** — GitHub Actions `release-android` job builds, signs, and deploys the release APK on tagged releases.

---

## v0.5.0

Build date: 2026-04-12

### Highlights

- Updated desktop fork branding, icons, executable naming, and attribution for Inter Galactic.
- Added room event controls for join, invite, and profile update visibility in room settings.
- Added customizable quick reactions in Settings > Emoticons.
- Expanded calendar room behavior with reminders, repeat improvements, attendance options, and default-view controls.
- Added theme customization tools, including custom theme creation and app icon mode selection.
- Exposed desktop notification sound and ringtone customization.
- Added favorites plus drag-and-drop room and space ordering.
- Improved call room layout with spotlight/equal-tile switching, in-app call pop-outs, per-panel pop-outs, and always-on-top pinning.

### Notes

- This was a desktop test build for bug validation before GitHub upload and release automation setup.
- Native multi-window call pop-outs are deferred; this build uses in-app floating pop-outs.
