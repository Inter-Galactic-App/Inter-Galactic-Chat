# Troubleshooting Guidance Map

Status: partial (inline tips only)
Last updated: 2026-07-23

The Report a Bug guided form shows a compact troubleshooting tips card after the
user selects a category. Today those tips are **inline-only**: the app has no
dedicated in-app troubleshooting routes or hosted troubleshooting pages, so the
form deliberately renders no "View <category> troubleshooting" links. This
avoids misleading dead links (see the plan's non-goals).

Inline tip content is defined in
`intergalactic/lib/client/bug_report/bug_report_models.dart` as
`BugReportCategory.troubleshootingTips`.

## Intended category → destination map (follow-up)

When dedicated troubleshooting routes or docs are created, wire each category to
its destination and replace the inline-only card with a real link:

| Category | Intended destination |
|---|---|
| `call_audio` | Call/audio troubleshooting |
| `call_video` | Call/video troubleshooting |
| `streaming` | Streaming troubleshooting |
| `notifications` | Notification troubleshooting |
| `encryption` | Encryption / message-recovery troubleshooting |
| `media_upload` | Media/upload troubleshooting |
| `performance_crash` | App performance troubleshooting |
| `accounts` | Account/login troubleshooting |

## Missing documentation follow-up

None of the destinations above exist yet. Keep this map as the follow-up record
until a destination is created and linked from the app. Until then, the inline
tips are the only guidance and they never block the user from submitting a
report.
