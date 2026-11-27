import 'dart:async';

import 'package:intergalactic/debug/log.dart';

/// How long closing a client waits for its calls to hang up before it closes
/// anyway.
///
/// Client close runs during account removal and app shutdown. On iOS a
/// database still held when the app suspends is grounds for the system to kill
/// the app, so a hang-up that waits on a LiveKit room that is already gone
/// would turn a leaked call into a hung close at the worst possible moment.
/// Leaking the call is the lesser failure, so the wait is capped.
///
/// A healthy hang-up finishes well inside this. It matches the per-step bound
/// the LiveKit session already applies to each of its own teardown steps, so a
/// close is never held longer than any one of those steps could hold it.
const Duration clientCloseHangUpBound = Duration(seconds: 5);

/// Runs every hang-up in [hangUps] at once and returns when they have all
/// finished, or when [bound] has elapsed - whichever comes first.
///
/// Concurrent rather than one after another so the wait is set by the slowest
/// call, not by the sum of them. Each hang-up's failure is logged and
/// contained: one call that throws must not stop the others being ended, and a
/// close that is already under way has nothing useful to do with the error.
///
/// A hang-up still running at [bound] is abandoned, not cancelled - Dart cannot
/// cancel a future - so it may yet finish, or fail, after the close. The
/// per-call error handler above is attached before the wait starts, so a
/// failure that arrives late is still logged rather than surfacing as an
/// unhandled error.
Future<void> hangUpBeforeClientClose(
  Iterable<Future<void> Function()> hangUps, {
  required String context,
  required Duration bound,
}) async {
  final pending = <Future<void>>[
    for (final hangUp in hangUps)
      Future<void>.sync(hangUp).catchError((Object error, StackTrace trace) {
        Log.onError(
          error,
          trace,
          content:
              'A call failed to hang up while its client closed ($context)',
        );
      }),
  ];
  if (pending.isEmpty) {
    return;
  }

  try {
    await Future.wait(pending).timeout(bound);
  } on TimeoutException {
    Log.w(
      'Closing without waiting further for ${pending.length} call hang-up(s) '
      'after ${bound.inMilliseconds} ms ($context). The call may outlive its '
      'client; a hung close is the worse failure.',
    );
  }
}
