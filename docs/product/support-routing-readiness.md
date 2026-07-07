# Support Routing Readiness

Status: COMMUNITY release-readiness notes
Owner: COMMUNITY for user-facing routing; S&C owns security/privacy correctness;
OPERATIONS/SERVER own hosted service or inbox infrastructure.
Last updated: 2026-06-14

## Scope

This document records the lightweight public-support routing plan for beta and
release readiness. It does not prove backend routing, security review, App
Store approval, legal review, or private mailbox contents.

## Current Evidence

- Policy drafts name `intergalactic@ourgalaxy.space` for support, privacy,
  abuse-routing help, and security contact.
- 2026-06-09 user confirmation: `intergalactic@ourgalaxy.space` is monitored
  and is the main public point of contact. No mailbox contents, credentials, or
  private reporter details were inspected or recorded.
- In-app Help -> Report a Bug is implemented for desktop and mobile. The flow
  previews the outbound payload, sends user-entered fields, and can include
  optional redacted logs and diagnostics.
- Help & Safety separates Matrix-native abuse reports from app bug reports.
  Matrix-native reports go to the selected homeserver; app bug reports go to
  Inter Galactic support.
- Beta product templates exist for bug reports, feature requests, known issues,
  update communication, and response snippets.
- 2026-06-14 COMMUNITY scoped the website feedback and feature-request intake
  system in `docs/product/website-feedback-system.md`; implementation is still
  pending SERVER website/API work and FEATURES app-link work.
- The lightweight inbox/release-candidate triage cadence is defined in
  `docs/product/feedback-triage.md`: daily during active beta pushes, twice per
  week in quiet beta periods, before release candidates, and immediate
  escalation for critical reports.
- 2026-06-12 release communication intake: QA/user validation and Operations
  endpoint monitoring are recorded for `v0.7.3+984`; COMMUNITY prepared a
  beta/user-facing update post in `docs/product/response-snippets.md`.

Reference docs:

- `docs/architecture/diagnostics/bug-reporting-flow.md`
- `docs/policies/SUPPORT.md`
- `docs/policies/REPORT_ABUSE.md`
- `docs/policies/COMMUNITY_GUIDELINES.md`
- `docs/product/feedback-triage.md`
- `docs/product/website-feedback-system.md`
- `docs/product/response-snippets.md`

## Routing Matrix

| Request type | First route | COMMUNITY action | Escalate when |
| --- | --- | --- | --- |
| App bug | Help -> Report a Bug, then support email if the app cannot open | Normalize report, assign beta severity, request only missing evidence | DEBUG, FEATURES, QA, or RELEASE PIPELINE need diagnosis, validation, or release notes |
| Feature request | Website feedback form once implemented; feature request template, Matrix room, or email until then | Capture user problem and status; keep separate from diagnostic bug reports | Product/FEATURES decision or SERVER website/API work is needed |
| Abuse or safety | In-app Matrix report/block controls or selected homeserver abuse path | Explain Matrix-native routing and collect safe app-level context only | S&C, homeserver operator, or legal/emergency pathway is required |
| Privacy request | Selected homeserver for account/data it controls; Inter Galactic email for app-policy routing | Route without promising homeserver action | S&C or DOCUMENTATION must verify policy wording |
| Account deletion | Selected homeserver account process | Explain Inter Galactic cannot delete third-party homeserver accounts | Account settings handoff is unclear or app UI evidence is needed |
| Security report | Private email to `intergalactic@ourgalaxy.space` | Keep report private and route to S&C | Any exploit, token, E2EE, privacy, or infrastructure risk is alleged |
| Store/release metadata issue | RELEASE PIPELINE / store metadata owner | Record stale or risky wording; do not edit release metadata without owner claim | Metadata affects App Store/Play Store submission |

## Metadata Review Findings

As of 2026-06-09, Android Fastlane metadata still contains upstream Commet
branding and should not be used for a public Inter Galactic submission without
RELEASE PIPELINE update:

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

The hosted URL blocker was primarily website/public-content work:

- publish the existing support, abuse/reporting, privacy, terms/account,
  community-guidelines, and source-offer pages at stable public URLs;
- add the scoped feedback page and form at `https://app.ourgalaxy.space/feedback/`
  after SERVER implements the website/API path;
- record those final URLs in release docs and store-submission metadata;
- hand the URLs to FEATURES only if Settings/About/Help in-app links need to
  be wired or refreshed.

This is separate from in-app bug reporting, which already sends app bug reports
to the support mailbox with user-entered fields and redacted logs.

As of the 2026-06-12 COMMUNITY handoff intake, the public support and policy
routes were recorded as:

- `https://app.ourgalaxy.space/support/`
- `https://app.ourgalaxy.space/report-abuse/`
- `https://app.ourgalaxy.space/privacy/`
- `https://app.ourgalaxy.space/terms/`
- `https://app.ourgalaxy.space/account-deletion/`
- `https://app.ourgalaxy.space/community-guidelines/`
- `https://app.ourgalaxy.space/source/`

## Evidence Still Needed Before Public Release

- Keep private escalation labels or folders for support, abuse, privacy, and
  security without documenting mailbox credentials or private message contents.
- Release Pipeline/Review still needs to decide where the current public URLs
  are referenced in final submission metadata and GitHub release materials.
- QA must manually verify Matrix-native report/block flows against a real test
  homeserver.
- RELEASE PIPELINE must update final public store metadata and submission
  packet fields.
- S&C must own any security/privacy claims and response expectations before
  policy pages are treated as final.
- SERVER must implement and smoke the feedback page/API before the website
  feedback route is treated as live.
- FEATURES must link the app Help/Support surface to the feedback page only
  after the route is live and reviewed.

## Release Recommendation

Treat mailbox monitoring as user-confirmed as of 2026-06-09, and treat the
basic beta release communication for `v0.7.3+984` as prepared as of
2026-06-12. Do not check the broader public-support release blocker until
private escalation ownership, QA report/block validation, S&C review, and final
release/store metadata routing are also reconciled. Do not check the
store-metadata blocker until stale upstream branding is removed or replaced in
the submission metadata and fork attribution is preserved in the correct
source/license surfaces.
