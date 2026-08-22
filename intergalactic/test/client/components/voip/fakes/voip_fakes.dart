// Shared deterministic fakes for driving `MatrixLivekitVoipSession` and
// `MatrixVoipRoomComponent` directly, instead of through the free-function
// `debug*ForTesting` shims.
//
// Import this barrel rather than the individual files.
//
// Design rules every fake here follows:
//
// * State that the real objects store independently is stored independently
//   here. Nothing is derived from something else "because it is usually the
//   same" - that is precisely what made the pre-existing hand-rolled fakes
//   unable to express the states the defects live in.
// * Anything not modelled routes to `noSuchMethod` and throws. A fake that
//   returns a plausible default for an unmodelled member lets a test pass
//   while observing nothing.
// * Operations are recorded so a test can assert what the session asked the
//   SDK to do, not only what state it ended in.

export 'fake_call_matrix_room.dart';
export 'fake_livekit_participants.dart';
export 'fake_livekit_publications.dart';
export 'fake_livekit_room.dart';
export 'fake_livekit_tracks.dart';
