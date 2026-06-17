# Public Release Readiness Tracker

Last updated: 2026-06-16

Purpose: this is the simple checklist to maintain as public-release work lands.
It summarizes the workspace audit report, the policy docs in this folder, and
the latest implementation work. Keep the detailed evidence in the linked docs;
keep this file short enough to scan before each release pass.

This is an engineering/release tracker, not legal advice.

## How To Maintain This File

- Check a box only after the code, docs, and manual evidence are done.
- If a code change lands but still needs device/App Store verification, leave
  the blocker unchecked and add a short note.
- Add the commit, PR, screenshot, upload result, or human review note in the
  evidence line when available.
- Confirm public contacts and TODO URLs before any public submission.

## Current Snapshot

- [x] REVIEW release-closeout pass completed for the current `0.7.4+985`
  rollout boundary.
  Evidence: on 2026-06-16 REVIEW reconciled S&C's prerelease findings after
  S&C completed its current work. The remaining push-payload provider proof,
  public App Store metadata, advisory-alert coverage, and counsel/legal review
  items are recorded as accepted defers or future-route validations, not
  pre-publish blockers for the current website/TestFlight rollout. Release
  Pipeline published the website desktop/Android release artifacts on
  2026-06-16 and recorded local/public manifest, checksum, and artifact URL
  verification in the v0.7.4 release record.
- [x] Release Pipeline submission-packet evidence is opened for the current
  candidate identity.
  Evidence: `docs/release/release-record-v0.7.4.md` is the active semantic
  release-cycle packet and records `0.7.4+985` as the live published build
  ledger row. The previous exact published `0.7.3+984` artifact record remains
  in `docs/release/release-record-v0.7.3+984.md`.
- [x] Policy/App Store document drafts exist in `docs/policies/`.
  Evidence: `PRIVACY_POLICY.md`, `TERMS_OF_SERVICE.md`,
  `COMMUNITY_GUIDELINES.md`, `REPORT_ABUSE.md`, `SUPPORT.md`, source/licensing,
  privacy, security, and App Store review docs are present.
- [x] Reader-facing policy drafts keep reader guidance in the policy files
  while unresolved release blockers stay centralized here.
  Evidence: `SUPPORT.md`, `REPORT_ABUSE.md`, `COMMUNITY_GUIDELINES.md`,
  `PRIVACY_POLICY.md`, and `ACCOUNT_MODEL.md` distinguish reader guidance from
  remaining release-readiness prerequisites.
- [x] Terms and account-deletion drafts now use the same centralized blocker
  pattern.
  Evidence: `TERMS_OF_SERVICE.md` and `ACCOUNT_DELETION.md` now point remaining
  publication and contact/deletion-path caveats back to this tracker.
- [x] Technical privacy/policy drafts now use the same centralized blocker
  pattern.
  Evidence: `GIF_RELAY_PUBLIC_BUILD_POLICY.md`,
  `URL_PREVIEW_PRIVACY_REVIEW.md`, `PUSH_PRIVACY_REVIEW.md`, and
  `LOG_REDACTION_POLICY.md` now phrase unresolved release work as explicit
  readiness prerequisites or blockers that point back to this tracker.
- [x] Third-party notices now use the same centralized inventory/blocker
  pattern.
  Evidence: `THIRD_PARTY_NOTICES.md` now distinguishes release evidence,
  current-scope acceptance, and future re-audit triggers. User confirmation on
  2026-06-16 verified the notice/access surface for the current release scope.
- [x] Remaining non-legal release-heavy docs now use the same centralized
  readiness pattern.
  Evidence: `ASSET_PROVENANCE.md`,
  `PUBLIC_RELEASE_ARTIFACT_HYGIENE.md`, `SECURITY_RELEASE_CHECKLIST.md`,
  `IOS_PRIVACY_MANIFEST_NOTES.md`, and `APP_PRIVACY_LABEL_INVENTORY.md` now
  distinguish active release verification work from final published state and
  point that follow-up back to this tracker.
- [x] Native Android/iOS login hides account registration.
  Evidence: `intergalactic/lib/ui/pages/login/login_page_shared.dart`.
