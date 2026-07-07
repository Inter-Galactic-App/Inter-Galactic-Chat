# Matrix Compatibility and E2EE Safety

## Purpose

This document captures the rules that must hold when changing anything related to:

- login and session restore
- encrypted room access
- verification and trust
- multi-account behavior
- web/browser persistence

If a fix touches account state, restore behavior, Matrix identity, or encrypted message usability, read this first.

## Core Rules

- Inter Galactic remains Matrix-native.
- Account state, device identity, and trust state must remain interoperable with Matrix homeservers and other Matrix clients.
- E2EE/session integrity is release-critical.
- Convenience is never a reason to weaken verification, trust continuity, or crypto persistence.

## Login and Session Restore

### Expectations

Login and restore paths must preserve:

- the correct account identity
- the correct device identity
- usable encrypted-room state when local crypto state is intact
- deterministic recovery behavior when local state is missing or corrupt

### Review together

When changing login or restore, inspect together:

- `intergalactic/lib/client/client_manager.dart`
- `intergalactic/lib/client/matrix/matrix_client.dart`
- `intergalactic/lib/client/matrix/auth/...`
- `intergalactic/lib/ui/pages/login/...`
- `intergalactic/lib/config/preferences.dart`

For web/browser restore also inspect:

- `intergalactic/lib/client/matrix/web/...`

### Do not

- silently replace one client/session with another
- discard restore state unless corruption or explicit reset is confirmed
- treat generic preferences storage as the source of truth for Matrix identity
- assume a successful app launch means crypto state is healthy

## Crypto Persistence

### Expectations

Local crypto state must remain scoped and durable enough for the target platform.

Relevant current code areas:

- `intergalactic/lib/client/matrix/matrix_client.dart`
- `intergalactic/lib/client/matrix/web/web_session_bootstrap.dart`
- vodozemac initialization inside the Matrix client layer

### What to preserve

- crypto store continuity across expected restarts
- secret storage and cross-signing setup continuity
- safe recovery behavior when crypto state is absent or inconsistent
- deterministic fallback when encryption support is unavailable

### Release blockers

- encrypted rooms stop decrypting after ordinary restart
- restore creates unnecessary new devices
- vodozemac initialization fails without a visible recovery path
- partial crypto state is treated as healthy

## Forced Password Reset

### Current implementation

- `intergalactic/lib/client/matrix/matrix_client.dart` probes
  `/_synapse/client/intergalactic/password-reset/status` after Matrix
  credentials are accepted. A missing endpoint is treated as unsupported so
  non-Inter-Galactic homeservers keep normal Matrix behavior.
- If the status probe returns `required: true`, or a Matrix error carries
  `org.intergalactic.password_reset_required: true`, the login page shows a
  non-dismissible password-change interstitial before post-login recovery,
  sync-dependent onboarding, or normal room use.
- The forced interstitial receives the temporary password from the just-accepted
  password login when available, but the user can edit it. SSO or unusual login
  paths still show an empty current/temporary password field.
- The app changes the password through the Matrix SDK account-password endpoint
  with `logoutDevices: false`, then re-checks the forced-reset status and
  continues only after the server reports `required: false`.
- The forced-reset screen offers Sign out as the escape hatch. Signing out
  discards the just-created Matrix session and rebuilds the login client while
  preserving the selected homeserver when it can be restored.
- Account -> Security exposes a voluntary Matrix password-change row. It is
  enabled only when the current Matrix session is verified; unverified sessions
  show "Verify this session before changing your password." Voluntary changes
  also use `logoutDevices: false`.

### Guardrails

- Forced reset may run before E2EE verification because the server blocks
  normal Matrix APIs until the password changes.
- Voluntary password changes must remain behind the verified-session guard.
- Passwords and temporary passwords stay in UI controller memory only and must
  not be logged, stored in preferences, added to Matrix account data, or
  included in diagnostics.
- Post-login recovery-key and biometric recovery prompts still run only after
  accepted Matrix credentials and after any required forced password reset.

