# Bug Reporting Flow

Status: implemented
Last updated: 2026-07-23

## Guided Diagnostic Interview (2026-07-23)

The generic app-bug template now presents a plain-language guided interview
instead of software-testing fields. The fixed `call_stream_logs` template is
unchanged and still uses its static details block. Full user/support-facing
detail lives in `docs/support/report-a-bug.md`,
`docs/support/bug-report-schema.md`, and `docs/support/troubleshooting/`.

Guided form sections (generic template):

1. What part of the app is affected? — required category selector. A stable
   category id (e.g. `call_audio`) is stored separately from the label.
2. What happened? — required primary free-text description (replaces the vague
   "actual behavior" prompt).
3. What were you doing right before it happened? — optional ordered actions
   (the former "reproduction steps").
4. How often does it happen? — required frequency (`always`/`usually`/
   `sometimes`/`once`/`unknown`).
5. What should have happened instead? — optional, plain-language expected
   result.
6. Category-specific follow-up questions — a small, targeted set per category
   (single-select where possible), stored as `category_answers`.
7. What have you already tried? — universal + category-specific troubleshooting
   checkboxes plus an optional note, stored as `troubleshooting_attempted`.
8. Anything else that might help? — optional additional details.
9. Short summary — required title, with a Suggest action that drafts one from
   the description; the user can always edit it.

After a category is chosen the form shows a compact, dismissible troubleshooting
tips card. Tips are inline-only and never block submission. Dedicated in-app
troubleshooting routes are planned but not implemented; until they exist, no
links are rendered. Opening the tips card never clears entered form data
because it is inline, not a navigation. Severity uses plain-language labels (Minor/Disruptive/Blocking/
Crash or data concern) mapped to the unchanged wire values
(`low`/`medium`/`high`/`critical`).

Backward compatibility: all previous payload fields are preserved. Programmatic
generic reports without a selected category (Developer Logs handoff, next-launch
crash prompt) keep the original description shape and simply omit the new
structured fields. See the Payload Shape section for the added keys.

## Purpose

Inter Galactic includes an in-app app-bug reporter for desktop and mobile. It
is separate from Help & Safety's Matrix-native abuse reporting. Abuse reports
go to the selected homeserver; app bug reports go to Inter Galactic support.

## Entry Points

- Help -> Report a Bug opens the full flow.
- Help & Safety includes a "Report app bug" shortcut for users who arrive from
  the safety/support page.
- Developer -> Logs exception rows use the same flow with the captured
  exception details prefilled.
- Call Diagnostics -> Report stream logs writes the current redacted call
  diagnostics snapshot into recent logs, then opens the fixed Call/stream logs
  report template.
- Next-launch crash detection uses the same flow when the previous run wrote a
  pending crash marker from an unhandled/fatal error path.
- The fatal startup page cannot open the settings reporter, so it only copies
  redacted startup details for a later bug report or support request.

Developer -> Logs opens exception details in a separate popup/bottom-sheet
route. The `Report Issue` action must return a redacted prefill object as that
route's pop result, then let the Logs page open the bug reporter after the
detail route is fully dismissed. Opening the bug reporter directly from inside
the expanded-error route can leave modal barriers stacked without a visible
form. On desktop, `showReportBugDialog` also constrains the form before placing
it inside the popup dialog so Flutter does not ask the form's dropdown/text
layout builders for unsupported intrinsic dimensions.

When `Log` observes an explicit fatal boundary, it writes a small redacted
`pending-crash-report.json` marker next to the diagnostic log files. The marker
is written only for boundaries whose message identifies the run as unable to
continue: fatal startup errors and unhandled headless/background entrypoint
failures. It also trusts the explicit marker sources that are only written by
fatal startup handling, by the mobile native LiveKit join guard, or by the
scoped native call-action guards around desktop/mobile WebRTC/LiveKit actions.
Main app `runZonedGuarded`, zone callback, Flutter, and `PlatformDispatcher`
errors are still persisted in diagnostic logs, but they do not create a
next-launch crash marker by source label alone because recoverable async
callbacks can reach those handlers while the app remains open. The app shell
checks the marker on the next UI launch, offers the user a "Report Crash"
prompt, clears the marker after the user chooses, and opens the normal Report a
Bug dialog with critical severity, recent logs, diagnostics, and the redacted
crash summary prefilled. The app never submits the crash report automatically;
the user still previews and confirms the exact outbound payload.
When a newer build reads an older pending marker, it rechecks the current
fatal/headless/native-guard allowlist and deletes legacy nonfatal runtime
markers without showing the crash prompt.

