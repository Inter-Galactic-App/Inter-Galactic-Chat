# Encryption Export Compliance

Status: current technical export-compliance record for App Store Connect submission support.
Last reviewed: 2026-06-16.

Inter Galactic is a Matrix client. It supports Matrix end-to-end encryption for
messages and room events using the Matrix Olm/Megolm cryptographic protocols
through `vodozemac` / `flutter_vodozemac`. The app also uses standard TLS/HTTPS
for network transport, WebRTC/LiveKit encrypted media transport for calls, and
platform secure storage for local credentials and keys. The encryption is used
for user privacy and secure communications; the app does not provide standalone
cryptographic tools for general-purpose file encryption.

## Export Compliance Summary

- App uses encryption: yes.
- iOS `Runner/Info.plist` sets `ITSAppUsesNonExemptEncryption` to `false`
  for App Store Connect/TestFlight submission metadata after the user reported
  Apple confirmed the current build can specify no non-exempt encryption /
  exemption from documentation. This does not remove or disable Matrix E2EE at
  runtime.
- Proprietary or non-standard cryptography: none identified in the current
  technical inventory.
- App Store Connect build metadata route: no non-exempt encryption /
  documentation exemption via `ITSAppUsesNonExemptEncryption=false`.
- If App Store Connect or App Review asks follow-up questions, use the exact
  answer wording from the current Apple workflow and the user-provided Apple
  guidance for the submitted build.
- S&C or release owner should re-check this if encryption scope changes or if
  Apple requests new documentation.

## Encryption In Use

- Matrix end-to-end encryption for encrypted rooms and events.
- `vodozemac` / `flutter_vodozemac` for Matrix cryptographic operations.
- Olm and Megolm Matrix cryptographic protocols.
- Ed25519 and Curve25519 keys/signatures used by Matrix device/session security.
- AES-256 and HMAC-SHA-256 as used by Matrix Megolm message encryption.
- `flutter_secure_storage` for platform-backed local secure storage of
  credentials, tokens, and key material.
- TLS/HTTPS for client/server and service network transport.
- WebRTC/LiveKit encrypted real-time media transport for calls.

## Purpose

- User messaging security.
- Encrypted Matrix room communication.
- Device, session, key backup, cross-signing, and verification handling.
- Secure local token/key storage.
- Media call transport security.

## App Store Connect Answer Guidance

Use the exact answers shown by App Store Connect for the submitted build. Based
on the current app inventory and the user-provided Apple response:

- "Does your app use encryption?": yes.
- "Does your app use proprietary or non-standard encryption?": no.
- If App Store Connect accepts the plist route, use
  `ITSAppUsesNonExemptEncryption=false` to indicate the iOS build does not use
  non-exempt encryption / is exempt from documentation. Do not interpret this as
  disabling Matrix E2EE or removing runtime encryption from the app.
- Short description:

```text
Inter Galactic is a Matrix client using Matrix E2EE (Olm/Megolm via vodozemac), TLS/HTTPS, WebRTC/LiveKit media encryption, and platform secure storage to protect messages, rooms, calls, credentials, and keys. It is not a standalone encryption tool.
```

If France distribution is enabled and App Store Connect requests documentation,
prepare and upload the French encryption declaration, then retain the approved
documentation or App Store Connect key with the release evidence. If the app's
cryptography changes to include proprietary or non-standard algorithms, route to
S&C before submission because Apple's documentation requirements change.

## Source Guidance Reviewed

- Apple App Store Connect: [Export compliance documentation for encryption](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
- Apple App Store Connect: [Provide export compliance information for beta builds](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-export-compliance-information-for-beta-builds)
- Apple Developer Documentation: [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption)

## User-Facing Note

E2EE protects message content in supported Matrix rooms, but it does not hide all metadata and does not control copies already received by other users or homeservers.
