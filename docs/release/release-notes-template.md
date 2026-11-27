# Release Notes Template

Use this template for public release notes, TestFlight notes, Play Store
changelogs, and release manager summaries. Keep public notes user-safe:
avoid secret paths, private hostnames, internal keys, and speculative promises.

```markdown
# Inter Galactic vX.Y.Z

Build: vX.Y.Z+build
Date:
Commit:
Platforms:

## Summary

Short paragraph describing the release in user-facing language.

## Highlights

-
-
-

## Fixes

-
-
-

## Platform Notes

### Windows

- Signing status:
- Installer:
- Update manifest:
- Known platform notes:

### Android

- Build mode: FCM / Google Services or embedded ntfy
- APK:
- Push/notification notes:
- Known platform notes:

### iOS

- Channel: TestFlight / App Store / ad-hoc
- Build number:
- Signing/export method:
- Known platform notes:

### Web

- Deployment target:
- Browser/session notes:
- Known platform notes:

## Known Issues

- Issue:
  - Affected platforms:
  - Workaround:
  - Tracking:

## Upgrade Risks

- Risk:
  - Affected users:
  - Detection:
  - Rollback/hotfix plan:

## Compatibility

- Minimum supported OS versions:
- Matrix/homeserver compatibility notes:
- Migration notes:

## Verification Completed

- Windows:
- Android:
- iOS:
- Web:
- Update manifest:
- Rollback point:

## Download And Update Links

- Download page:
- Windows installer:
- Android APK:
- Source archive:
- Checksums:
- Release notes URL:

## Internal Release Manager Notes

- Release owner:
- Build machine:
- Commands used:
- Signing assets verified:
- Gaps/waivers:
- Follow-up owner:
```
