# App Store Release Checklist

Draft status: release-readiness checklist. Counsel review required for legal items.

## Release Gate Checklist

This list includes completed and open App Store gates. Use
`PUBLIC_RELEASE_READINESS_TRACKER.md` for current pass/fail state before
treating a row as blocking.

- Host public Privacy Policy, Terms/EULA, Community Guidelines, Support, Report Abuse, Source Offer, and Account Deletion pages.
- Add visible in-app links to the hosted Privacy Policy, Terms/EULA, Support, Community Guidelines, Report Abuse, and Source Offer.
- Verify native iOS login does not expose account registration.
- Provide an account deletion initiation path or review-note path to the selected homeserver deletion flow.
- Implement and verify in-app Matrix-native report and block/ignore flows for UGC safety.
- Confirm `intergalactic@ourgalaxy.space` is monitored for public support, privacy, abuse, and security contact routing.
- Validate `intergalactic/ios/Runner/PrivacyInfo.xcprivacy` in Xcode and App Store upload.
- Complete App Store privacy labels from `APP_PRIVACY_LABEL_INVENTORY.md`.
- Complete encryption export answers from `ENCRYPTION_EXPORT_COMPLIANCE.md`.
- Publish exact AGPL source archive for the submitted build.
- Verify release artifacts exclude secrets and signing material.

## Manual Verification

- Test login with an existing Matrix account on `matrix.org`.
- Test custom homeserver login if the submitted build allows it.
- Test E2EE room restore, verification, and recovery prompts.
- Test push notification registration and privacy-enhanced notification mode.
- Test Matrix-native message, room, and user report flows; block/ignore; and moderator flows on at least one review homeserver.
- Test account sign-out and local data removal behavior.
- Test URL preview and GIF settings in encrypted rooms.
- Test voice/video/screen-share permissions and Info.plist strings.
- Verify App Store metadata does not imply affiliation with Matrix.org, Commet, Discord, Messenger, Apple, Spotify, LiveKit, or GIF providers.

## Submission Records

Keep the following with the release:

- submitted build number and commit;
- source archive URL and checksum;
- App Store privacy-label answers;
- encryption export answers;
- privacy manifest copy;
- third-party notices bundle;
- asset provenance inventory;
- screenshots and review notes;
- support, abuse, privacy, and security contact routing proof.