## Device Verification and Trust Continuity

### Expectations

Verification UI must reflect real Matrix trust state. Cross-signing and verification should not be faked or simplified into app-local trust markers.

Relevant current code areas:

- `intergalactic/lib/client/matrix/components/key_verification_component/...`
- `intergalactic/lib/ui/pages/matrix/verification/...`
- `intergalactic/lib/ui/pages/settings/categories/account/security/matrix/...`

### Do not

- mark devices verified without actual Matrix verification state
- auto-dismiss trust problems as if they were cosmetic
- reset or replace cross-signing flows just to hide friction

### Prefer

- explicit recovery prompts
- truthful verification state in settings and dialogs
- preserving existing trust continuity wherever local crypto state is still valid

## E2EE Diagnostics And Repair

### Expectations

Stable builds must leave enough redacted evidence to separate these failure
classes:

- missing Megolm room session keys
- requestable session keys that need `m.room_key_request`
- room keys received through to-device events
- room keys explicitly withheld by a sender
- Olm to-device failures such as `unknown one-time key`

The diagnostics layer must never log raw room keys, ciphertext, Matrix event
bodies, access tokens, or unredacted user/room/event/session identifiers.
Identifiers used for support correlation should be hashed or otherwise
non-reversible in normal logs.

### Current implementation

- `intergalactic/lib/client/matrix/matrix_e2ee_diagnostics.dart` owns the
  Matrix E2EE diagnostic subscriptions and repair helper.
- Timeline/history bad-encrypted events log hashed room, event, sender,
  session, and sender-key identifiers plus a coarse reason.
- To-device logs record receipt/request/withheld breadcrumbs with hashed
  identifiers and no key material.
- The Matrix SDK log bridge sanitizes generic SDK titles and special-cases
  Vodozemac to-device decrypt failures so raw event content is not persisted.
- The SDK decrypt-log bridge is installed during process startup before Matrix
  clients initialize, and `MatrixDecryptLogSummarizer` collapses room-decrypt
  failures, including `reason=missing_room_session` and "has not sent us a
  session key" forms, into rate-limited summaries.
- Requestable missing Megolm sessions are tracked in memory by
  room/sender/session. After repeated unresolved observations over time, the
  diagnostics emit one hash-only stale-session breadcrumb and clear it when a
  matching room key is received. This is evidence only and does not trigger
  repair, key requests, recovery, or changed decrypt timing.
- Shared log redaction removes Matrix IDs, MXC URIs, recovery-key patterns,
  and common E2EE payload fields before logs are stored. Security health,
  message backup, recovery-key unlock, repair, and decrypt retry paths must not
  log raw event objects, ciphertext, room-key payloads, device IDs, session IDs,
  recovery keys, or account identifiers; use counts, coarse states, or short
  non-reversible hashes instead.
- Manual history sharing and `m.room_key_request` responses may send forwarded
  room keys as part of the Matrix E2EE protocol, but their diagnostics must log
  only hashed room/user/device/session/key identifiers and delivery counts.
- `MatrixClient.repairEncryptionSessionsAndRetry()` refreshes one-time and
  fallback keys, refreshes SSSS cache state, runs a bounded sync, and reuses the
  existing encrypted-room retry-decrypt sweep.
- `RoomOpenDecryptRetryCoordinator` runs from the shared room-open timeline
  path used by chat and special room surfaces that load Matrix timelines
  directly, including forum, photo album, and calendar rooms. When a loaded
  E2EE room timeline contains `TimelineEventEncrypted` placeholders, it calls
  the existing room-local `retryDecryptAll()` at most once per local room every
  10 minutes. It does not run global Security repair automatically, and its
  diagnostics use only counts, coarse trigger/reason labels, and short
  non-reversible room hashes.