The crash prompt is reserved for genuinely unhandled/fatal boundaries. Expected
recoverable failures, such as an MXC media download returning `M_NOT_FOUND`
while an avatar or timeline image is loading, must be handled by the feature
surface and reported to local image/error listeners instead of escaping to the
app zone. This keeps the crash reporter useful without turning missing remote
media or nonfatal async callback errors into a next-launch crash prompt.
URL-preview timeline refreshes follow the same boundary: if a synced event no
longer has a previewable link by the time preview loading runs, the component
returns no preview instead of forcing a link lookup and surfacing a zone error.

## Client Flow

1. The user fills in title, severity, reproduction steps, optional expected
   behavior, and actual behavior. The reporter does not collect contact info.
   Specialized entry points may preselect a fixed template and details block so
   support can distinguish generic app bugs from call/stream logs.
   On mobile, the form follows keyboard insets and exposes keyboard-dismiss
   actions so the preview and submit controls remain reachable after long text
   entry.
2. The user chooses whether to include recent logs and detailed diagnostics.
3. For call/audio, video-call, or streaming categories, the client collects a
   bounded current-session snapshot before loading recent logs. The snapshot
   omits identifiers and media and is skipped when diagnostics are disabled.
4. The client builds a redacted JSON payload locally.
5. The preview screen shows the exact payload that will leave the device,
   payload size, and the JSON attachment entries included in the upload.
6. The user confirms submission.
7. `BugReportService.submit(...)` posts JSON to the configured Inter Galactic
   bug-report endpoint for the build.
8. The UI shows success, or a failure state with retry using the same previewed
   payload.

Recent diagnostic logs are capped before preview and upload. The cap preserves
the newest redacted log tail and inserts an omission marker when older log
output was dropped. Log contents are sent once, as the `diagnostic-logs.txt`
text attachment. The JSON body carries only log metadata and a small redacted
preview so the payload limiter does not drop the log attachment by counting the
same log text twice. The full encoded JSON payload, including base64 JSON
attachments, also targets a conservative 90 KB cap. If metadata or attachment
encoding pushes the payload over that cap, logs are trimmed again; if
diagnostics still make the payload too large, detailed diagnostics are replaced
with an explicit omitted placeholder. This keeps busy sessions from sending
unexpectedly large JSON bodies while retaining the most useful failure context.

## Important Files

- `intergalactic/lib/client/bug_report/bug_report_models.dart`
- `intergalactic/lib/client/bug_report/bug_report_service.dart`
- `intergalactic/lib/client/bug_report/call_stream_bug_report_diagnostics.dart`
- `intergalactic/lib/client/bug_report/pending_crash_report.dart`
- `intergalactic/lib/client/bug_report/pending_crash_report_store.dart`
- `intergalactic/lib/client/bug_report/crash_report_prompt.dart`
- `intergalactic/lib/debug/log.dart`
- `intergalactic/lib/ui/pages/settings/categories/help/report_bug_page.dart`
- `intergalactic/lib/debug/log_redactor.dart`
- `intergalactic/lib/ui/pages/settings/categories/developer/log_page.dart`
- `intergalactic/lib/ui/pages/fatal_error/fatal_error_page.dart`

## Payload Shape

The upload is JSON, not multipart in this pass. The payload includes:

- flat support-intake compatibility fields: `title`, `summary`,
  `severity`, `description`, `message`, `reproduction_steps`, `app_version`,
  and `platform`
- API compatibility aliases: `reproductionSteps`, `expectedBehavior`,
  `actualBehavior`, and `appVersion`
- `schema_version`
- template routing fields: `template_tag`, `templateTag`, and `template_label`
  at the top level and inside `report`. Current tags are `generic_app_bug` and
  `call_stream_logs`.
- `timestamp`
- `report_hash` and `reportHash`: non-PII per-report correlation hashes
  generated locally from timestamp plus random entropy
