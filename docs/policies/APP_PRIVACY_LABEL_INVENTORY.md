# App Privacy Label Inventory

Publication status: App Store Connect answers were provided by the app owner on
2026-06-14 from App Store Connect screenshots and reconciled with
`PUBLIC_RELEASE_READINESS_TRACKER.md`. Recheck this inventory if the submitted
archive or App Store answers change.

Tracking: No tracking is declared in the recorded App Store Connect label set.

## App Store Connect Evidence - 2026-06-14

User-provided App Store Connect screenshots record the following labels:

- Data Linked to You: Identifiers, User Content, Search History.
- Data Not Linked to You: Diagnostics, User Content.
- Data types collected: User ID, Device ID, Emails or Text Messages, Photos or
  Videos, Audio Data, Other User Content, Customer Support, Search History,
  Crash Data, Performance Data, and Other Diagnostic Data.
- Purpose shown for each visible type: App Functionality.
- Linked fields shown: Emails or Text Messages, Photos or Videos, Other User
  Content, Audio Data, Search History, User ID, and Device ID.
- Not-linked fields shown: Customer Support, Crash Data, Performance Data, and
  Other Diagnostic Data.
- Additional Audio Data screenshot supplied on 2026-06-14 shows Audio Data is
  used for App Functionality and linked to the user's identity.

S&C interpretation: the screenshots match the current identifier, diagnostic,
support, search, and user-content boundary if the contactless in-app app-bug
reporter remains unlinked and diagnostics remain redacted before
preview/upload. Audio Data is now aligned with the inventory's treatment of
voice calls and voice messages as linked app-functionality data.

## Likely Data Types

| Data type | Linked to user | Purpose | Notes |
| --- | --- | --- | --- |
| User ID | Yes | App functionality | Matrix user ID, room/event/user references. |
| Device ID | Yes | App functionality | Matrix device ID and push token. |
| Other user content | Yes | App functionality, moderation | Matrix messages, reactions, Matrix-native reports, direct Inter Galactic reports, room metadata. |
| Photos or videos | Yes | App functionality | User-selected uploads, avatars, media messages, screen-share frames, Emoticon Creator source photos, generated transparent PNGs, and Matrix image-pack saves. Emoticon Creator source photos and local drafts remain on-device unless the user chooses a Matrix save/share or export path. |
| Audio data | Yes | App functionality | Voice calls and voice messages. RNNoise WAV diagnostics remain local-only and are not accepted by the bug-report submission path. |
| Customer support | No for the current contactless in-app app-bug reporter; yes if submitted through an account/email context | App functionality | The App Store Connect screenshots record Customer Support without linked-to-user status. Account/email support and Matrix-native abuse reports can still be linked by account, sender, or email context outside the contactless app-bug reporter. The current in-app app-bug reporter does not store source IP hash or user-agent values with the report artifact. |
| Search history | Yes | App functionality | GIF searches when the user uses GIF search. |
| Crash data | No for the current contactless in-app bug reporter; yes if submitted through an account/email context | App functionality | Diagnostic logs and crash reports are opt-in support data and are redacted before preview/upload. |
| Performance data | No for the current contactless in-app bug reporter; yes if submitted through an account/email context | App functionality | Call quality, WebRTC/LiveKit stats, launch or troubleshooting logs. |
| Other diagnostic data | No for the current contactless in-app bug reporter; yes if submitted through an account/email context | App functionality | Debug logs, device/app version, push troubleshooting, and sanitized image-cutout backend/dimension/byte-count/failure-code diagnostics. |

## Current In-App Bug Report Collection Boundary

- The Report a Bug form does not ask for contact info.
- The client redacts identifiers, tokens, Matrix IDs, local paths, and
  contact-shaped fields before preview and again before upload.
- The server rejects legacy top-level contact fields such as `contact`,
  `contact_info`, `contactInfo`, `reporterContact`, and `reporter_contact`.
- Stored bug-report metadata omits source IP hash and request user-agent
  values. Support correlation uses a random per-report hash and/or server
  report ID.
- RNNoise WAV diagnostic captures remain local-only. The in-app bug-report
  path does not accept audio diagnostic uploads.
- Matrix-native abuse reports, direct email support, privacy/security requests,
  and account-management requests are separate channels and may remain linked
  by their account, sender, or email context.

## Current Emoticon Creator Collection Boundary

- Source photos selected for Emoticon Creator are processed on-device through
  the Dart/local fallback, Apple's local Vision framework on supported iOS
  versions, or Android ML Kit Subject Segmentation on supported Android
  versions.
- Android uses a Google Play services ML Kit unbundled model. The app does not
  bundle a subject-segmentation model file or use an Inter Galactic
  cloud/background-removal API for the reviewed mobile implementation.
- Generated transparent PNGs, thumbnails, and local draft metadata remain
  local unless the user chooses a Matrix image-pack save/share or export path.
- Cutout diagnostics may include backend, host platform, operation, duration,
  dimensions, byte counts, fallback state, and structured failure code. They
  must not include source image paths, raw image bytes, EXIF metadata, source
  hashes, Matrix identifiers, or raw native exception text.
- App Store `Photos or Videos` coverage remains appropriate for user-selected
  source photos and generated/shared output. Google Play Data safety answers
  must separately account for Google ML Kit Android SDK diagnostic/usage data
  described by Google for the exact submitted Android build.

## Not Declared Unless Evidence Changes

- Precise or coarse location.
- Contacts.
- Advertising data.
- Third-party advertising.
- Developer advertising.
- Health, fitness, financial, credit, or government identifiers.

## Required Manual Verification

- Confirm whether Firebase Messaging or another iOS push SDK is included in the final iOS archive.
- URL previews for submitted `v0.7.3+984`: encrypted-room previews default on
  and are user-disableable. App Store Connect screenshots supplied on
  2026-06-14 record Search History as linked and used for App Functionality.
- Confirm whether GIF search is enabled by default in the submitted iOS build.
- Confirm whether Apple Music/local media activity sends artwork or playback metadata off-device or only displays locally.
- Confirm whether the submitted build sends abuse reports only to the selected homeserver or also sends direct copies to Inter Galactic support tooling.
- For any build with Emoticon Creator enabled, confirm no desktop ONNX model,
  cloud background-removal provider, or bundled mobile model artifact is enabled
  unless a separate S&C/release review has accepted it.
- For any Android build with ML Kit enabled, confirm Google Play Data safety and
  SDK-disclosure answers account for ML Kit Android SDK diagnostics and usage
  analytics for the exact submitted artifact.

## URL Preview Label Notes

For submitted `v0.7.3+984`, encrypted-room URL previews are enabled by default
but can be disabled by the user. A preview can send URL/request metadata to the
selected Matrix homeserver preview API and, for supported public providers, use
provider-limited direct client fetches. No Inter Galactic preview endpoint was
evidenced for the submitted build. Treat URL-preview targets as
user-provided-content/request metadata when completing App Store privacy labels;
this inventory is not legal advice.

Keep these verification items synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md` and
`IOS_PRIVACY_MANIFEST_NOTES.md`.