- Chat keeps the initial timeline loading state visible while the chat-open
  retry coordinator settles. Older-history pagination also keeps the existing
  history loader visible while the same coordinator runs with a
  `history_pagination` trigger. The coordinator keeps the normal cooldown for
  an unchanged set of failed encrypted placeholders, but a pagination pass that
  adds newly loaded encrypted event IDs may retry immediately. This is a
  presentation/retry-timing affordance only; it does not add a second decrypt
  path, fetch recovery keys, or run Security repair automatically.
- Corrupted/stale Megolm session failures are treated like a bounded repairable
  session-request case when the Matrix SDK returns a bad-encrypted placeholder
  without `can_request_session=true` but the original encrypted event still
  carries `session_id` and `sender_key`. Room retry and per-message lock retry
  request that exact room key through the existing Matrix key manager once per
  sender/session retry pass, then retry decrypt. This does not delete local
  sessions, weaken outbound key-sharing policy, auto-fetch recovery keys, or
  run global Security repair from chat-open.
- The Security encryption health panel separates Matrix verification from
  recovery/key-backup readiness. A session can be verified by emoji and still
  need the recovery key if backed-up Megolm history keys are not cached locally.
  Desktop keeps the full status chip set; mobile uses a compact status set so
  the health summary stays scannable on narrow screens.
- Security exposes repair and retry through one **Encrypted message tools**
  chooser. **Repair key delivery** refreshes key state, runs the bounded sync,
  and asks loaded encrypted rooms for missing keys. **Retry message
  decryption** does not fetch more keys; it retries unreadable messages with
  keys already stored on this session.
- The repair action is a delivery/cache repair, not a recovery-key substitute.
  After repair, Security prompts users to enter the recovery key when key backup
  is enabled but the backup secret or crypto identity is still not connected.

### Do not

- add verbose E2EE logging that includes event JSON or encrypted payloads
- add a second independent decrypt retry path when the serialized room sweep
  already exists
- treat repair as a guarantee that old messages will decrypt if a sender never
  shared the room key
- describe emoji verification as equivalent to recovery-key entry; emoji
  verification establishes device trust, while recovery unlocks historical
  backed-up room keys

## Outbound Key-Sharing Policy

### Expectations

Outbound encrypted-room key sharing should remain strict by default. Users may
enable the compatibility key-sharing toggle when they need to send messages to
trusted contacts whose new sessions are not verified yet, but that choice must
be explicit and visible in Security settings.

### Current policies

- `cross_verified_if_enabled` maps to
  `ShareKeysWith.crossVerifiedIfEnabled` and is the default.
- `all_non_blocked` maps to `ShareKeysWith.all` for compatibility.
- `cross_verified` maps to `ShareKeysWith.crossVerified`.
- `directly_verified_only` maps to `ShareKeysWith.directlyVerifiedOnly`.

Changing this setting affects future outbound room-key sharing for the local
client. It does not recover old messages by itself and does not override
explicitly blocked devices.

## Encrypted History Sharing

### Current implementation

- `intergalactic/lib/client/matrix/matrix_history_sharing.dart` owns the
  Inter Galactic history-sharing service.
- `/sharehistory` is an admin rescue command for joined users who lost room
  keys. It accepts explicit Matrix user IDs and, when the room has exactly one
  other joined member, can infer that single target. Validation failures are
  shown as command guidance instead of falling through to the generic message
  send error. After admin confirmation, the command sends locally available
  `m.forwarded_room_key` sessions immediately to target devices eligible under
  the sender's current Matrix key-sharing policy, then listens briefly to the
  Matrix SDK `onRoomKeyRequest` stream for new `RoomKeyRequest` objects from
  the same joined targets.
- A deliberate break-glass confirmation can allow a specific policy-ineligible
  requesting device during `/sharehistory`, but it is never automatic and the
  dialog explains the risk first.
