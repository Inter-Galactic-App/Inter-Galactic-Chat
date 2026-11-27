# Stream viewer indicator

## Viewing contract

A receiver advertises a remote screen share only while its call tile is
revealed or its panel popout is open. Hidden tiles, camera tiles, and local
shares are excluded. A mounted call surface clears its intent while the app
is hidden/paused/detached, on surface disposal, and on session replacement.
The session unions intent from multiple call surfaces.

Intent travels as a reliable LiveKit data packet on
`intergalactic.stream_viewers.v1`, targeted to each share's publisher
identity. It contains only version 1 and a bounded set of publication SIDs.
The publisher accepts only SIDs of its own live screen-share publications.
Snapshots replace earlier state for that LiveKit participant; a 15-second
refresh and 45-second expiry cover missed leave/clear packets. Participant
disconnect and local unpublish prune immediately. Multiple devices of the
same Matrix account are deduplicated for display.

The room header resolves the resulting Matrix user IDs to room display names
and avatars. Up to three avatars are shown on a normal header (two in compact
or mobile); above that the indicator becomes one count button with a bounded,
scrollable viewer menu. The indicator is absent without a local share or
watchers. Older clients do not send this optional protocol, so the count is
not a server-authoritative subscriber tally.
