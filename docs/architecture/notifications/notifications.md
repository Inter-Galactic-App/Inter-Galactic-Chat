# Notifications

## Purpose

This file documents the notification architecture across Android, iOS, Web,
macOS, and Desktop.

Use it when changing:

- token/subscription registration
- notification permissions
- click/open routing
- account/session routing
- badge counts or room notification policy
- background notification handling

## Architecture Summary

Notification handling is split into:

- shared notification policy and routing in Dart
- platform-specific notifier implementations
- Matrix pusher registration for the active client/account
- UI navigation and click response handling

Current visible code areas:

- `intergalactic/lib/client/components/push_notification/...`
- `intergalactic/lib/client/matrix/components/push_notifications/matrix_push_notification_component.dart`
- `intergalactic/lib/service/background_service.dart`
- `intergalactic/lib/service/background_service_notifications/...`
- `intergalactic/lib/ui/pages/settings/categories/app/notification_settings/...`
- `intergalactic/lib/main.dart`

## Shared Responsibilities

The shared layer should own:

- notification content models
- room/account/session routing
- rules for suppressing or allowing notifications
- notification identity and grouping rules
- navigation targets after click/open
- privacy decisions about what content is safe to show

The shared layer should not assume one OS delivery model.

## In-app unread projection after a read marker

`MatrixRoom` is the shared unread-count source for Inbox and Favorites. The
pinned Matrix SDK sends read markers to the server but replaces its cached
notification and highlight counts only on sync. After a successful explicit
room or Inbox read, the room therefore temporarily projects counts past the
exact marked event and emits `onUpdate`; a failed marker changes nothing.
Inbox snapshots freeze the exact target event ID; the room checks cached
newest-first event order, not millisecond timestamps, so a newer notification
remains visible even when it shares the target's `origin_server_ts`. The
Inbox cache scan also stops at that accepted target while the SDK's
`m.fully_read` cache catches up, so an older marked direct mention cannot
reappear in the mention-only filter.

The projection uses the pre-request SDK counts and a bounded, in-memory set of
notification event IDs. A stale pre-marker sync retains the projection. It
retires when a sync confirms the target with converged or partially reduced
unread counts, or when explicit room account data reports a different marker
from both the target and the marker present before the request. This affects in-app
counts, not Android/iOS notification-tray cancellation, which has its own
platform path and rebuilt-device validation.

## Room Notification Snooze

Per-chat snooze is a local Inter Galactic notification policy. Snooze records
are stored in device-local preferences as account/room entries keyed by Matrix
client id plus room id, with an absolute `snoozed_until_ms`, creation time, and
source label. The built-in durations are 30 minutes, 1 hour, 8 hours, and 24
hours.

`NotificationModifierRoomSnooze` runs before platform notifier handoff. It
suppresses message, story, and calendar reminder notification content for the
snoozed room while the snooze is active. Call/ring notifications intentionally
bypass this first version so temporary chat snooze does not hide an incoming
call; add a separate product decision before changing that behavior.

Users can manage snoozes from App > Notifications active-snooze cards, room
notification settings, DM long-press context menus, and supported
Android/iOS/macOS local notification actions. Android adds snooze actions to
local message, story, and calendar notifications. iOS and macOS register local
notification categories with the same actions and apply them to local message,
story, and calendar notifications. The shared notification response handler
stores the snooze from the action payload and clears active local notifications
for the room when the room is available.

Snooze does not mutate Matrix push rules, mark rooms read, change unread
counts, alter server-side pushers, store plaintext message content, or sync to
other devices. Expired entries are ignored during reads and pruned when the app
notification settings page opens.

## Mobile Rich Message Notifications

`MessageNotificationContent` separates the legacy message body from a mobile
attachment presentation. Android and iOS use that presentation for the first
attachment only: `Sent an image`, `Sent a video`, `Sent a file`, or `Sent a
GIF`. App-picker pack media also uses `Sent a sticker` for static PNG/WebP
stickers; GIF and animated-WebP picker media use `Sent a GIF`. A real caption
follows the type label for normal attachments, while generated filename bodies
are not displayed. This preserves the existing desktop/companion message-body
contract.

Matrix picker media has two supported event shapes. Normal mode sends
`m.sticker`; sticker compatibility mode sends `m.room.message` with
`msgtype: m.image` and `chat.commet.type: chat.commet.sticker`. Android FCM's
background fetch/decrypt path must recognize both before notification-content
conversion and retain a `MatrixMxcImage` for rich preview staging. The
`chat.commet.animated` flag is authoritative for picker animation when the
downloaded representation is WebP; a `.gif` body is also treated as animated.
Ordinary `m.image` messages continue through the normal attachment path.

The existing preview preference is the privacy boundary. Private notifications
are reduced to `New message`, have no attachment presentation or preview, and
must not offer Reply. Rich notifications may show their normalized type/caption
and image/GIF preview; the lock screen remains subject to the device's own
notification settings.

Android keeps `MessagingStyleInformation` for both normal and bubble-enabled
message notifications. When a Rich image/GIF/sticker preview is available, its
message data carries a protected app `FileProvider` URI, so the conversational
history, Reply action, and existing Mute action stay intact. Preview files live
in the app cache and are bounded by age cleanup. Android Reply deliberately
uses `showsUserInterface: true`: the foreground launch receives submitted
`RemoteInput` before dispatching it to the serialized inline-reply handler.

iOS Rich notifications use a Darwin text Reply action and a foreground Mute
action. Mute follows the normal notification route into the target room's
existing Notifications settings tab, which retains the full duration picker;
Private notifications keep the direct existing duration actions. The iOS
native callback bridge forwards typed input to `NotificationResponseHandler`,
which serializes sends with Android inline replies. Rich preview files are
created only after redaction, use iOS file protection, and are age-cleaned; a
preparation/protection failure omits the preview rather than notification text
or actions.

## Story Badge Suppression

DM-scoped stories use `chat.intergalactic.story.photo` and
`chat.intergalactic.story.video` custom room events rather than normal chat
messages. Story reactions use `chat.intergalactic.story.reaction`. For v1,
Inter Galactic suppresses those story events from local room, DM, and space
badge counts so posting or reacting to a story does not light up every DM-style
room. The suppression is display-only and subtracts known unread story markers
from Matrix's raw unread count; it must not mark the room read or hide ordinary
messages.

During the initial post-login story refresh, story-capable DM rooms suppress the
raw badge count until their local/history story marker scan finishes or fails.
The room is then refreshed back to exact marker-based suppression, preventing a
startup sidebar badge flash without sending receipts or changing server unread
state.

Story notification preferences live in private account data under
`chat.intergalactic.stories.notification_settings.v1` and are edited in App >
Notifications. These settings prepare app-side story post/reaction alerts
after sync/decrypt. Live story events that pass those settings are delivered
through `NotificationManager` as story-specific local notification content;
Windows, Android, iOS, and macOS render story notifications without message
reply actions. Windows, iOS, and macOS can suppress the story sound directly;
Android marks the story notification silent when the setting is off. Story
notification taps carry a shared story-open route with client, room, story
sender, story id, and optional story event id so taps open the full-screen story
viewer instead of the sender DM. If the target story is no longer active or
cannot be resolved, the app falls back to the carrying DM room. Story post
delivery dedupes one logical story per account, sender, and `story_id` before
the platform notifier handoff, because the same upload can appear as separate
Matrix events in multiple DM rooms. Photo stories and video stories
(`chat.intergalactic.story.video`) use this same shared route, dedupe rule, and
fallback behavior. The settings do not change Matrix push rules, pusher
registration, platform background delivery, or server unread counts.
For native iOS/APNs tap responses, the shared Dart handler keeps the native
`response_id` pending until `MainPage` confirms the story viewer route has
started or the stale-story fallback room is selected.

See `../features/dm-stories.md` for the current story event contract, marker lifetime,
account-data settings shape, and badge-suppression boundaries.

## Desktop Notification Companion

The desktop notification companion is an opt-in local display surface for
approved message notifications on supported desktop platforms. It listens after
`NotificationManager` passes `enableNotifications` and all registered
notification modifiers. If a notification is suppressed by normal policy, the
companion receives nothing.

The companion still uses the normal approved-notification pipeline and does not
change local notification sounds, pusher registration, Matrix push rules, or
click response handling. While the companion host is available and the
companion is enabled, the Windows notifier suppresses native message
notifications so the same approved message is not displayed in both the
companion and a system notification. Call and calendar reminder notifications
stay native. Companion clicks route through
`EventBus.openRoomFromNotification((roomId, clientId))`.

The companion host is currently Windows-only. macOS keeps its normal local
notification path even though the companion settings tab is visible there.