- When an admin invites a user to an encrypted room whose
  `m.room.history_visibility` is `shared` or `world_readable`, the app attempts
  an MSC4268-style `io.element.msc4268.room_key_bundle` to-device message. The
  bundle payload is encrypted into an uploaded media file and sent only through
  Olm-encrypted to-device messages to devices eligible under the sender's
  current Matrix key-sharing policy. Bundle file metadata includes both the
  plaintext bundle size and the encrypted upload size; import rejects missing,
  mismatched, or over-limit sizes and downloads the encrypted file through a
  capped streaming fetch instead of an unbounded media download.
- Invite-time sharing refreshes the target user's device keys, then reads the
  refreshed Matrix device-key cache directly instead of requiring the invitee to
  already appear in the local room participant cache. If bundle delivery is
  skipped because there are no policy-eligible target devices, no local
  sessions, or a send failure, the inviter gets a warning while the invite
  itself remains successful.
- The current `m.room.history_visibility` value is exposed in Room Settings ->
  Security -> Room History. Room Settings -> Permissions -> History Visibility
  controls the power level required to change that value.
- Invite acceptance attempts to import a pending bundle from the inviter. If
  the bundle arrives just after the local join completes, the active-session
  listener retries import for the joined room while preserving the accepted
  inviter as the sender boundary when it is known. A bundle is rejected if it is
  unencrypted, expired, for the wrong room, from the wrong inviter, from an
  unknown sender device or a sender device that is not eligible under the
  receiver's key-sharing policy, malformed, corrupt, oversized, size-mismatched,
  or not marked as shared history.
- Pending bundles are held only briefly in memory for the active app session.
  This avoids plaintext preference storage and Matrix account data, but it
  means an app restart between invite receipt and join can miss the bundle.
- The same history-sharing runtime also listens to Matrix SDK
  `onRoomKeyRequest` events. If a joined user requests a specific missing
  Megolm session in an encrypted room whose history visibility is `shared` or
  `world_readable`, and this local device has permission to change history
  visibility, Inter Galactic can automatically answer the concrete request
  with a locally available `m.forwarded_room_key` for the requesting device.
  This covers users who joined through a non-Inter-Galactic invite path or
  missed the invite-time bundle.

### Policy

- Full-history room visibility in encrypted rooms means admins may share locally
  available historical Megolm keys with newly invited devices that pass the
  sender's Matrix key-sharing policy. It does not make old encrypted room
  events plaintext or server-readable.
- Automatic invite sharing follows the SDK's `DeviceKeys.encryptToDevice`
  policy. With Inter Galactic's default `cross_verified_if_enabled` setting,
  devices cross-signed by the invitee's own master key can receive history
  without requiring member-to-member verification in Inter Galactic; explicitly
  blocked or policy-ineligible devices are excluded.
- Manual rescue remains admin-driven and joined-target scoped. Policy-eligible
  devices can receive locally available sessions immediately after
  confirmation; policy-ineligible devices still require an explicit
  per-request break-glass confirmation.
- Automatic request-response sharing is deliberately narrower than
  `/sharehistory`: it answers only concrete SDK room-key requests, only for
  joined users, only in full-history encrypted rooms, only from devices with
  history-visibility permission, and never uses break-glass for
  policy-ineligible devices.
- Logs must use counts and short hashes only for room, user, device, session,
  sender-key, and MXC bundle identifiers.

### Remaining SDK work

- The current app-side bundle path adds `org.matrix.msc3061.shared_history` to
  exported bundle payloads, but the Matrix Dart SDK dependency still needs
  upstream or vendored support to mark outbound `m.room_key` sessions at
  creation time and rotate outbound Megolm sessions when history visibility or
  membership changes make old-session reuse unsafe.
- Live validation must confirm Alice invite-share to Bob, non-shared
  visibility behavior, policy-ineligible device exclusion, automatic
  request-response recovery after a non-Inter-Galactic invite path,
  `/sharehistory` rescue, and leave/kick rotation behavior on real Matrix
  accounts.

## DM-Scoped Stories

Dedicated current-state architecture reference: `../features/dm-stories.md`.

### Current implementation

