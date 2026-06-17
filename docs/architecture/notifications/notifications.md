# Notifications

## Purpose

This file documents the notification architecture across Android, iOS, Web, and Desktop.

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
notification settings, DM long-press context menus, and supported Android/iOS
local notification actions. Android adds snooze actions to local message,
story, and calendar notifications. iOS registers a local notification category
with the same actions and applies it to local message, story, and calendar
notifications. The shared notification response handler stores the snooze from
the action payload and clears active local notifications for the room when the
room is available.

Snooze does not mutate Matrix push rules, mark rooms read, change unread
counts, alter server-side pushers, store plaintext message content, or sync to
other devices. Expired entries are ignored during reads and pruned when the app
notification settings page opens.

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
Windows, Android, and iOS render story notifications without message reply
actions. Windows and iOS can suppress the story sound directly; Android marks
the story notification silent when the setting is off. Story notification taps
carry a shared story-open route with client, room, story sender, story id, and
optional story event id so taps open the full-screen story viewer instead of
the sender DM. If the target story is no longer active or cannot be resolved,
the app falls back to the carrying DM room. Story post delivery dedupes one
logical story per account, sender, and `story_id` before the platform notifier
handoff, because the same upload can appear as separate Matrix events in
multiple DM rooms. Photo stories and video stories
(`chat.intergalactic.story.video`) use this same shared route, dedupe rule, and
fallback behavior. The settings do not change Matrix push rules, pusher
registration, platform background delivery, or server unread counts.
For native iOS/APNs tap responses, the shared Dart handler keeps the native
`response_id` pending until `MainPage` confirms the story viewer route has
started or the stale-story fallback room is selected.

See `../features/dm-stories.md` for the current story event contract, marker lifetime,
account-data settings shape, and badge-suppression boundaries.

## Desktop Notification Companion

The Windows notification companion overlay is an opt-in local display surface
for approved message notifications. It listens after `NotificationManager`
passes `enableNotifications` and all registered notification modifiers. If a
notification is suppressed by normal policy, the companion receives nothing.

The companion still uses the normal approved-notification pipeline and does not
change local notification sounds, pusher registration, Matrix push rules, or
click response handling. While the Windows companion host is available and the
companion is enabled, `WindowsNotifier` suppresses native message toasts so the
same approved message is not displayed in both the overlay and a system toast.
Call and calendar reminder toasts stay native. Companion clicks route through
`EventBus.openRoomFromNotification((roomId, clientId))`.

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

FCM builds are the default Android release path. Maintainer Android build
helpers run `intergalactic/scripts/set_google_services.ps1 enable`, then run
`flutter pub get`, and forward the FCM flags to the Android build. The toggle
enables Firebase dependencies, the Gradle Google Services plugin, Firebase
imports, and `lib/firebase_options.dart`. Web build helpers must run the same
toggle in `disable` mode before package resolution so browser builds use Web
Push without compiling Android-only Firebase Messaging packages.

FCM must stay a data-only delivery path. Android should not render FCM
notification title/body fields directly for Matrix messages because encrypted
events require local event fetch/decryption first. The FCM background handler
currently uses the build-929 decrypt-capable `BackgroundNotificationsManager`
path because device validation showed the lightweight decrypt reader still did
not render encrypted message previews. Firebase wakes the app for the
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

Use the maintainer Android build helper's embedded-ntfy/no-FCM mode only when
producing a non-Google fallback build. The Firebase service-account JSON/private
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

## TODOs To Verify In Repo

- Verify the current native iOS APNs bridge path before documenting file-level ownership more narrowly than `intergalactic/ios/`.
- Verify whether any desktop target has additional native notifier code outside the shared Dart notifier layer before adding more platform-specific path guidance.
