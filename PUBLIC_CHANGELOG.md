# Public Changelog

This app-repo copy mirrors the current public-safe release note entry for the
source archive and public repository. The release workflow publishes the same
public changelog section to the website update metadata when a release is
prepared.

Current public changelog target:

- `https://app.ourgalaxy.space/updates/changelog/v0.8.0.md`

Previous published changelog:

- `https://app.ourgalaxy.space/updates/changelog/v0.7.4.md`

Internal engineering history belongs in `CHANGE_LOG.md`.

---

# Inter Galactic v0.8.0 Beta

Build date: 2026-07-06
Build identity: v0.8.0+992 development cycle.
Status: In-progress beta notes for the public repository and future release
pipeline.

## Highlights

### Top Changes

- The Emoticon Creator adds local background removal, manual mask cleanup,
  crop controls, preview backgrounds, local drafts, and mobile native cutout
  helpers on supported Android and iOS devices.
- Mobile call popout work continues with Android foreground call retention,
  Android picture-in-picture, and iOS native picture-in-picture support for
  active video calls.
- Desktop call popouts and detached call windows have cleaner transparent
  chrome, tighter overlay handling, and a vendored window-manager fix for the
  white edge seen around transparent Windows popouts.
- Stories and media rendering have stronger handling for video backgrounds,
  letterbox/pillarbox gaps, image stacks, animated media, and final output
  generation during upload or save.
- Fresh sign-in and add-account startup paths now refresh profile state more
  reliably, including the first account avatar shown after login.
- Accessibility work for the v0.8.0 cycle adds broader control semantics,
  readable settings structure, favorite-room category settings, and reduced
  motion handling for animated media.
- Windows gameplay streaming diagnostics have been reorganized around clearer
  sender, receiver, renderer, and reporting evidence. The stream-test tooling
  now has smaller modules and cleaner local runtime setup.
- GIF search now defaults to Inter Galactic's managed Klipy relay without
  embedding a direct provider key in the app. Users can still configure their
  own relay or API key locally.
- The app has moved into the v0.8.0 development cycle with aligned desktop,
  Android, and Apple-platform version metadata.

### Calls, Streaming, And Diagnostics

- Desktop call controls and detached call surfaces have clearer shared action
  controls, popout structure, and diagnostic boundaries.
- Call panels can show connection-health state such as strong, unstable, poor,
  reconnecting, disconnected, or audio trouble without exposing private room
  details.
- Call health, encrypted-history recovery, favorite-room category setup, and
  desktop navigation restore paths have additional review hardening for the
  v0.8.0 beta cycle.
- Hidden shared streams and focused call-room layouts have been tightened so
  muted/hidden stream audio, remote activity labels, and busy participant rails
  behave more predictably.
- Android active calls can keep a low-priority foreground call notification
  while the session is connected, reducing the chance that mobile OS background
  handling interrupts call audio.
- Android picture-in-picture can be requested from the existing call popout
  button on supported devices, and iOS can use the native system
  picture-in-picture surface for active video calls.
- Android call picture-in-picture controls received an additional session and
  receiver-permission hardening pass during release review.
- Stream-test local setup now uses a committed example env file and an ignored
  local env file, so users can configure machine paths once instead of editing
  scripts or test fixtures.
- Stream-lab runtime output is routed outside the app repo by default, keeping
  generated local evidence out of source control.
- Receiver-probe and renderer diagnostics were expanded for Windows stream
  validation so future beta tuning can distinguish sender, receiver, and
  renderer behavior more clearly.
- Call and stream diagnostic lifecycle handling has additional review hardening
  for late async callbacks, Android picture-in-picture sizing, and local
  diagnostic artifact redaction.
- Call-room side rails now restore more consistently on mobile and keep forced
  call-room panel controls aligned with the panel that is actually visible.

### Appearance And Themes

- New dark theme options include Dark Matter as the refreshed default and
  Cosmic Stardust as an additional built-in style.
- Existing custom themes remain selected across updates, even when a custom
  theme's saved ID matches a newly added built-in theme ID.
- Windows desktop builds have a cleaner custom title bar and refined close
  controls for the thread panel and add-account sign-in flow.
- Custom theme import and edit flows have stronger recovery paths for legacy
  theme folders, interrupted imports, and duplicate save taps.

### Media, Stories, And GIFs

- Animated media surfaces can respect pause-animation preferences while keeping
  image, GIF, sticker, preview, and story media affordances visible.
- Call and notification sounds now use original Inter Galactic audio created by
  Renzo Mayo aka Renzo!.
- Fresh installs use the managed Klipy relay for GIF search unless a build or
  user setting overrides it.
- GIF relay errors now log only the relay origin/path instead of the full
  request URL.
- The Emoticon Creator can generate transparent PNG cutouts locally, refine
  masks with erase/restore controls, save local drafts, and use supported
  mobile-native cutout helpers without sending source photos to a cloud
  background-removal service.
- Story image capture/import paths can use preview-size draft canvases during
  editing and generate the final full-size image when upload or save needs it.
- Story photo save now reuses the shared platform media-save helper, including
  supported Photos-library save paths.
- Desktop story recording now recovers more cleanly from camera discovery or
  recorder-start failures.
- Demo story video previews now carry the same display metadata used by normal
  video story uploads, preserving portrait composition in preview flows.

### Updates And Install Flow

- Version metadata now targets `0.8.0+992` for the next beta cycle.
- Release build tooling forwards the managed GIF relay by default and includes
  an explicit opt-out for unmanaged builds.
- Apple broadcast-extension build metadata and desktop installer metadata were
  aligned with the new app version.

### Known Issues

- Android call backgrounding, Android picture-in-picture, iOS
  picture-in-picture, and transparent desktop call popouts still need final
  rebuilt-device smoke testing before they should be treated as fully
  validated for release.
- Windows gameplay streaming remains in active beta tuning. If a game or
  screen share feels unstable, try the Smooth profile or a lower quality level
  and send a Report Issue entry with the app version and stream details.
- Android remains a direct APK download, so installing or updating may require
  approving installation from the browser or file manager.