- [x] Draft iOS privacy manifest exists and is added to the iOS project.
  Evidence: `intergalactic/ios/Runner/PrivacyInfo.xcprivacy`.
- [x] Settings includes Help & Safety and Policies above About.
  Evidence: commit `792aaa0`.
- [x] Matrix-native report and block controls exist in Settings.
  Evidence: commit `792aaa0`; message, room, user reports use Matrix reporting
  APIs and block/unblock uses Matrix ignored-user account data.
- [x] Report and block controls are manually verified against a real test
  homeserver.
  Evidence: user confirmed on 2026-06-12 that message, room, and user reports
  were submitted against a real homeserver; OPERATIONS confirmed the report
  path landed where expected. User also confirmed block/unblock worked.

## True Public Release Blockers

- [x] Confirm `intergalactic@ourgalaxy.space` is monitored for public support,
  privacy, abuse, and security routing.
  Evidence: user confirmed on 2026-06-09 that
  `intergalactic@ourgalaxy.space` is monitored and is the main point of
  contact; see `docs/todo-list/done.md`
  (`TODO-2026-06-09-public-support-inbox-monitoring`).
- [x] Host public Privacy Policy, Terms/EULA, Community Guidelines, Support,
  Report Abuse, Account Deletion, and Source Offer pages.
  Evidence: current public URLs are recorded in `APP_STORE_REVIEW_NOTES.md`,
  `SOURCE_OFFER.md`, and `docs/release/release-record-v0.7.3+984.md`.
  DOCUMENTATION rechecked the listed policy/support/source URLs with Python
  HTTPS HEAD requests on 2026-06-12; all returned HTTP 200, and the source
  archive reported the expected 166,087,940-byte length.
- [x] Add final hosted policy/source links in-app.
  Evidence: user confirmed on 2026-06-12 that the in-app policy/source links
  open the hosted public pages; DOCUMENTATION also verified the public
  policy/support/source URLs with HTTP 200 responses on 2026-06-12.
- [x] Verify the account deletion/deactivation handoff in Account settings.
  Evidence: code path added in
  `intergalactic/lib/ui/pages/settings/categories/account/account_management/account_management_tab.dart`;
  review-note copy updated in `APP_STORE_REVIEW_NOTES.md`; user confirmed on
  2026-06-12 that the Account settings handoff is visible, successfully pulls
  the appropriate public links, and makes sense.
- [x] Validate `PrivacyInfo.xcprivacy` with Xcode/App Store upload.
  Evidence: `docs/release/release-record-v0.7.3+984.md` records the iOS App
  Store Connect export path, local code-sign verification, Transporter
  delivery, and TestFlight upload/install confirmation for the submitted
  archive. IOS also verified on 2026-06-12 that the exported IPA contains the
  app-level `Payload/Runner.app/PrivacyInfo.xcprivacy` plus bundled SDK/plugin
  privacy manifests.
- [x] Complete App Store privacy labels.
  Evidence: user provided App Store Connect screenshots on 2026-06-14. The
  labels record Identifiers, User Content, and Search History as linked to the
  user's identity, and Diagnostics plus unlinked User Content as not linked to
  the user's identity. The collected data types are User ID, Device ID, Emails
  or Text Messages, Photos or Videos, Audio Data, Other User Content, Customer
  Support, Search History, Crash Data, Performance Data, and Other Diagnostic
  Data; each visible type is used for App Functionality. The additional Audio
  Data screenshot shows Audio Data linked to the user's identity. Reconciled
  with `APP_PRIVACY_LABEL_INVENTORY.md`.
- [x] Complete encryption export compliance for the current TestFlight release
  scope.
  Evidence: user confirmed on 2026-06-16 that IOS handled the App Store
  Connect encryption export compliance work for the current TestFlight build.
  Follow-up evidence on 2026-06-16 refreshed the iOS IPA to `0.7.4+986` with
  `ITSAppUsesNonExemptEncryption=false` after Apple guidance indicated the
  plist route can specify no non-exempt encryption / documentation exemption.
  Retain the IOS/App Store Connect evidence with the release record. This is an
  engineering release-gate note, not legal advice; broader counsel/legal review
  remains tracked separately.
- [x] Publish exact AGPL source for the submitted binary.
  Evidence: `docs/release/release-record-v0.7.4.md` records source commit
  `5ea73c0`, build `985`, source archive
  `https://app.ourgalaxy.space/source/intergalactic-0.7.4+985-source.zip`, and
  SHA-256
  `342280CB6ED1A8684B96EDCD78F36CB98A9F5AC828C57041322378701AB70255`.
- [x] Prove public artifacts contain no local secrets or signing material.
  Evidence: `docs/release/release-record-v0.7.4.md` records
  `.github/scripts/security-review.py --repo-root . --artifact-root dist`
  passed for the `0.7.4+985` release artifact root before publish.
- [x] Verify artifact signatures or approved unsigned-consent records.
  Evidence: `docs/release/release-record-v0.7.4.md` records the Windows
  untrusted-root Authenticode `UnknownError` state as the approved
  checksum-verified unsigned/untrusted consent path with
  `allow_unsigned_auto_update=true`. User explicitly deferred Android signing
  on 2026-06-12 because Android distribution remains website APK download or
  source build from the public repo until further notice. iPhone distribution
  remains TestFlight for this release route.
- [x] Validate update-manifest integrity and checksums.
  Evidence: `docs/release/release-record-v0.7.4.md` records local and public
  `latest.json` verification for `v0.7.4+985`, strict UTF-8 JSON parsing with
  no BOM, Windows and Android download URLs, expected auto-update flags, public
  checksum file verification, and SHA-256/byte counts matching the release
  record.
- [x] Confirm rollback artifact and process validation.
  Evidence: Release Pipeline archived the previous live mirror rollback set on
  2026-06-16 under
  `workspace:intergalactic-app/archive/release-rollback/v0.7.4/previous-v0.7.3+984-20260616-143137/`
  and zipped it as
  `previous-v0.7.3+984-20260616-143137.zip` with SHA-256
  `7FBFF5A92C712C314894DF918A30DA4171024F21522FFCA31ED6DA8F57717918`.
  The archive contains the live `v0.7.3+984` `latest.json`, checksum file,
  Windows installer, Android APK, source archive, and public changelog. The
  archived installer/APK/source hashes match the live checksum file, and the
  installer signature state is `NotSigned`, matching the approved
  unsigned-consent rollback path.

## High-Risk Engineering Items

- [x] Finalize public GIF search setup.
  Evidence: user confirmed on 2026-06-12 that the public GIF path allows users
  to provide either their own KLIPY API key or relay URL, and that the saved
  setup persists across updates. Current release docs require public artifacts
  to avoid embedding a direct provider key by default.
- [x] Harden URL previews for encrypted rooms for `0.7.3+984`.
  Evidence: S&C classified submitted `0.7.3+984` on 2026-06-12.
  Encrypted-room URL previews default on and are user-disableable from
  Settings; user confirmed the settings copy is understandable. The submitted
  source uses the Matrix homeserver preview API first, with no Inter Galactic
  preview endpoint evidenced in release logs/default source. Direct client
  fallback is provider-limited to TikTok, Instagram, and Reddit and keeps
  unsafe-scheme, localhost, private/reserved network, DNS, and redirect guards
  before fetches. RELEASE PIPELINE accepted current settings-plus-policy
  disclosure as sufficient for `0.7.3+984` on 2026-06-12 with a documented
  defer: future full close should add first-use consent or change the
  encrypted-room default off before the next public/store build where this gate
  is reconsidered.
- [x] Expand runtime log redaction before public support intake.
  Evidence: BUG-220 shortcut avatar-cache Matrix ID leakage was fixed and
  resampled. BUG-224 Matrix API URI redaction was implemented in app commit
  `f7679aa`, covered by focused redactor tests and targeted analyzer
  validation, and supported by rebuilt-app non-crash/support-artifact redaction
  evidence. User confirmed on 2026-06-16 that no safe user-accessible crash
  reproduction path is currently available, and the release accepts the
  remaining crash/report exception-path resample as post-release or
  controlled-harness validation if a natural crash report occurs or
  DEBUG/REVIEW adds a dev-only crash harness.