macOS local notifications use `MacosNotifier` and Flutter's Darwin/macOS local
notification APIs. This path requests local alert, badge, and sound permission,
does not need a push token, returns no extra Matrix pusher registration data,
and routes message, story, call, membership, invite, error, and calendar
notification taps through the shared notification response handler.

Foreground client sync reconciles pending companion messages with current room
notification state. When another device marks a room read and the desktop
client syncs the cleared unread count, the companion removes matching pending
messages instead of waiting for the user to open the room on desktop.

Companion preview redaction is local to the overlay. When companion previews are
disabled, or when screen-sharing privacy mode applies to a newly approved
notification, the overlay shows a generic `New message` state instead of body
text.

## Platform Responsibilities

### Android

Primary code areas to inspect:

- `intergalactic/lib/client/components/push_notification/android/...`
- `intergalactic/lib/service/background_service.dart`
- `intergalactic/android/` for manifest/services/permissions

Key concerns:

- permission and channel setup
- push gateway / UnifiedPush registration
- token refresh
- foreground service/background task behavior
- click routing back into the correct account and room

Android has two delivery modes:

- FCM data-only builds use `FirebasePushNotifier`, the Matrix pusher app id
  `chat.intergalactic.app.android`, and the configured push gateway endpoint.
- Non-Google builds use `EmbeddedNtfyNotifier`, register the same Inter
  Galactic Android app id, and use an embedded ntfy topic URL as the Matrix
  push key.

Legacy Android pushers using `chat.commet.commetapp.android` or
`chat.commet.app.android` are stale migration artifacts and should be deleted
when the active Android client refreshes pushers. Do not preserve them as a
fallback; they point the Matrix push gateway at the wrong app registration.
In Google Services builds, same-app Android pushers with URL-shaped pushkeys are
also stale embedded-ntfy artifacts and should be deleted even if their Matrix
device display name differs from the current install.
This stale URL/legacy cleanup should still run when the current FCM token is
temporarily unavailable; in that case it must remove only globally stale
Android URL/legacy pushers and leave existing non-URL FCM pushers intact.

FCM builds are the default Android release path. The Android release flow runs
`intergalactic/scripts/set_google_services.ps1 enable`, then runs `flutter pub
get` and forwards the FCM flags to the Android build. The toggle
enables Firebase dependencies, the Gradle Google Services plugin, Firebase
imports, and `lib/firebase_options.dart`. Before web package resolution, run the
same toggle in `disable` mode so browser builds use Web Push without compiling
Android-only Firebase Messaging packages.

### Background service readiness

`lib/service/background_service.dart` has two initialization callers on Android:
the service's automatic embedded-push startup and the foreground isolate's
explicit `init` request. Both share a `BackgroundServiceInitGate`. The first
caller registers the `on_message_received` task listener and completes the
notification manager initialization; concurrent callers await that same future
before emitting `ready`. A failed initialization clears the gate so a later
start can retry. The foreground isolate subscribes to `ready` before sending
`init`, so a fast service start cannot emit the only readiness signal before
the task queue listener exists. Keep queued background tasks behind this
readiness boundary; do not invoke `ready` from a duplicate-init fast path.

FCM must stay a data-only delivery path. Android should not render FCM
notification title/body fields directly for Matrix messages because encrypted
events require local event fetch/decryption first. The FCM background handler
uses the decrypt-capable `BackgroundNotificationsManager` path because encrypted
message previews must be resolved locally before display. Firebase wakes the app
for the
configured push-gateway Matrix push payload, the app validates `room_id` /
`event_id`, fetches/decrypts locally, then shows a local notification.
Malformed or unexpected Firebase payloads should be logged instead of displayed
to users as raw diagnostic text. Background-service Matrix clients must use
only a bounded wake sync for event/to-device room-key processing and must not
leave continuous Matrix background sync running after the notification wake.
The bounded wake sync is also persistently rate-limited per Matrix client so
rapid Android bubble/inline-reply use cannot repeatedly start full background
sync/key-upload work across Firebase isolate restarts. Duplicate FCM deliveries
for the same `room_id` / `event_id` are ignored inside the Firebase isolate,
and notification inline replies are serialized through the shared response
handler before sending. Android bubble entrypoints mark themselves as bubble
sessions and use the same per-client limiter for startup `oneShotSync` calls so
rapid room-to-room bubble launches do not each force another Matrix startup
sync while the normal main app startup path remains unchanged.

For Firebase, the Android package name must match the Gradle app id
`chat.intergalactic.app`. The Matrix pusher app id remains
`chat.intergalactic.app.android`; do not use the Matrix pusher id as the
Firebase Android package.

The Google Services Gradle plugin prefers variant-specific files such as
`android/app/src/release/google-services.json` over the top-level
`android/app/google-services.json`. These files are owner-local build inputs,
not public source-control files. Keep release/debug Google Services files
aligned with the intended Firebase project before packaging, or the APK can
ship stale sender/app IDs even when the top-level file is correct.

Android app-data backup/transfer is disabled in the manifest because restored
SharedPreferences can revive old push transport state after an uninstall. The
app also records `android_push_transport_mode`; when the compiled mode changes
between FCM and embedded ntfy, `Preferences.init()` updates the active mode but
keeps inactive transport credentials. The active notifier refreshes its own
token/topic after startup, and retaining inactive values avoids orphaning push
subscriptions if the user or build switches back before the new transport is
confirmed working.

Runtime Android notification small icons, screen-share foreground-service
notifications, and embedded-push foreground-service notifications should use
`@drawable/ig_notification_icon`, a white Inter Galactic vector that is kept by
`android/app/src/main/res/raw/keep.xml`. The background-service plugin also has
a native initial-notification fallback at `@drawable/ic_bg_service_small`, so
`android/app/src/main/res/drawable-anydpi-v21/ic_bg_service_small.xml` must stay
aligned with the Inter Galactic notification glyph. Do not point notification
code back at legacy density PNGs if they contain older Commet artwork.

Use the embedded-ntfy/no-FCM mode only when producing a non-Google fallback
build. The Firebase service-account JSON/private
key is not an app build input; keep it on the server-side push gateway only.

FCM builds should stop the embedded-push foreground service during startup.
That service and its persistent "Listening for message notifications"
notification belong to the non-Google fallback path and should not remain
active in a default Firebase build.

Linux/server requirements for FCM:

- The configured push gateway host must terminate TLS and reverse proxy
  `/_matrix/push/v1/notify` to the custom `matrix-push-gateway` service.
- `matrix-push-gateway` must have `FCM_ANDROID_APP_ID`,
  `FCM_PROJECT_ID`, and `FCM_SERVICE_ACCOUNT_FILE` configured. The service
  sends FCM v1 data-only messages directly; Sygnal is an alternative, but is
  not required for the current Docker stack.
- The Linux compose default should resolve `FCM_PROJECT_ID` to
  `inter-galactic` and `FCM_SERVICE_ACCOUNT_FILE` to
  `/run/secrets/intergalactic-fcm-service-account.json`, matching the mounted
  secret. `/healthz` should report `fcmConfigured: true`,
  `fcmServiceAccountLoaded: true`, and
  `fcmAndroidAppId: "chat.intergalactic.app.android"` before Android FCM
  testing.
- When rejecting stale embedded-ntfy pushers for an FCM build, only treat
  `http://` and `https://` pushkeys as URL endpoint pushers. Firebase
  registration tokens can contain colon separators and must still be delivered
  through FCM.
- Do not add notification-title/body default payloads for Android FCM unless
  there is a specific product decision to let Google/Android render generic
  server-side notifications. The app expects data-only Matrix pushes containing
  `room_id` and `event_id`, then fetches/decrypts locally.
- Android message notifications should include the shared route payload and use
  the shared notification response handler for taps, cold-launch opens, and
  inline replies. Keep room/account routing centralized there instead of adding
  Android-only room lookup behavior in the notifier.
- Android story notifications use the shared story-open payload and stable
  per-story notification IDs, but intentionally do not include message reply
  actions or Android bubble metadata. They are local app-rendered notifications
  after story sync/decrypt, not a server-side encrypted story preview.

### iOS

Primary code areas to inspect:

- `intergalactic/lib/client/components/push_notification/ios/...`
- `intergalactic/lib/client/components/push_notification/notification_response_handler.dart`
- `intergalactic/lib/utils/event_bus.dart`
- `intergalactic/ios/` for entitlements, capabilities, and native registration

Key concerns:

- permission prompts
- APNs token lifecycle
- click routing and launch-from-notification behavior
- privacy of notification previews
- keeping account/session routing deterministic

