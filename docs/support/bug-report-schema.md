# Bug Report Payload Schema

Status: implemented
Owner: DEBUG / Help & diagnostics
Last updated: 2026-07-23

The upload is a single redacted JSON body (`schema_version: 1`). This document
covers the fields added by the 2026-07-23 guided interview. All previously
documented fields are unchanged; see
`docs/architecture/diagnostics/bug-reporting-flow.md` for the full baseline
payload and the redaction/privacy guarantees.

## Backward compatibility

- No existing field was removed or renamed. Legacy flat and camelCase aliases
  (`title`, `summary`, `severity`, `description`, `message`,
  `reproduction_steps`, `reproductionSteps`, `expected_behavior`,
  `actual_behavior`, `app_version`, `appVersion`, `platform`, …) are preserved.
- `actual_behavior` / `actualBehavior` remain populated: for guided reports they
  carry the "What happened?" text (which replaced the "actual behavior" prompt).
- The new structured fields appear **only** for guided reports where a category
  is selected. Programmatic generic reports without a category (Developer Logs
  handoff, next-launch crash prompt) keep the original description shape and
  omit these fields.
- `severity` wire values are still `low` / `medium` / `high` / `critical`. The
  plain-language labels are for display and are also exported as
  `severity_label`.

## New top-level fields (guided reports)

| Field | Type | Notes |
|---|---|---|
| `category` | string | Stable id, e.g. `call_audio`. |
| `category_label` | string | Display label, e.g. `Calls and audio`. |
| `frequency` | string | One of `always`/`usually`/`sometimes`/`once`/`unknown`. |
| `frequency_label` | string | Display label, e.g. `Sometimes`. |
| `what_happened` / `whatHappened` | string | Primary description (redacted). |
| `feature_diagnostics_scope` | string | Present as `call_stream` when a call/audio, video-call, streaming, or fixed call-log report includes the category snapshot. |

## New `report` object fields (guided reports)

| Field | Type | Notes |
|---|---|---|
| `category`, `category_label` | string | As above. |
| `frequency`, `frequency_label` | string | As above. |
| `severity_label` | string | Plain-language severity, e.g. `Disruptive`. |
| `what_happened` | string | Primary description (redacted). |
| `what_were_you_doing` | string | Actions before the problem (redacted). |
| `expected_behavior` | string | Expected result (redacted). |
| `troubleshooting_attempted` | array | `[{ "id": string, "label": string }]`. |
| `troubleshooting_note` | string | Optional free-text note (redacted). |
| `category_answers` | array | `[{ "id": string, "question": string, "answer": string }]` (answers redacted). |
| `additional_details` | string | Optional extra context (redacted). |
| `feature_diagnostics_scope` | string | Mirrors the attached category-diagnostic scope for support scanning. |

## Description body format (guided reports)

`description` / `message` is rendered as a sectioned, developer-readable summary
so an agent can scan it, rather than one concatenated paragraph:

```text
Category: Calls and audio
Frequency: Sometimes

What happened:
...

What you were doing:
...

Expected result:
...

Troubleshooting attempted:
- Left and rejoined the call
- Note: ...

Category-specific answers:
- Could you hear other participants?: No

Additional details:
...
```

## Stable value vocabularies

- **Categories:** `call_audio`, `call_video`, `streaming`, `messages_rooms`,
  `notifications`, `media_upload`, `stories`, `emotes_stickers`, `accounts`,
  `encryption`, `settings_accessibility`, `performance_crash`,
  `desktop_windows`, `other`.
- **Frequency:** `always`, `usually`, `sometimes`, `once`, `unknown`.
- **Severity (wire):** `low`, `medium`, `high`, `critical`.

## Diagnostics by category

When detailed diagnostics are enabled, `call_audio`, `call_video`, and
`streaming` reports automatically add:

- `feature_diagnostics_scope: "call_stream"` at the top level and in `report`;
- `diagnostics.feature_diagnostics`, containing a `scope` plus a bounded
  category snapshot; and
- a compact `bug-report-call-stream-diagnostics` line before recent logs are
  collected.

The fixed `call_stream_logs` template uses the same collector in addition to
the full snapshot already written by Call Diagnostics.

The category snapshot includes active-session state, mute/camera/share state,
deafen state, stream and participant counts, call-health issue codes, and
bounded sender/receiver transport and render metrics. It excludes room and
session IDs, participant names and identities, stream IDs and labels, capture
source titles, and all audio/video content. The normal redaction pass,
`diagnostics.json` attachment encoding, and 90 KB payload limiter still apply.

If no call is active, the snapshot records `status: "no_active_call"` rather
than retaining an ended session. Notification-specific diagnostics remain a
separate follow-up.