- [x] Verify Matrix token and E2EE key storage on iOS and Android.
  Evidence: user confirmed on 2026-06-12 that token and E2EE storage are
  confirmed on iOS and Android and are safely locked behind biometrics.
- [x] Complete third-party license notices and asset provenance for the
  current release scope.
  Evidence accepted: S&C generated `docs/release/THIRD_PARTY_LICENSES.json`,
  `THIRD_PARTY_NOTICES.md`, `ASSET_PROVENANCE.md`,
  `LICENSE_AUDIT_REPORT.md`, and `LICENSE_RELEASE_CHECKLIST.md` on
  2026-06-12. REVIEW wired Android release builds on 2026-06-13 to refresh
  Gradle/Maven runtime evidence for the shipped APK and, for FCM builds,
  Firebase/FlutterFire package evidence from the temporary Google Services
  dependency state without committing Firebase client config. On 2026-06-13,
  S&C folded user-supplied local license evidence for Nunito,
  Twemoji-derived app emoji font material, Emojibase, and ClearURLs; REVIEW
  later mirrored that evidence under `docs/release/evidence/license-sources/`
  so app-repo release docs no longer depend on workspace-only evidence paths.
  S&C also added exact file/use inventory for sounds, placeholder
  avatars/photos, confetti, and store metadata images. Later on
  2026-06-13, S&C recorded user confirmation that `avatar1.jpg` and
  `avatar2.jpg` are Commet-created, recorded Pexels license evidence for
  Pexels-named placeholder photos, and removed copied Commet Fastlane/store
  images from the repo. S&C then folded Commet asset evidence into the release
  evidence for bundled sound/ringtone assets and `confetti.webp` as Commet AGPL
  repository assets with first-observed upstream commits recorded; REVIEW
  mirrored that file to
  `docs/release/evidence/license-sources/commet/commetassets.md`. S&C also
  recorded Flutter repository license evidence for the initial Flutter SDK
  package rows.
  REVIEW then resolved the remaining generated JSON unknown/owner-review rows
  on 2026-06-13: Flutter SDK pseudo-packages, Starfield Unlicense evidence, all
  iOS pod rows from synced CocoaPods acknowledgement sources, Android
  Gradle/Maven root rows from Maven POMs plus generated `0.7.4+985` Android
  evidence, and patched WebRTC license-family classification. REVIEW then
  generated patched WebRTC/libwebrtc notice evidence under
  `docs/release/evidence/webrtc/` and closed RNNoise attribution to the release
  notice surface on 2026-06-13. REVIEW then accepted TwemojiCOLR attribution
  and source evidence, regenerated Emojibase from `emojibase-data@17.0.0` and
  removed the stale Commet-era readme, accepted ClearURLs `ClearURLs/Rules @ 9317c06` handling with
  LGPL source-offer/source-link requirements, accepted Animated Fluent emoji
  particle MIT attribution after confirming particle files match Commet by
  hash, and accepted synced iOS acknowledgement/license source files for the
  inventory. REVIEW also staged the static BtbN `win64-lgpl` FFmpeg/FFprobe
  pair and recorded source/config/hash evidence under
  `docs/release/evidence/ffmpeg/`. REVIEW then sanitized the retained Android
  Gradle evidence snapshot by removing Gradle warning pseudo-modules and
  maintainer-local warning/report URI lines, and fixed the collector so future
  runs exclude those lines. On 2026-06-14, REVIEW normalized the provided
  Nunito, TwemojiCOLR/Twemoji, Emojibase, ClearURLs, and Commet asset evidence
  into release-ready source records and recorded user/owner acceptance for
  retaining the Commet-inherited sound/ringtone/confetti assets under the
  Commet AGPL repository-asset evidence path. The generated inventory's
  unknown/owner-decision count is now 0. REVIEW reran `build_android.bat` on
  2026-06-14 after fixing the evidence collectors: the Gradle bundle is
  present for `0.7.4+985` in FCM mode with Firebase/FCM Maven modules, and the
  generated `docs/release/evidence/android-fcm/0.7.4+985/` bundle records 7
  Firebase/FlutterFire packages with 0 missing local license files. REVIEW then
  added Android Gradle source/policy overrides plus a Google OSS licenses
  plugin baseline comparison and reran `build_android.bat --skip-codegen` on
  2026-06-14; the Gradle bundle records 171 runtime modules with 0 missing
  license rows, and the Google OSS baseline records 3 generated files, 228
  notice names, and 229 dependency modules. User confirmed on 2026-06-16 that
  the notice/access surface is verified. The rebuilt Windows FFmpeg story-video
  smoke currently fails with `video could not be recorded.` Release owner
  accepts deferring that runtime story-export smoke to the next release while
  leaving the current license/provenance evidence as-is.
