# Abuse Moderation Runbook

Draft status: operational runbook for public Inter Galactic support spaces if they exist.

## Intake

Default public abuse intake to Matrix-native reporting through the selected homeserver:

- message or event reports use `POST /_matrix/client/v3/rooms/{roomId}/report/{eventId}`;
- room reports use `POST /_matrix/client/v3/rooms/{roomId}/report`;
- user reports use `POST /_matrix/client/v3/users/{userId}/report`;
- blocking/ignoring users updates Matrix ignored-user account data, commonly `m.ignored_user_list`.

Accept direct Inter Galactic reports only for app-level issues, support spaces Inter Galactic actually operates, unavailable Matrix report flows, or routing help. Public Inter Galactic contact: `intergalactic@ourgalaxy.space`.

Collect only what is needed: reporter contact, reported Matrix user ID, room ID/alias, event ID/link, homeserver, timestamp, description, and safe evidence.

## Triage

Classify reports as:

- immediate safety threat;
- child sexual abuse material or exploitation;
- non-consensual sexual content;
- credible threat or violence;
- harassment/stalking/doxing;
- spam/raid/automation abuse;
- impersonation or fraud;
- copyright/IP complaint;
- ordinary support issue.

## Action

If Inter Galactic controls the service or room, moderators may remove content, warn users, kick/ban users, restrict rooms, preserve evidence, or seek legal advice. Do not assume control over private friend-group homeservers or third-party homeservers.

If another homeserver controls the account or content, route the report through Matrix-native reporting or direct the user to that homeserver's abuse process. Provide Matrix identifiers needed for that report when safe. Do not promise removal, suspension, or deletion on a homeserver Inter Galactic does not operate.

## Evidence Handling

Do not ask users to transmit illegal sexual content involving minors. Preserve only necessary metadata and safe evidence. Limit access to abuse records and retain them only as long as needed for moderation, safety, and legal reasons.

## Emergency Limits

Inter Galactic is not an emergency service. If someone is in immediate danger, direct the reporter to local emergency services.

## Current Staffing And Response Model

Public direct abuse/support intake is currently monitored by the sole project
operator at `intergalactic@ourgalaxy.space`; there is no separate moderation
staff roster. Matrix-native reports still go to the selected homeserver and do
not need to forward to the operator's personal homeserver unless that
homeserver is separately configured to do so.

Direct Inter Galactic reports are reviewed on a best-effort basis for app-level
issues, routing help, and Inter Galactic-operated support/community spaces.
Because there is no 24/7 staff, Inter Galactic does not promise emergency
response, real-time moderation, or action on third-party homeservers it does
not operate.

Appeals, follow-up information, and law-enforcement requests use the same
public inbox. The operator may preserve limited metadata or safe evidence when
needed for safety, abuse handling, or legal process, and may route reporters to
the responsible homeserver or local authorities when Inter Galactic lacks the
authority or staffing to act directly.
