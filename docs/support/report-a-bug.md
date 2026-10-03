# Report a Bug

Status: implemented
Last updated: 2026-07-23

## What this is

Help → Report a Bug opens an in-app guided diagnostic interview. It replaces the
old blank technical form (title / severity / reproduction steps / expected /
actual) with plain-language questions so ordinary users can file actionable
reports without understanding software-testing terminology.

This is the app-bug reporter. It is separate from Help & Safety's Matrix-native
abuse reporting. Nothing is sent until the user previews the exact payload and
confirms submission — see `docs/architecture/diagnostics/bug-reporting-flow.md`
for the submission, redaction, and privacy guarantees, which are unchanged.

## Form flow (generic template)

1. **What part of the app is affected?** (required) — a category selector. The
   stable category id is stored separately from the displayed label.
2. **What happened?** (required) — the main free-text description. Users are not
   asked to repeat it elsewhere.
3. **What were you doing right before it happened?** (optional) — actions in
   order, plain language.
4. **How often does it happen?** (required) — Every time / Most of the time /
   Sometimes / Only happened once / Not sure.
5. **What should have happened instead?** (optional) — plain-language expected
   result.
6. **Category-specific questions** — a small targeted set for the chosen
   category only.
7. **What have you already tried?** — universal + category troubleshooting
   checkboxes, plus an optional note.
8. **Anything else that might help?** (optional) — additional details.
9. **Short summary** (required) — the title, with a Suggest button that drafts
   one from the description. Always editable.

Severity is expressed in plain language: **Minor**, **Disruptive**,
**Blocking**, **Crash or data concern**. These map to the unchanged internal
severity values `low` / `medium` / `high` / `critical`.

## Categories

`call_audio`, `call_video`, `streaming`, `messages_rooms`, `notifications`,
`media_upload`, `stories`, `emotes_stickers`, `accounts`, `encryption`,
`settings_accessibility`, `performance_crash`, `desktop_windows`, `other`.

## Contextual troubleshooting

After a category is selected the form shows a compact, dismissible
troubleshooting tips card. Rules:

- Tips are category-specific and never block submission.
- Opening the card never clears entered form data (it is inline, not a new
  route).
- Tips are inline-only today. There are no dedicated in-app troubleshooting
  routes yet, so no links are rendered — no misleading dead links. The
  category → destination map is tracked in
  `docs/support/troubleshooting/README.md`.

## Reliability

- Failed submissions keep the entered data and the previewed payload so the user
  can retry the same report.
- Retry reuses the same previewed payload, including the stable per-report
  `report_hash`, so the backend can correlate/deduplicate retries.
- Automatic app version, platform, and redacted logs remain included and
  optional exactly as before.

## Automatic call and streaming diagnostics

With detailed diagnostics enabled, reports categorized as Calls and audio,
Video calls and camera, or Screen sharing and streaming include a bounded
snapshot of the current call. The same collector is used by the fixed
Call/stream logs template.

The snapshot records call/stream state and health metrics needed to classify
mute, publication, connection, encode, decode, and render failures. It never
includes room names or IDs, session IDs, participant names or identities,
stream IDs, source titles, or captured media. If the user files the report
after the call has ended, the snapshot explicitly says there is no active call;
the existing recent redacted logs remain the source for prior-session events.

## Accessibility

Fields carry visible, associated labels; required fields are marked in text (not
color alone); section headings are exposed as headers; troubleshooting and
category answers expose selected/checked state; and validation errors are shown
in a screen-reader live region.

## Related files

- `intergalactic/lib/client/bug_report/bug_report_models.dart`
- `intergalactic/lib/client/bug_report/bug_report_service.dart`
- `intergalactic/lib/client/bug_report/call_stream_bug_report_diagnostics.dart`
- `intergalactic/lib/ui/pages/settings/categories/help/report_bug_page.dart`
- `docs/support/bug-report-schema.md`
- `docs/architecture/diagnostics/bug-reporting-flow.md`