- `app`: app name, version, git hash, build detail, build fingerprint
- `environment`: configured platform, target platform, web flag, device summary
- `report`: user-entered fields. For guided reports this now also includes
  `category`, `category_label`, `frequency`, `frequency_label`,
  `severity_label`, `what_happened`, `what_were_you_doing`,
  `troubleshooting_attempted` (list of `{id,label}`), `troubleshooting_note`,
  `category_answers` (list of `{id,question,answer}`), and `additional_details`.
  The top level mirrors `category`, `category_label`, `frequency`,
  `frequency_label`, and `what_happened` for flat support-intake scanning. The
  `description`/`message` body is rendered as a sectioned, developer-readable
  summary (What happened / What you were doing / Expected result /
  Troubleshooting attempted / Category-specific answers / Additional details)
  rather than one paragraph. All of these fields are omitted for legacy
  reports without a category, and all user text stays redacted.
- `included`: logs/diagnostics booleans
- `report_notice`: optional redacted user-facing note for template-driven
  reports
- `additional_metadata`: optional template-specific metadata
- `log_attachment`: optional summary for the attached redacted log text
- `log_preview`: optional small redacted newest-log preview for user review
- `attachments`: API-ingested text attachments with `name`, `mimeType`, and
  `contentBase64`; recent logs use `text/plain`, and diagnostics use
  `application/json`
- `diagnostics`: optional redacted device/runtime diagnostic map used by the
  server summary. For `call_audio`, `call_video`, `streaming`, and the fixed
  `call_stream_logs` template, it also contains a bounded
  `feature_diagnostics` object with `scope: call_stream`. The scope is mirrored
  as `feature_diagnostics_scope` at the top level and in `report`.
- `attachment_transport_fallback`: optional metadata explaining that additional
  attachments were omitted because the upload would exceed the report limit

Future multipart or Matrix-admin-room integrations should keep the same
reviewable payload boundary. Multipart upload may replace base64 attachment
encoding later if support needs larger non-audio artifacts.

Call/stream reports use the same redacted log attachment path as generic app
reports. The Call Diagnostics action writes a `call-diagnostics-report` log
snapshot first. The bug-report service also writes a compact,
identifier-free `bug-report-call-stream-diagnostics` line and attaches the
structured active-session snapshot. The report remains a normal JSON bug
report with logs and diagnostics enabled by default rather than a separate
stream-log upload. The structured snapshot excludes room/session IDs,
participant identities and names, stream IDs and labels, capture source titles,
and media content. If the call has ended, it reports `no_active_call` and does
not retain an ended-session snapshot.

RNNoise WAV capture remains local-only. The capture bundle writer emits
`capture-manifest.json` and per-stage metadata into the local diagnostics
folder for developer inspection, but the app does not open an Audio WAV report
template, does not add `rnnoise_wav_artifacts` metadata to bug reports, and
does not submit WAV/audio attachments. Stale callers that try to provide
audio attachments or RNNoise WAV metadata have those fields omitted with an
explicit fallback note.

The current client caps the log attachment source at 64 KB before JSON encoding
and keeps the total encoded JSON payload under 90 KB where possible. The
payload preview and attachment summary reflect the capped text size, not the
uncapped diagnostic source size. Empty logs are omitted instead of being sent
as a zero byte attachment because the API only accepts non-empty attachments.
Additional supported non-audio attachments are removed from the transport
payload and replaced with `attachment_transport_fallback` metadata if they
would push the encoded JSON over the upload limit after logs and diagnostics
are bounded.

Severity is user-selected in the form and sent as one of the server-supported
lowercase values: `critical`, `high`, `medium`, or `low`. The form defaults to
`medium` so support emails do not show `unknown` for normal app-submitted
reports.

Device diagnostics are sanitized before redaction, preview, and attachment
encoding. The client omits local machine/license identifiers such as Windows
`digitalProductID`, Windows `productId`, host/computer names, device IDs,
serial numbers, machine GUIDs, vendor identifiers, Android IDs, and usernames.
Large numeric arrays are collapsed to a short placeholder such as
`[omitted numeric array, length=18]` so support emails and JSON previews remain
readable without losing the fact that a large binary-like field existed.
The conversion, sanitizer, and final redaction pass also guard recursive or
overly deep diagnostic maps/lists with explicit omitted placeholders before
preview or attachment encoding, so unusual platform metadata cannot make the
preview builder overflow the stack.
Unknown diagnostic objects and map keys are stringified through a guarded path;
if a platform object throws or recurses during `toString()`, the report keeps an
explicit omitted-value placeholder instead of failing preview construction.

