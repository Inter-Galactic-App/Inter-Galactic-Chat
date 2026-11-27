# Beta Feedback Triage Workflow

This is the lightweight product/community workflow for beta-user bug reports,
feature requests, and general feedback. It is meant to keep reports actionable
without adding a heavy support desk process.

## Intake

Accepted intake channels can be Matrix rooms, direct messages, GitHub issues,
forms, or release-testing notes. Maintainers should normalize reports into one
of these buckets:

- Bug report: something expected is broken.
- Feature request: a new capability or product change.
- Usability feedback: confusion, friction, unclear copy, or workflow pain.
- Known issue update: a public-facing status change for beta users.

Default app-bug intake should use Help -> Report a Bug when possible because
that flow lets the user preview the outbound payload and optionally include
redacted logs and diagnostics. Email, Matrix, website, or issue-tracker intake
is still acceptable when the app cannot start, the user is offline, or the
report is not about app diagnostics.

Default feature-request and usability intake should use the website feedback
form once it is implemented. Until then, use the feature-request template,
Matrix, or support email and keep those reports separate from diagnostic bug
payloads.

Use `bug-report-template.md` for bugs and
`feature-request-template.md` for feature requests. For brief usability
feedback, capture the user quote, platform, screen/flow, and suggested next
action in the triage notes.

## Routing Rules

Use `support-routing-readiness.md` as the current COMMUNITY release-readiness
checklist for support, privacy, abuse, security, and metadata routing. Keep the
routes simple:

- App bugs and support questions: Help -> Report a Bug first, or
  `intergalactic@ourgalaxy.space` when the app flow is unavailable.
- Abuse and safety: Matrix-native report/block controls first because reports
  go to the selected homeserver; direct Inter Galactic contact is for app-level
  problems, unavailable report flows, or routing help.
- Privacy, account deletion, and homeserver account decisions: route to the
  selected homeserver when it controls the account or data; use Inter Galactic
  contact only for app-policy questions or routing help.
- Security reports: keep details private and route to the security/S&C owner.
- Feature requests: use the website feedback form when live, then normalize
  the user problem with `feature-request-template.md`; do not mix feature
  requests with diagnostic bug-report payloads.

Use `response-snippets.md` for short beta-room or email replies. Snippets are
manual text helpers, not response-time commitments.

## Bug Severity

- `critical` - Data loss, security/privacy risk, login blocked, app crash loop,
  messaging fully unusable, or beta rollout must stop.
- `major` - Important feature is broken or very unreliable, but users have a
  workaround or only a subset of users is blocked.
- `moderate` - Noticeable bug that affects normal use but does not block the
  main workflow.
- `cosmetic` - Visual polish, wording, alignment, animation, or other minor UX
  issue that does not change functionality.

## Engineering Severity Mapping

Use beta severity for user-facing triage and map it to the maintainer's private
engineering tracker when engineering accepts the issue:

| Beta severity | Engineering severity | Use when |
| --- | --- | --- |
| `critical` | `Critical` | Release should stop or roll back; data loss, privacy/security risk, login blocked, messaging unusable, or crash loop. |
| `major` | `High` | Important feature is broken, unreliable, or affects a broad beta segment, but the app remains usable or there is a workaround. |
| `moderate` | `Medium` | Noticeable bug on a feature/platform that users can work around or that is fixed but still needs runtime validation. |
| `cosmetic` | `Low` | Copy, layout, visual polish, animation, or other non-functional issue. |

In-app bug reports may arrive with the server-supported labels `critical`,
`high`, `medium`, and `low`. Normalize those into the beta labels as:
`critical -> critical`, `high -> major`, `medium -> moderate`, and
`low -> cosmetic`.

When an internal `High` bug is already fixed in client but only needs a smoke
pass, COMMUNITY may publish it as `moderate` if users have a clear workaround
and the remaining risk is validation rather than active breakage.

## Reproducibility Checklist

Ask for the smallest useful evidence set first:

- Logs: app diagnostic logs, browser console logs, or system crash/event logs.
- Screenshots or screen recording: with private room/account details hidden
  when possible.
- Platform/version: app build, OS/browser version, device model, and
  homeserver when relevant.
- Reproduction steps: exact path from a clean starting state to the issue.

Repro status should stay simple:

- `confirmed` - A team member reproduced it or logs clearly prove it.
- `likely` - Multiple users report the same pattern or evidence is strong.
- `needs info` - Missing logs, screenshots, version, or steps.
- `not reproducible` - Tried with the available details and could not trigger
  it.

## Bug Triage Flow

1. Create or update one normalized bug report.
2. Assign severity using the beta categories above.
3. Check whether it is already a known issue.
4. Request only the missing evidence needed to reproduce or route it.
5. Link to the maintainer's private engineering tracker when engineering
   accepts it.
6. Add user-facing status to `known-issues.md` only when beta users need to
   know about the issue, workaround, or rollout risk.
7. Close the user-facing report when the fix ships or the issue is rejected as
   unsupported/intended behavior.

## Triage Cadence

Recommended ownership: community/support maintainers own intake and
user-facing status; engineering maintainers own client diagnosis; release
maintainers own merge/release closeout; security maintainers own privacy or
security-sensitive report handling; operations maintainers own server/endpoint
incidents.

- Active beta push: triage new in-app reports once per day.
- Quiet beta period: triage twice per week, with one pass before any release
  candidate.
- Release candidate window: triage before build cut, after smoke testing, and
  before public update notes are posted.
- Critical report: interrupt the normal cadence and page the relevant owner
  immediately.
- After a fix ships: update `known-issues.md` in the same pass that closes or
  updates the private engineering tracker.

## Feature Request Flow

Feature requests move through:

- `investigating`
- `planned`
- `rejected`
- `completed`

COMMUNITY should keep the request framed around the user problem. Product or
engineering can then decide whether the right answer is a new feature, a docs
change, a settings adjustment, or no change.

When rejecting a request, write a short reason that a user can understand:
privacy risk, Matrix compatibility, product fit, maintenance cost, duplicate
request, or replaced by an existing workflow.

The website feedback form's scope is tracked with the website project, not
this repo. The form should stay lightweight: title, user problem, requested
behavior, platform/version when relevant, optional contact, and optional
priority. Diagnostic logs and automatic screenshots belong in the
in-app bug-report flow, not feature request intake.

## User-Facing Known Issues

Use `known-issues.md` for beta-facing status. Keep it practical:

- one short summary per issue
- affected platforms/builds
- severity
- current status
- workaround, if any
- next update expectation

Do not publish private implementation details, tokens, internal logs, user IDs,
or room names. Keep private tracker links in maintainer-only copies unless they
are safe for beta users to open.

## Update Communication Format

Use this format for Matrix room posts, GitHub issue updates, or release-testing
notes:

```text
Status update: <issue/request title>

What changed:
- <short user-facing change>

Who is affected:
- <platform/build/user group>

What to do now:
- <update, workaround, retry, or no action>

Next update:
- <when or what evidence we need next>
```

## Current Process Gaps

- Private engineering trackers may use different severity labels than
  beta-facing status updates.
- The website-backed feedback form is scoped but not implemented or linked from
  the app yet.
- Email-first triage remains practical for beta volume, but a protected inbox
  or dashboard may be needed if request volume grows.
- Website feedback should be routed through privacy/security review before it
  collects contact details, platform metadata, screenshots, or attachments.