- `intergalactic/lib/client/components/stories/story_component.dart` defines
  the app-facing story abstraction, parser, upload model, active-story stream,
  and per-account viewed-state contract.
- `intergalactic/lib/client/matrix/components/stories/` implements v1 stories
  as custom room events in existing direct-message rooms. The event type is
  `chat.intergalactic.story.photo`; content includes `v: 1`, a stable
  `story_id`, `created_at`, `expires_at`, image `info`, and Matrix media
  metadata.
- Story media is photos only. Inter Galactic hides malformed, redacted,
  oversized, non-image, future-invalid, and expired story events. The UI treats
  `expires_at` as authoritative and prunes active views after 24 hours.
- Encrypted DMs manually encrypt the uploaded image bytes with the Matrix SDK
  file-encryption helper before upload. The custom story event then carries
  encrypted Matrix `file` metadata instead of a plaintext `url`; the custom
  room event itself is still sent through the normal encrypted-room send path.
- Story rendering must not call the SDK's normal event attachment downloader,
  because that helper accepts standard attachment event types and rejects the
  Inter Galactic custom story type. The Matrix story component downloads the
  MXC from the parsed story metadata and decrypts encrypted `file` payloads
  directly before handing bytes to the image cache.
- Plain custom story events are intentionally not `m.room.message` events, so
  Inter Galactic timeline rendering treats them as hidden/unknown control
  events rather than ordinary chat images.
- V1 story events are hidden from room, DM, and space notification badges in
  Inter Galactic. This is a local client display policy; server unread counts
  can still include the underlying custom room events until the room is read.
- The sender's private account-data key
  `chat.intergalactic.stories.outbox.v1` stores the active outbox and recipient
  room/event IDs for delete/expiry redaction. It stores only story metadata and
  media summary needed for management; encrypted file keys are not copied into
  account data.
- Viewed story IDs are tracked per account under
  `chat.intergalactic.stories.viewed.v1` so Home can show accent rings for
  unseen stories and muted rings for seen stories.

### Policy

- v1 story visibility is existing DM contacts at upload time. Newly created
  DMs receive future stories only; there is no public discovery, selected
  audience picker, room backfill, or server-side story index.
- Expiry is an Inter Galactic client policy plus best-effort redaction of the
  sender's own recipient events while that sender app is online. Homeservers
  may retain media or remote history according to normal Matrix retention and
  redaction behavior.
- No server-side work is required for v1 beyond standard Matrix media upload,
  encrypted room events, sync/history, private account data, and redaction.

### Validation requirements

- Real-account validation must cover encrypted DM media decryption on recipient
  devices, multi-photo viewer navigation, long-press DM navigation, delete
  redaction sync, and expiry disappearance.
- Story logs and diagnostics must not log Matrix IDs, event IDs, MXC URLs,
  encrypted file keys, ciphertext, or account-data payloads in raw form. Use
  counts and short hashes if troubleshooting is needed.

## Biometric Recovery Key Storage

### Scope

Biometric recovery-key storage is an optional iOS/Android account-recovery
helper. It stores a user-entered existing Matrix recovery key locally on the
device so the user can unlock it later with platform biometrics when the normal
Matrix recovery flow asks for that key.

This is a convenience copy only. It is not server-side escrow, not an audited
cryptographic recovery product, and not a replacement for keeping an external
backup copy.

### Current implementation

- `intergalactic/lib/client/matrix/biometric_recovery_key_store.dart` owns the
  Dart storage boundary, account-scoped storage key derivation, legacy
  current-device fallback, and validation-before-save flow.
- The native iOS bridge is `chat.intergalactic.app/secure_recovery_key` in
  `ios/Runner/AppDelegate.swift`.
- The native Android bridge uses the same
  `chat.intergalactic.app/secure_recovery_key` channel in
  `android/app/src/main/kotlin/chat/intergalactic/app/SecureRecoveryKeyStore.kt`.