## Redaction Behavior

Redaction runs before preview and again before upload encoding. The reporter
reuses `LogRedactor` and extends it for bug-report exports:

- Authorization headers
- cookies
- access tokens and refresh tokens
- Matrix access-token shapes
- Matrix user IDs, room IDs, room aliases, event IDs, and MXC URIs, including
  assignment-shaped diagnostics such as `sender=@...` and `room_id=!...`
- OpenID, ID-token, JWT, and LiveKit JWT fields
- LiveKit participant identity fields such as `participant=...` and
  `participantIdentity=...`
- password/passwd fields
- session key, Matrix crypto, Megolm/Olm, recovery, backup, private-key, API
  key, client-secret, and generic secret fields
- query-string token/password values
- JSON or text Authorization / Proxy-Authorization values
- camelCase token field names such as `accessToken` and `refreshToken`
- local filesystem paths, reduced to `[LOCAL_PATH]/filename`
- incidental email addresses
- noisy device-info identifiers and large binary-like numeric arrays before
  diagnostics are attached

Legacy or manually supplied contact-shaped payload fields are redacted before
upload and are not generated by the in-app form. The Inter Galactic API also
rejects legacy top-level contact fields before storage so older or hand-built
payloads cannot reintroduce contact collection through this path.

Redaction is intentionally idempotent: applying the redactor again to a string
that already contains `[REDACTED]` should not grow or corrupt that marker.
For text attachments, the final outbound payload redaction decodes
`contentBase64`, redacts the decoded text, then re-encodes it. This preserves
the belt-and-suspenders upload redaction pass without running large base64 blobs
through the text regex redactor directly.

## Privacy Guarantees

- The reporter never uploads automatically.
- Next-launch crash reporting only opens an opt-in prompt and then the normal
  preview/confirm flow.
- The user sees the exact outbound payload before submission.
- The reporter does not collect contact info; support correlation uses the
  generated report hash or the server-side report ID when one is returned.
- The Inter Galactic API stores bug reports without source IP hashes or request
  user-agent values in report metadata. Request IP is used only for the
  server's ephemeral in-process rate-limit key.
- Logs and detailed diagnostics are optional.
- Bug reports do not collect or upload RNNoise WAV/audio diagnostic files.
- Matrix crypto/session material and local file paths are redacted before both
  preview and upload.
- Uploads do not include app-owned API secrets because the endpoint requires no
  client secret.
- Upload failure diagnostics include endpoint scheme/host/path, status or
  transport failure class, payload size, and a short redacted server response
  message when one is available. They do not log the outbound JSON body.

## Known Limitations

- The current endpoint client posts JSON only. Multipart attachment support can
  be added later if support needs binary artifacts.
- Only a recent log tail is uploaded. Users can still copy/save broader logs
  from Developer -> Logs when needed.
- Offline users receive a retryable failure state; reports are not queued in
  local storage.
- The fatal startup page cannot complete the in-app preview/submit flow because
  normal app startup did not finish. It can still write the redacted pending
  crash marker so the next successful UI launch can offer the normal report
  flow.
- Desktop call-room native actions now use scoped pre-operation crash markers
  for microphone enable, Push to Talk runtime microphone enable or microphone
  sender detach/reattach, and screen share start/stop in both LiveKit call
  rooms and direct Matrix calls. If native
  WebRTC/LiveKit code terminates the process before Dart observes successful or
  handled-failure completion, the next launch can offer the user a crash report
  without trusting generic app-zone, Flutter, or `PlatformDispatcher` errors.
  Direct Matrix screen-share replacement keeps the `screen-share-start` marker
  active while the previous share is stopped, since the marker store is a
  single file and a nested stop marker would overwrite the crash source that
  matters for the replacement publish.
- The backend contract is intentionally minimal: a 2xx response is success,
  and optional `report_id` / `message` fields are displayed when returned.
  Edge or reverse-proxy access logs are separate operations logs and are not
  part of the stored support artifact reviewed by the in-app preview.
