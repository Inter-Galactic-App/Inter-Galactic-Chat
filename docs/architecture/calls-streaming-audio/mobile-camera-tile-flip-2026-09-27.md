# Mobile call-room camera tile flip

## Behavior

- Double-tapping the visible local camera tile in an Android/iOS call room
  switches the currently published camera track between front and back.
- Remote tiles, screen shares, hidden or inactive camera tiles, desktop layouts,
  and non-LiveKit sessions do not receive the gesture. A single tap keeps its
  existing tile focus/reveal behavior.
- The session serializes the switch with camera enable/disable operations and
  uses LiveKit `LocalVideoTrack.setCameraPosition`, retaining the publication.
  The call surface drops another flip while one is in progress and reports a
  failed switch through the existing call-control error UI.
- Voice & Video camera settings and capture parameters are unchanged.
