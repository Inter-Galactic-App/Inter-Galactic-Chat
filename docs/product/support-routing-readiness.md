# Support Routing Readiness

Status: release-readiness reference

## Scope

This document records the lightweight public-support routing plan for beta
and release readiness. It does not prove backend routing, security review,
App Store approval, legal review, or private mailbox contents.

## Current State

- `intergalactic@ourgalaxy.space` is the monitored public point of contact
  for support, privacy, abuse-routing help, and security.
- In-app Help -> Report a Bug is implemented for desktop and mobile. The flow
  previews the outbound payload, sends user-entered fields, and can include
  optional redacted logs and diagnostics.
- Help & Safety separates Matrix-native abuse reports from app bug reports.
  Matrix-native reports go to the selected homeserver; app bug reports go to
  Inter Galactic support.
- Beta product templates exist for bug reports, feature requests, known
  issues, update communication, and response snippets.
- A website feedback and feature-request intake form is planned as a
  complement to Help -> Report a Bug; implementation is still pending
  website/API work and app-link work. The design lives with the website
  project, not this repo.
- The lightweight inbox/release-candidate triage cadence is defined in
  `docs/product/feedback-triage.md`: daily during active beta pushes, twice
  per week in quiet beta periods, before release candidates, and immediate
  escalation for critical reports.

Reference docs:

- `docs/architecture/diagnostics/bug-reporting-flow.md`
- `docs/policies/SUPPORT.md`
- `docs/policies/REPORT_ABUSE.md`
- `docs/policies/COMMUNITY_GUIDELINES.md`
- `docs/product/feedback-triage.md`
- `docs/product/response-snippets.md`

## Routing Matrix

| Request type | First route | Triage action | Escalate when |
| --- | --- | --- | --- |
| App bug | Help -> Report a Bug, then support email if the app cannot open | Normalize report, assign beta severity, request only missing evidence | Diagnosis, validation, or release notes are needed beyond triage |
| Feature request | Website feedback form once implemented; feature request template, Matrix room, or email until then | Capture user problem and status; keep separate from diagnostic bug reports | A product decision or website/API work is needed |
| Abuse or safety | In-app Matrix report/block controls or selected homeserver abuse path | Explain Matrix-native routing and collect safe app-level context only | An exploit, homeserver-operator issue, or legal/emergency pathway applies |
| Privacy request | Selected homeserver for account/data it controls; Inter Galactic email for app-policy routing | Route without promising homeserver action | Policy wording needs verification |
| Account deletion | Selected homeserver account process | Explain Inter Galactic cannot delete third-party homeserver accounts | Account settings handoff is unclear or app UI evidence is needed |
| Security report | Private email to `intergalactic@ourgalaxy.space` | Keep report private and route directly | Any exploit, token, E2EE, privacy, or infrastructure risk is alleged |
| Store/release metadata issue | Whoever currently owns release metadata | Record stale or risky wording; do not edit release metadata without that owner's involvement | Metadata affects App Store/Play Store submission |

## Metadata Review Findings

Android Fastlane metadata has historically contained upstream Commet
branding and must be checked before any public Inter Galactic submission:

- `fastlane/metadata/android/en-US/title.txt`
- `fastlane/metadata/android/en-US/full_description.txt`
- `fastlane/metadata/android/jp-JP/title.txt`
- `fastlane/metadata/android/jp-JP/full_description.txt`
- `fastlane/metadata/android/zh-CN/title.txt`
- `fastlane/metadata/android/zh-CN/full_description.txt`

Metadata should preserve required fork/AGPL attribution without presenting the
submitted app as Commet. Public copy should avoid implying affiliation with
Matrix.org, Commet, Discord, Messenger, Apple, Spotify, LiveKit, or GIF
providers.

## Hosted Website URL Scope

The hosted URL surface is primarily website/public-content work:

- publish the support, abuse/reporting, privacy, terms/account,
  community-guidelines, and source-offer pages at stable public URLs;
- add the scoped feedback page and form at
  `https://app.ourgalaxy.space/feedback/` once the website/API path for it is
  implemented;
- record the final URLs in release docs and store-submission metadata;
- wire Settings/About/Help in-app links to those URLs only once each route is
  live.

This is separate from in-app bug reporting, which already sends app bug
reports to the support mailbox with user-entered fields and redacted logs.

Public support and policy routes:

- `https://app.ourgalaxy.space/support/`
- `https://app.ourgalaxy.space/report-abuse/`
- `https://app.ourgalaxy.space/privacy/`
- `https://app.ourgalaxy.space/terms/`
- `https://app.ourgalaxy.space/account-deletion/`
- `https://app.ourgalaxy.space/community-guidelines/`
- `https://app.ourgalaxy.space/source/`

## Evidence Still Needed Before Public Release

- Keep private escalation labels or folders for support, abuse, privacy, and
  security without documenting mailbox credentials or private message
  contents.
- Decide where the current public URLs are referenced in final submission
  metadata and GitHub release materials.
- Manually verify Matrix-native report/block flows against a real test
  homeserver.
- Update final public store metadata and submission packet fields.
- Confirm security/privacy claims and response expectations before policy
  pages are treated as final.
- Implement and smoke-test the feedback page/API before the website feedback
  route is treated as live.
- Link the app Help/Support surface to the feedback page only after that
  route is live and reviewed.

## Release Recommendation

Do not treat the broader public-support release blocker as clear until
private escalation ownership, Matrix-native report/block validation, a
security/privacy review, and final release/store metadata routing are all
reconciled. Do not treat the store-metadata blocker as clear until stale
upstream branding is removed or replaced in the submission metadata and fork
attribution is preserved in the correct source/license surfaces.