- [x] Verify push privacy behavior for the current rollout boundary.
  Evidence partial: user confirmed on 2026-06-12 that push notification
  registration works and OS-level notification preview suppression works where
  tested. SERVER completed source hardening for provider payload minimization.
  Release owner accepts the provider-payload proof as post-release/released
  iOS/TestFlight validation because final provider evidence cannot be sampled
  before the released build path exists. Keep the integration queue item open
  for exact released-build evidence that encrypted-room pushes avoid decrypted
  message content while preserving readable local notifications and tap-to-room
  routing.
- [x] Update public store metadata for the current route.
  Evidence/defer: Android Play/store metadata and signing are explicitly
  deferred because the current Android route is website APK download or source
  build from the public repo. Current distribution remains TestFlight rather
  than a public App Store launch, so public product-page metadata remains a
  future store-route gate. Current TestFlight/reviewer-facing release notes,
  privacy/export/support, and app-review evidence are the active store-facing
  metadata surface for this rollout.

## Manual Test Pass Before Submission

- [x] Existing Matrix account login works on `matrix.org`.
- [x] Custom homeserver login works if the submitted build allows it.
- [x] Native mobile login does not expose Create Account.
- [x] E2EE room restore, device verification, and recovery prompts work.
- [x] Help & Safety can report a message.
- [x] Help & Safety can report a room.
- [x] Help & Safety can report a user.
- [x] Help & Safety can block and unblock a user.
- [x] Account deletion/deactivation handoff is visible and understandable.
- [x] Support, privacy, abuse, security, and source links open public pages.
- [x] URL preview settings are understandable in encrypted rooms.
- [x] GIF search uses the approved relay path or user setup path.
- [x] Push notification registration works.
- [x] Privacy-enhanced encrypted-room notification payload behavior is
  release-accepted for post-release provider validation.
  Evidence/defer: server-side source hardening is complete and current local
  notification routing requirements are documented. Exact APNs/FCM provider
  payload proof remains queued against the released iOS/TestFlight and Android
  notification paths, but it is no longer a pre-publish blocker for this
  rollout.
- [x] Voice, camera, microphone, photo/file, notification, and screen-share
  permission strings make sense on iOS.
- [x] Public artifacts install/launch and match the submitted build number.
- [x] Windows desktop and Android APK post-release update smoke passed for
  `v0.7.4+985`.
  Evidence: user confirmed on 2026-06-16 that the app auto-detected the live
  update and updated successfully through both the Windows desktop path and
  the Android APK path.

## Submission Packet

- [x] Submitted app version and build number: `0.7.3+984`
- [x] Git commit: `91c4adf072dee05092f24943ee686c4eec91bd7e`
- [x] PR: GitHub PR #38, merged into `main` at
  `0bb2381cf4e354719f1f85c19a70da03182f1b90`
- [x] Source archive URL: `https://app.ourgalaxy.space/source/intergalactic-0.7.3+984-source.zip`
- [x] Source archive checksum: `7AEB2033B2DCD27EF7998F439663F07C9FDC970B66FB89ED840804DE1E299684`
- [x] Privacy Policy URL: `https://app.ourgalaxy.space/privacy/`
- [x] Terms/EULA URL: `https://app.ourgalaxy.space/terms/`
- [x] Support URL/email: `https://app.ourgalaxy.space/support/`;
  `intergalactic@ourgalaxy.space`
- [x] Abuse report URL/email: `https://app.ourgalaxy.space/report-abuse/`;
  `intergalactic@ourgalaxy.space`
- [x] Account deletion URL: `https://app.ourgalaxy.space/account-deletion/`
- [x] Community Guidelines URL:
  `https://app.ourgalaxy.space/community-guidelines/`
