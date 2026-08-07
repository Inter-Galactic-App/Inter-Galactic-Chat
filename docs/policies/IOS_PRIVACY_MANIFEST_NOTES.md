# iOS Privacy Manifest Notes

Publication status: companion notes for
`intergalactic/ios/Runner/PrivacyInfo.xcprivacy`. Submitted-build validation
evidence and recorded App Store privacy-label evidence are tracked in
`PUBLIC_RELEASE_READINESS_TRACKER.md`.

Apple requires privacy manifests to declare collected data, tracking, and required reason APIs. Apple also states that third-party SDKs should provide their own manifests; this app manifest focuses on app-level data and conservative required-reason coverage for app code and current Flutter/iOS usage.

## Repo Evidence Used

- iOS permissions: camera, Face ID, microphone, Apple Music, photo library.
- iOS entitlements: APNs and app group `group.chat.intergalactic.app`.
- iOS broadcast extension uses ReplayKit and an app-group socket path.
- iOS Podfile.lock includes `file_picker`, `flutter_secure_storage`, `flutter_webrtc`, `image_picker_ios`, `livekit_client`, `permission_handler_apple`, `shared_preferences_foundation`, and `sqflite_darwin`.
- AppDelegate uses APNs token capture, local media controls, biometrics, voice recording, temporary files, and file attributes.

## Manifest Choices

Tracking is set to false.

Collected data is conservatively declared for Matrix user IDs, device IDs, messages/content, photos/videos, audio data, customer support, GIF searches, and diagnostic/performance logs when submitted.

Required-reason APIs are declared for:

- UserDefaults: `CA92.1` for app-only settings/session preferences and `1C8F.1` for possible app-group sharing.
- File timestamps: `C617.1` for app/app-group files and `3B52.1` for user-selected files.
- Disk space: `E174.1` for checking whether files/media/cache/database writes can proceed.
- System boot time: `35F9.1` for in-app timers and elapsed-time calculations.

## Submitted `0.7.3+984` Evidence

`PUBLIC_RELEASE_READINESS_TRACKER.md` records that the submitted iOS archive
included the app-level privacy manifest and that the App Store Connect export,
Transporter delivery, and TestFlight upload/install path were completed for
that build.

## Next Submission Verification

- Revalidate the manifest in Xcode/App Store Connect for every new submitted
  archive.
- Confirm whether App Store Connect reports missing third-party SDK manifests.
- Confirm whether Firebase Messaging is included in the final iOS archive.
- Confirm whether Apple Music/local media artwork or playback state is transmitted off-device.
- Reconfirm App Store privacy labels match this file for each new submitted
  archive or App Store Connect answer change.

Keep these prerequisites synchronized with
`PUBLIC_RELEASE_READINESS_TRACKER.md` and
`APP_PRIVACY_LABEL_INVENTORY.md`.

Primary Apple references:

- https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
- https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest
