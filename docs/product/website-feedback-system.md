# Website Feedback And Feature Request Intake

Status: scoped by COMMUNITY on 2026-06-14; awaiting SERVER and FEATURES work.
Owner: COMMUNITY owns workflow and triage; SERVER owns website/API delivery;
FEATURES owns any in-app link; S&C owns privacy/security wording review.

## Goal

Provide a lightweight website path where beta users can send general feedback,
usability notes, and feature requests for the app without using the diagnostic
bug-report flow.

This should complement Help -> Report a Bug. It should not replace the in-app
bug reporter when the user can send redacted logs and app diagnostics.

## Recommended MVP

- Add a public website page at `https://app.ourgalaxy.space/feedback/`.
- Submit feedback through a server-side endpoint, not a client-only email link.
- Route submissions to the monitored support inbox with a stable request ID.
- Keep a private server-side record only if SERVER already has an appropriate
  low-maintenance store; otherwise email-first is acceptable for the first beta.
- Add an app Help/Support link after the website form is live.

Use `mailto:` only as a fallback link for users whose browser or network blocks
the form. The primary path should be a website form because generated emails
are inconsistent across desktop and mobile clients, expose less structured
metadata, and are harder to rate-limit.

## User Routes

| User need | Route | Notes |
| --- | --- | --- |
| App bug with logs or diagnostics | Help -> Report a Bug | Preferred path when the app opens. |
| Feature request | Website feedback form | Normalize into `feature-request-template.md`. |
| General feedback or usability friction | Website feedback form | Capture the screen/flow and user problem. |
| Bug when app cannot open | Website feedback form or support email | Ask for platform/version and reproduction steps. |
| Abuse, privacy, account deletion, or security | Existing support/policy routes | Do not collect private evidence in the feedback form. |

## Form Fields

Required:

- Type: `feature_request`, `usability_feedback`, `general_feedback`, or
  `bug_without_logs`.
- Title.
- Description or user problem.

Optional:

- Requested behavior.
- Current workaround.
- Platform: Windows, Android, iOS, web, Linux, macOS, or all.
- App version/build.
- Contact email.
- Priority from the user's perspective: low, normal, or high.
- Reproduction steps for `bug_without_logs`.

Do not include diagnostic logs, automatic screenshots, Matrix room IDs, access
tokens, recovery keys, or private message content in this form.

## Server Implementation Scope

SERVER should implement:

- A responsive website page for the feedback form.
- A same-origin `POST` endpoint for structured JSON submissions.
- Field validation and a small payload cap.
- Rate limiting, spam controls, and a honeypot field; add stronger CAPTCHA only
  if abuse appears.
- Server-side sanitization before email or storage.
- A generated request ID included in the email subject/body.
- Email delivery to the monitored support inbox or an equivalent private intake
  destination.
- A generic success/failure response that does not leak server internals.

Recommended email subjects:

- `[Inter Galactic][Feature][<requestId>] <title>`
- `[Inter Galactic][Feedback][<requestId>] <title>`
- `[Inter Galactic][Bug-No-Logs][<requestId>] <title>`

Attachments are out of scope for the MVP. If screenshots become necessary,
route the user to support email or add a separately reviewed upload contract.

## App Link Scope

FEATURES should add a Help/Support entry after SERVER confirms the website form
is live:

- Label: `Send feedback or request a feature`.
- Destination: `https://app.ourgalaxy.space/feedback/`.
- Open externally using the existing safe link pattern.
- Do not attach logs, local paths, Matrix identifiers, room names, or account
  identifiers.
- Do not prefill user identity. Platform and app version query parameters may
  be considered only after S&C reviews the privacy wording.

## Triage Workflow

COMMUNITY should triage submissions using `feedback-triage.md`:

1. Separate feature requests, usability feedback, general feedback, and
   bug-without-logs reports.
2. Normalize feature requests into `feature-request-template.md`.
3. Move requests through `investigating`, `planned`, `rejected`, or
   `completed`.
4. Send diagnostic bugs back to Help -> Report a Bug when the app is usable.
5. Add user-facing known issue updates only when beta users need status,
   workaround, or rollout-risk visibility.

## Validation Checklist

- Submit each form type and confirm the private intake receives structured
  fields and a request ID.
- Confirm missing required fields and oversized payloads are rejected.
- Confirm spam controls do not block one normal beta-user submission.
- Confirm success and failure states are understandable on mobile and desktop.
- Confirm no logs, screenshots, local paths, Matrix IDs, or private content are
  auto-collected.
- Confirm the app Help link opens the website form after FEATURES wires it.

## Out Of Scope

- Public issue creation.
- Public roadmap voting.
- Authenticated support dashboard.
- Automatic screenshots, logs, or diagnostic uploads.
- In-app feature request form.
- Attachments or media uploads.
- Abuse, privacy, account deletion, or security incident intake.