- [x] Security contact: `intergalactic@ourgalaxy.space`; GitHub private
  vulnerability reporting remains deferred until public visibility/security
  settings are enabled and rerun through REVIEW.
- [x] App Store privacy-label evidence: user-provided App Store Connect
  screenshots from 2026-06-14 are reconciled with
  `APP_PRIVACY_LABEL_INVENTORY.md` for identifiers, user content, Audio Data,
  search, support, and diagnostics. RNNoise WAV/audio diagnostics stay
  local-only and are not accepted by bug-report submission.
- [x] Encryption export evidence: user confirmed on 2026-06-16 that IOS handled
  App Store Connect encryption export compliance for the current TestFlight
  build; IOS later refreshed the IPA to `0.7.4+986` with
  `ITSAppUsesNonExemptEncryption=false` after Apple guidance accepted the
  no-non-exempt-encryption plist route. Retain the IOS/App Store Connect
  evidence with release records. Broader counsel/legal review remains tracked
  separately.
- [x] Privacy manifest validation evidence: `docs/release/release-record-v0.7.3+984.md`
  records App Store Connect export, local code-sign verification, Transporter
  delivery, and TestFlight upload/install confirmation for the submitted
  archive; IOS verified the exported IPA contains the app-level
  `PrivacyInfo.xcprivacy` on 2026-06-12.
- [x] Artifact secret-scan evidence:
  `.github/scripts/security-review.py --repo-root . --artifact-root dist`
  passed for `v0.7.3+984` per `docs/release/release-record-v0.7.3+984.md`.
- [x] Third-party notices bundle: generated/reviewed by S&C on 2026-06-12,
  unknown/owner-review JSON rows cleared by REVIEW on 2026-06-13, and patched
  WebRTC/RNNoise notice evidence generated by REVIEW on 2026-06-13. REVIEW also
  accepted Twemoji, regenerated Emojibase, accepted ClearURLs, Fluent emoji
  particles, and iOS notice-source handling on 2026-06-13; FFmpeg
  binary/source evidence is now attached under `docs/release/evidence/ffmpeg/`,
  and app-local license evidence is mirrored under
  `docs/release/evidence/license-sources/`. On 2026-06-14, REVIEW normalized
  the provided license evidence into release-ready source records and recorded
  owner acceptance for the retained Commet-inherited sound/ringtone/confetti
  assets. Android Gradle/FCM/Google OSS baseline evidence is complete for
  `0.7.4+985`. User confirmed on 2026-06-16 that the notice/access surface is
  verified, and the release owner explicitly accepts deferring the failing
  Windows FFmpeg story-export smoke (`video could not be recorded.`) to the
  next release.
- [x] Asset provenance inventory: generated/reviewed by S&C on 2026-06-12;
  Twemoji, regenerated Emojibase, ClearURLs, and retained Commet-inherited
  sound/ringtone/confetti rows are accepted with notice/source-offer/package or
  Commet AGPL repository-asset evidence; FFmpeg evidence is attached. User
  confirmed on 2026-06-16 that current asset provenance stays as-is and no new
  owner decisions are required unless assets change. The rebuilt Windows FFmpeg
  story-export smoke is deferred to the next release by release-owner
  acceptance.
- [x] Counsel/legal review note: explicitly deferred until counsel/legal review.
  Evidence/defer: engineering release records state that these are S&C/release
  readiness findings and not legal advice. Counsel/legal review remains an
  external future gate rather than a current Release Pipeline blocker.

## Detailed References

- Workspace audit report: `docs/AUDIT_REPORT.md`
- `APP_STORE_RELEASE_CHECKLIST.md`
- `SECURITY_RELEASE_CHECKLIST.md`
- `APP_PRIVACY_LABEL_INVENTORY.md`
- `IOS_PRIVACY_MANIFEST_NOTES.md`
- `ENCRYPTION_EXPORT_COMPLIANCE.md`
- `REPORT_ABUSE.md`
- `ACCOUNT_MODEL.md`
- `ACCOUNT_DELETION.md`
- `SOURCE_OFFER.md`
- `THIRD_PARTY_NOTICES.md`
- `ASSET_PROVENANCE.md`