- New stored items use a v2 SHA-256-derived account scope from normalized
  homeserver origin and Matrix user ID. The Matrix device ID is intentionally
  excluded so the same local biometric copy can be found after an explicit
  sign-out followed by a new Matrix device session on the same app install.
- Legacy v1 records that were scoped by homeserver, Matrix user ID, and Matrix
  device ID remain readable while the old client/device ID is still known.
  Status and unlock checks prefer v2, then fall back to the current-device v1
  record. New saves write only v2. Normal account-specific delete removes v2
  plus the current-device v1 record when that legacy scope can be derived.
- Explicit Settings sign-out routes use the shared biometric recovery-key
  logout prompt before calling normal client logout. This currently covers the
  app-level Logout button and Account Management account rows. If a stored key
  exists, the user must choose `Keep key and sign out`, `Delete key and sign
  out`, or `Cancel`. Keeping a legacy-only v1 key migrates it to v2 before
  logout. Keep is only offered when the stored key status is currently
  readable; if biometric unlock/authentication is unavailable, cancelled, or
  migration fails, logout is aborted. Deleting removes both the v2 and
  current-device legacy v1 records before logout.
- Matrix soft-logout, token drift, and session-repair paths must not delete the
  biometric recovery-key copy. Persistence across those paths is intentional so
  the user can recover E2EE state after accidental session loss.
- Native iOS/Android bridge methods accept exact storage keys for normal
  status, write, read, and account-specific delete. They also expose an
  explicit delete-all cleanup for the app's secure recovery-key namespace only:
  Android clears the dedicated recovery-key SharedPreferences file plus
  Keystore aliases with the recovery-key prefix, while iOS deletes every
  Keychain item under the recovery-key service. This is reserved for the
  Security emergency cleanup action and is not used by normal keep/delete
  logout choices.
- iOS uses a Keychain generic-password item with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, `kSecAttrSynchronizable=false`,
  and `biometryCurrentSet` access control. A biometric enrollment change should
  make the stored item unavailable and require delete/re-entry. Updating an
  existing local copy uses Keychain add-or-update semantics so a failed
  replacement attempt does not delete the prior stored key.
- iOS status checks are non-prompting. `errSecInteractionNotAllowed` means the
  Keychain item exists but requires a biometric prompt to read, so Dart should
  still receive `stored=true` and show Unlock. Auth/decode failures continue to
  mark the item as `biometry_changed_or_unavailable`.
- Android uses Android Keystore AES-GCM keys with the hashed account scope as
  the alias suffix. Key use requires `BIOMETRIC_STRONG`; this prototype does
  not allow device-credential fallback. `BiometricPrompt.CryptoObject` gates
  both encrypt/write and decrypt/read. The app stores only IV, ciphertext, and
  best-effort metadata in a private app SharedPreferences file. Plaintext
  recovery-key material is passed only through memory during the explicit
  setup/unlock flow.
- Android key generation tries StrongBox when the device reports support and
  falls back to the normal Android Keystore if StrongBox is unavailable.
  Status may report `platform: android`, `biometricStrongAvailable`,
  `hardwareBacked`, and `strongBoxBacked` when the native layer can determine
  those values.
- The setup UI is part of the normal opt-in Security > Cross Signing & Backup
  flow on supported iOS/Android devices. It is hidden on desktop because the
  secure biometric recovery-key storage bridge is mobile-only. It is no longer
  hidden behind Developer Mode or the `biometric_recovery_key_unlock`
  experiment.
- The sign-in screen accepts only account credentials. Recovery-key entry is
  deferred until Matrix credentials are accepted and the post-login recovery
  prompt determines that encrypted history or identity recovery is needed.
  That prompt lets the user enter a recovery key, unlock a stored key with
  biometrics, or set up/update/delete the local biometric-protected copy.
- Setup validates the entered key before writing to native secure storage. If
  the Matrix crypto identity is not connected, it uses the existing
  `restoreCryptoIdentity` recovery path. If the user has already completed
  message-backup recovery and the identity is connected, it validates the
  secret directly against the current SSSS key instead of rerunning the restore
  helper.