The iOS host's bounded silent wake also owns the developer-only E10 backup
presence measurement. During the existing remote-wake sync,
`MatrixE2eeDiagnostics` observes decrypt failures and may probe the current
server-side room-key backup version and one room/session key. The scope allows
at most two probes, caps each at 750 ms, and skips when the existing wake
budget is too low; it finishes before the wake releases the database and does
not extend the sync deadline. It records only aggregate
`candidates/in_backup/not_in_backup/version_unusable/skipped_budget` counts.
This is host-side measurement only: it does not decrypt, import, upload, or
change key policy, and it does not involve the Notification Service Extension
or vodozemac.

iPhone notification taps should preserve room/account routing across both
local-notification payloads and APNs response payloads. The native
`AppDelegate.swift` bridge captures tapped APNs responses, normalizes
top-level and nested `room_id` / `client_id` / route-payload shapes, stores a
pending response for cold launch, and forwards warm responses over the
`chat.intergalactic.app/ios_notifications` channel. Dart then routes through
`NotificationResponseHandler.handleRemotePayload(...)` and
`EventBus.openRoomFromNotification(...)`, which queues the open request until
the main page listener exists. Do not add iOS-only room lookup shortcuts that
bypass this shared route. The shared response handler briefly de-duplicates the
same room route because iOS local-notification and native APNs callbacks can
both report the same user tap.

The app delegate must remain the active `UNUserNotificationCenter` delegate for
iOS tap capture. APNs tap payloads are retained natively until Dart either
drains them with `takePendingNotificationResponse` or acknowledges the
method-channel callback with `acknowledgeNotificationResponse`. `IosNotifier`
also re-checks the pending native payload when the app returns to the resumed
lifecycle state, because a warm/background tap can wake the app before the Dart
handler is ready to consume the first method-channel delivery.
`IosNotifier` must mix in `WidgetsBindingObserver` rather than implement it
directly, so newer Flutter SDK observer no-op methods are inherited instead of
becoming cross-platform compile requirements.
When `AppDelegate` recognizes an Inter Galactic APNs/local notification route,
it consumes the `UNNotificationResponse`, calls the iOS completion handler
directly, and schedules delivery to Dart on the `ios_notifications` channel.
Do not forward recognized Inter Galactic responses back through
`FlutterAppDelegate`, because the local notification plugin can otherwise
double-handle a foreground tap. Unknown or non-routable responses may still
fall through to the superclass/plugin path.

Native APNs tap payloads are not removed from the native pending slot when Dart
calls `takePendingNotificationResponse`. The shared Dart notification response
handler now owns the route attempt state, retries while Matrix clients, rooms,
or the main open-room listener are not ready, and only acknowledges the native
`response_id` after the target room is selected. This keeps cold-launch taps
recoverable without bypassing Matrix session restore, E2EE room resolution, or
the existing `EventBus.openRoomFromNotification(...)` route. Permanently
unrouteable native responses, such as payloads with a `response_id` but no room
route after parsing, are acknowledged as terminal failures so stale debug or
malformed APNs responses do not remain in the native pending slot forever.
When a notification targets the room that is already selected, `MainPage`
emits the selected-room success signal for that notification route without
changing the room again; this preserves the tested success path while allowing
the pending native response to clear.

Merely tapping a notification does not mark its room as read. Once the timeline
reaches its newest event, the room-read path requests notification clearing;
snoozing a room also requests clearing. `NotificationManager.clearNotifications`
and `clearNotificationsByRoute` remove Flutter-local alerts for that account
and room and ask the native iOS bridge to remove delivered APNs alerts with the
same exact `client_id` and `room_id`. The native bridge checks for a push
trigger and refuses missing route fields; other accounts and rooms remain
visible. This includes NSE generic fallbacks for the cleared room. A remote
alert lacking either routing field cannot be cleared this way, and there is no
global Notification Center clear.

Debug iOS builds expose a developer-only APNs replay harness in App >
Advanced > Developer > Notifications. The replay control calls the native
`debugReplayNotificationResponse` method, which is compiled under `#if DEBUG`
or an explicit `IOS_NOTIFICATION_DEBUG_HARNESS` Swift build flag for local
profile-mode iPhone harnesses. The method normalizes a pasted APNs `userInfo`
JSON object through the same `AppDelegate` capture path as a real tap, and then
delivers it over the normal `notificationResponseReceived` channel.
Release/TestFlight builds do not expose or implement this replay method. Debug
and explicit local harness builds also keep the last tapped APNs `userInfo`
payload in memory so Developer > Notifications can replay that exact tap
without logging or copying raw payloads into diagnostics. The optional "Load
Last" control fills the local replay text box for manual redaction and
inspection only; it should not be used to paste secrets into docs or bug
reports.

Direct debug-mode Flutter iPhone installs must be launched through Flutter
tooling or Xcode; launching a debug `Runner.app` from the home screen or via
`devicectl` can exit before Flutter initializes. When Flutter cannot attach to
the connected phone, use a local profile-mode harness build with
`BUILD_MODE=debug`, `IOS_NOTIFICATION_DEBUG_HARNESS_SWIFT_FLAG=-DIOS_NOTIFICATION_DEBUG_HARNESS`,
and `APS_ENVIRONMENT=development`. That keeps the replay UI available, signs
with sandbox APNs for development-device testing, and leaves normal
Release/TestFlight production APNs behavior unchanged.

For the developer-mode-only E10 key-backup measurement, the native silent-wake
bridge retains the APNs client, room, and event route only while that wake is
pending. Before the wake's bounded sync, Dart reads the routed encrypted event
without decrypting it and uses its transient Megolm session id for the existing
aggregate backup-presence probe. This covers wakes where to-device processing
receives the room key before a `BadEncrypted` timeline event is observable.
The route and session id are neither logged nor persisted; the probe remains
bounded by the existing wake budget and does not change the NSE, key material,
or notification rendering.

Notification routing diagnostics should remain structured and redacted. The
iOS/native and Dart route path logs payload receipt, target room/event
extraction, account/client target resolution, Matrix client readiness, router
readiness, navigation attempts, delayed retry state, and success/acknowledgment
without logging raw room IDs, event IDs, payload JSON, or message contents.

Notification-originated room opens are also tagged in the shared event bus so
`MainPage` can treat them differently from a normal user-initiated room jump.
If the app is filtered to a different account, the notification route may switch
to the notification's target client without showing the manual account-switch
dialog. If the room/client is not ready yet during cold launch, `MainPage`
retries the tagged open briefly and then surfaces the selected room by returning
to the main route and focusing the mobile timeline panel. Payload parsing should
continue to accept both `room_id` / `roomId` / `roomID` and route payload keys
such as `payload`, `route_payload`, `deep_link`, and `url` across top-level and
nested APNs/local-notification data.

Notification-originated story opens use the same account-routing discipline but
dispatch through `EventBus.openStoryFromNotification(...)`. `MainPage` refreshes
the target account's story component, opens the full-screen viewer at the
matching story id/event id, and falls back to the carrying room if the story has
expired, was deleted, or cannot be found locally. If the notification came from
the native iOS/APNs response bridge, Dart acknowledges the native response only
after the viewer route is started or that fallback room selection succeeds, so
cold-launch story taps remain retryable until navigation has been confirmed.

iOS story notifications use the shared story-open payload while keeping the
same per-room thread identifier as message notifications for grouping and
clearing. They respect the story sound toggle through
`DarwinNotificationDetails.presentSound`, and they do not add reply actions or
iOS-only story routing shortcuts.

iOS push registration is intentionally self-healing on app startup. When the
user has notification permission, `IosNotifier` registers for remote
notifications, waits briefly for APNs to return the current device token, and
forces Matrix pusher reconciliation even if the token string appears unchanged.
Native `pushTokenUpdated` callbacks force the same reconciliation, including a
queued second pass if a refresh is already running. Native
`pushTokenRegistrationFailed` clears the cached token and triggers Matrix
pusher reconciliation so same-install APNs pushers can be pruned instead of
leaving a dead token behind after an app update.

Matrix pusher cleanup treats iOS APNs rows similarly to Android transport
migrations but stays scoped to Inter Galactic/iOS identities. Same-install iOS
pushers are identified by Matrix `device_id`, matching device display name, or
the current APNs push key paired with the Inter Galactic iOS pusher app id.
If APNs cannot provide a current token after registration, same-install iOS
pushers are considered stale and removed; unrelated iOS pushers are left alone.

iOS Runner background modes intentionally include `remote-notification` for
APNs wake/local notification rendering, `fetch` so the app can participate in
iOS Background App Refresh / `BGAppRefreshTask` style refresh eligibility, and
`audio` for supported media/call behavior. The Runner target also keeps the
Xcode Background Modes capability enabled. Do not add `processing` unless the
app introduces a real long-running `BGProcessingTask` use case; Matrix message
notification decryption should stay on the APNs wake/fetch-local-render path
rather than deferred processing.