- Retrieval is explicit. Security restore and post-login recovery can show an
  "unlock stored key" action, but the app does not silently read or use the key
  at startup.
- If a biometric-unlocked stored key fails Matrix recovery after sign-in, the
  post-login recovery dialog treats the local copy as possibly stale and points
  the user to update it with the current recovery key or delete the local copy.
  This does not auto-delete the copy because a failed Matrix recovery attempt
  can still be caused by transient sync or crypto-state loading.
- Remaining release validation must prove iOS and Android save, unlock, cancel,
  account-specific delete, delete-all emergency cleanup, legacy migration,
  explicit keep/delete/cancel logout from every user-visible sign-out route,
  stale stored-key update/delete after failed Matrix recovery, soft
  logout/session drift, biometric enrollment invalidation, recovery-key
  rotation handling, and app uninstall/data-clear behavior on real devices or
  emulators.

### Guardrails

- Do not upload recovery keys.
- Do not write recovery keys to Matrix account data, SharedPreferences, logs,
  analytics, crash reports, or bug reports.
- Do not include recovery keys in diagnostics. The log redactor includes
  recovery-key field and grouped-key pattern coverage as a belt-and-suspenders
  guard.
- Keep storage opt-in and user-driven. The app may offer setup in the normal
  post-login recovery and Security flows, but it must not silently read or save
  a key without an explicit user action.
- Android enrollment changes, unavailable strong biometrics, corrupted
  ciphertext metadata, or Keystore invalidation must fail closed. The user may
  delete the local copy and re-enter the recovery key, but the app must not
  fall back to plaintext storage.

## Multi-Account Isolation

### Expectations

Each account must keep its own:

- session identifiers
- crypto state
- push registration
- room/account routing
- local restore metadata

Relevant current code areas:

- `intergalactic/lib/client/client_manager.dart`
- per-client Matrix wrappers under `intergalactic/lib/client/matrix/...`
- notification routing code

### Do not

- share restore hints across accounts
- let one account's notification key or pusher registration overwrite another
- mix room-specific state with the wrong active client

## Web Persistence Risks

Web/browser storage is the most fragile target for restore and encrypted continuity.

Relevant visible code areas:

- `intergalactic/lib/client/matrix/web/web_session_bootstrap.dart`
- `intergalactic/lib/client/matrix/web/matrix_client_registry_html.dart`
- `intergalactic/lib/client/matrix/auth/web/...`
- web-only notification code under `intergalactic/lib/client/components/push_notification/web/...`

### Risks to assume

- browser-managed storage eviction
- partial IndexedDB loss
- stale preferences surviving when Matrix DB state is gone
- service worker or browser lifecycle waking code at inconvenient times
- web-only imports leaking into shared code

### Review checklist for web changes

- inspect conditional imports
- inspect IndexedDB and registry code
- inspect restore/bootstrap classification logic
- inspect any notification or service-worker wake path
- verify encrypted state is either healthy or routed into recovery, not silently half-broken

## Defensive Review Checklist

Before merging changes in this area, verify:

- login still succeeds
- restore still picks the correct account
- encrypted rooms still decrypt after restart when state is intact
- verification flows still reflect real trust state
- session repair does not fight with verification
- logout/reset cleanup does not damage unrelated accounts
- web/browser restore still fails closed when storage is missing

## Common Triggers For Full Review

- edits in `client_manager.dart`
- edits in `matrix_client.dart`
- changes to login pages or account bootstrap
- changes to conditional web restore code
- changes to key verification or cross-signing UI
- changes to storage assumptions, migration, or preferences keys

## TODOs To Verify In Repo

- Verify the current secure-storage/native-secret-storage path for Android and iOS before documenting platform-specific storage backends more narrowly.
- Verify the current desktop persistence path if a future fix depends on concrete filesystem locations rather than logical restore behavior.