#### Notification Service Extension (local decrypt, NSE Phase C)

`ios/InterGalactic Notification Extension/NotificationService.swift` is the
iOS half of the documented push-privacy model: the gateway sends routing
identifiers only, and the extension turns them into a readable notification
on the device without the app running. It is invoked only when the APNs
payload carries `mutable-content: 1`, which is a gateway change owned by
SERVER; without it the extension is inert and the generic alert shows.

The six media-placeholder bodies use the extension's `Localizable.strings`,
generated during its Xcode target build from the host `assets/l10n/intl_*.arb`
files. The policy snapshot carries no presentation strings. English source
keys are required; a missing locale value uses the explicit English default
in Swift. All 19 non-English host ARBs now supply these six keys. An unsigned
iPhoneOS build from app commit `698ad982` packaged all 20 locale catalogues
in the notification extension; each parsed with exactly six media-body keys.
This verifies generation and bundle placement, not runtime locale selection,
translation quality, signed-payload identity, or notification delivery.

The pipeline:

1. **Payload validation.** `client_id`, `room_id` and `event_id` are
   bounded by length, matched against Matrix identifier grammar, and
   percent-encoded into the request path. No fallback to "the first client".
2. **Policy first.** The extension reads
   `<App Group>/notification-policy/policy.json`, written by the host through
   `NotificationPolicySnapshot` (`lib/client/components/push_notification/ios/`)
   every time a watched preference changes, before the preference write
   returns (`Preference.afterWrite`). Missing, malformed, oversized, or
   undecidable snapshot, notifications muted, Mentions-only mode, a snoozed
   room, or the private preview choice: the gateway payload is delivered
   unmodified. Room snoozes are matched by HMAC-SHA256 digest of
   `clientId::roomId` under a key carried in the file, so the snapshot names
   no room. The snapshot is deleted on data reset and when the last account
   is removed, and rewritten on other account changes.
3. **Database, read-only.** `<App Group>/db/account/drift/<client_id>/data.db`
   is opened `SQLITE_OPEN_READONLY` with a 1.5 s busy timeout, and exactly one
   `client_data` row supplies the homeserver, the token and the user id.
   Failures are classified by extended result code (busy, cantopen, corrupt)
   for a diagnostic counter that is pre-registered but not yet built.
4. **Fetch.** `GET /_matrix/client/v3/rooms/{room}/event/{event}` against the
   stored homeserver only, HTTPS only, no redirects, 8 s request and 12 s
   resource timeouts, 2 MB body cap. Only an iOS request timeout may trigger
   one retry within the original event-fetch envelope; all other failures
   stop. Developer Mode records only the bounded attempt count. 401 and 403
   stop the extension; it never refreshes or writes a token, and holds it in
   memory only.
5. **Decrypt.** `m.megolm.v1.aes-sha2` only, through vodozemac's
   `ios_decrypt_event` with the session pickle from the same database and the
   pickle key derived exactly as `pickle_key.dart` does (UTF-16 code units,
   low byte, padded or truncated to 32). A missing session, an Olm-only
   event, or any library error is an ordinary failure: generic, no retry.
6. **Gates mirrored from `shouldNotify`.** Self-sent events and events older
   than ten minutes deliver generic.
7. **Render, once.** A fresh mutable copy gets title (sender display
   name from `room_members`, else the localpart), subtitle (room name from
   room state, if any), body (text, or the media presentation such as
   "Sent an image"), `threadIdentifier = clientId::roomId` to match the
   host's own notifications, and the rich message category so Reply and
   Mute work. It is handed over in one assignment; the gateway content is
   never mutated and is what `serviceExtensionTimeWillExpire` delivers.
8. **Logging.** `os.Logger` lines carry a stage, an outcome class and
   integer codes, all literals or numbers. Nothing event-derived, no path, no
   origin, no library error string.

Not in the first revision, by decision rather than omission: image
attachments (needs the authenticated media download plus AES-CTR
attachment decryption, which the vodozemac ABI does not provide), Mentions
mode (needs a per-event highlight signal in the payload), and the diagnostic
counter above. The target is `APPLICATION_EXTENSION_API_ONLY`, links the
vodozemac archive through `-force_load` and the system `sqlite3`, and must
never depend on the `flutter_vodozemac` pod, which pulls `Flutter.framework`.

### Web

Primary code areas to inspect:

- `intergalactic/lib/client/components/push_notification/web/...`
- `intergalactic/web/`
- `intergalactic/lib/main.dart`

Visible current pieces include:

- web push notifier
- service worker registration
- web push bridge for service-worker messages
- app badge management

Key concerns:

- browser permission flow
- service worker registration scope
- stored subscription state
- click routing when the app is cold or storage is partially gone
- conditional imports staying web-only

### Desktop

Verify current path per platform before editing native integration details.

Likely ownership split:

- shared Dart notification logic stays in `lib/client/components/push_notification/...`
- desktop runner/platform folders under `intergalactic/windows/`, `intergalactic/linux/`, and `intergalactic/macos/` own native registration or activation behavior where needed

Key concerns:

- launcher activation and focus behavior
- notification click routing into the right account/room
- differences between Windows, Linux, and macOS desktop notification facilities
- Windows and Linux message notifications silence the OS notification audio and
  play local app-managed sounds through `media_kit`. The global notification
  sound is stored in `custom_notification_sound_path`; room-specific desktop
  overrides are stored locally in `room_notification_sound_paths` and are keyed
  by room identifier. These room sounds are local user preferences and are not
  Matrix room state.
- Foreground read-state sync should clear route-matching desktop notifications
  when a room/client no longer has a displayed unread notification count, so
  native desktop notifications and the Windows companion cannot outlive the
  Matrix unread state.

## Token and Subscription Registration

Current Matrix-facing pusher registration is visible in:

- `intergalactic/lib/client/matrix/components/push_notifications/matrix_push_notification_component.dart`

When changing registration, review:

- how the app gets the token/subscription/endpoint
- how the Matrix pusher key is chosen
- how stale pushers are cleaned up
- whether routing remains account-specific

Failure modes to prevent:

- duplicate pushers
- wrong-account pusher registration
- stale tokens kept forever
- notifier initialized before the correct client context exists

## Permissions

Notification permissions differ by target.

Always verify:

- the user-facing prompt still occurs at the right time
- denied permissions leave the app in a recoverable state
- retry/setup flows still work from settings
- lack of permission does not break unrelated startup or account restore paths

## Click Routing and Account / Session Routing

Notification clicks must resolve to:

- the correct account
- the correct room or call target
- the correct app state transition

Inspect together:

- notification response handlers
- app bootstrap/restore behavior
- room-opening event bus or equivalent navigation hook
- background notification handling

Do not assume the active foreground client is the correct account for a clicked notification.

## Privacy and Preview Rules

Notifications can expose sensitive data. Treat preview behavior as product and security logic, not UI decoration.

Review:

- message body formatting
- media previews in notifications
- whether encrypted or undecryptable events fall back safely
- platform differences in what the OS can display on lock screen / banner / browser notifications

Visible preference/config areas include:

- `intergalactic/lib/config/preferences.dart`
- notifier-specific content builders
- `lib/client/components/push_notification/ios/notification_policy_snapshot_io.dart`:
  the local notification preferences the iOS extension honours are carried
  to it through this snapshot. A new local-only notification control is not
  honoured by the extension until it is added to
  `NotificationPolicyInputs`, the watched key set, and the extension's
  `NSEPolicy.decide`. Older valid snapshots without `developer_mode` retain
  their rich-preview policy while defaulting the developer-only path off;
  malformed values still fail closed. Add new controls to all three in one
  change and decide their old-snapshot default explicitly.

## Change Checklist

When changing notifications, inspect all of the following:

- shared notification content/routing code
- Matrix pusher registration
- Android notifier implementation
- iOS notifier implementation
- web notifier and service-worker bridge
- settings/setup surfaces for notification permissions and diagnostics

## Release Checklist

- permission request still works on the affected platform
- registration/token refresh still works
- click routing opens the correct account and room
- room-level mute rules still behave as expected
- notification privacy settings still apply
- no stale pusher or token cleanup regressions

## Verified Implementation Paths

- iOS shared notifier behavior lives under
  `intergalactic/lib/client/components/push_notification/ios/ios_notifier.dart`;
  the native APNs registration and tap bridge lives in
  `intergalactic/ios/Runner/AppDelegate.swift`.
- Desktop notification policy remains in the shared Dart notifier layer. The
  Windows companion display host is implemented under
  `intergalactic/lib/ui/windows/notification_companion/`.
- Keep platform-specific ownership claims narrow and verify the target runner
  folder before documenting a new native notifier path.
