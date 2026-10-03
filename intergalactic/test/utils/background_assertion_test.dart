import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/background_assertion.dart';

/// WHAT WOULD MAKE THESE WRONG, stated first: the thing being guarded is a
/// wait that never ends, and a test that only checks the happy path cannot see
/// it. So every case below drives a host that answers LATE or not at all, and
/// asserts on when the caller was let go - which is why they run under
/// `fakeAsync` rather than real timers. A test that awaited these futures
/// directly would hang exactly as the production path did.
///
/// Why it matters: both calls sit on the suspension path inside
/// `DatabaseReleaseTrigger`'s serialised chain - `begin` before the sweep,
/// `end` in its `finally`. A host that never answers stops that chain for
/// good, so the resume queued behind it never runs, sync stays stopped, and
/// every waiter on `whenEstablished` blocks for the life of the process.
void main() {
  test('a responsive host is still granted immediately', () {
    fakeAsync((async) {
      final host = _RecordingHost(beginDelay: Duration.zero);
      BackgroundAssertionHandle? handle;
      unawaited(
        BackgroundAssertion.begin('n', host: host).then((h) => handle = h),
      );

      // `Future.delayed(Duration.zero)` is still a timer, so flushing
      // microtasks alone would not resolve it.
      async.elapse(_tick);
      expect(handle?.granted, isTrue);
      expect(handle?.token, 'token');
    });
  });

  test('an unresponsive host yields an ungranted handle rather than a wait '
      'with no end', () {
    fakeAsync((async) {
      final host = _RecordingHost(beginDelay: const Duration(days: 1));
      BackgroundAssertionHandle? handle;
      unawaited(
        BackgroundAssertion.begin('n', host: host).then((h) => handle = h),
      );

      async.elapse(BackgroundAssertion.hostTimeout - _tick);
      expect(handle, isNull, reason: 'inside the budget it must keep waiting');

      async.elapse(_tick * 2);
      expect(handle, isNotNull, reason: 'the caller has to be let go');
      expect(handle!.granted, isFalse);

      // Ending an ungranted handle is a no-op, so the suspension path's
      // `finally` cannot hang on it either.
      var ended = false;
      unawaited(handle!.end().then((_) => ended = true));
      async.flushMicrotasks();
      expect(ended, isTrue);
      expect(host.ended, isEmpty);
    });
  });

  test('a token that arrives after the timeout is handed back', () {
    fakeAsync((async) {
      // Walking away is not enough on its own. The handle we returned holds no
      // token, so nothing else would ever end this one, and iOS kills the app
      // when an unended beginBackgroundTask expires - a wedge traded for a
      // termination is not an improvement.
      // Stated relative to the budget, not in seconds. The literals this used
      // to carry - a 5s host answered by two 3s elapses - only worked because
      // `hostTimeout` happened to be shorter than 3s. Raise it to 4s and the
      // first elapse lands INSIDE the budget: `handle` is still null, and the
      // test fails on a null check with nothing about the timeout having
      // regressed. The relationship the case needs is the whole of it - the
      // host answers after the budget, and the test looks once on each side.
      final beginDelay = BackgroundAssertion.hostTimeout * 2;
      final host = _RecordingHost(beginDelay: beginDelay);
      BackgroundAssertionHandle? handle;
      unawaited(
        BackgroundAssertion.begin('n', host: host).then((h) => handle = h),
      );

      async.elapse(BackgroundAssertion.hostTimeout + _tick);
      expect(handle!.granted, isFalse);
      expect(host.ended, isEmpty, reason: 'the host has not answered yet');

      async.elapse(beginDelay - BackgroundAssertion.hostTimeout);
      expect(host.ended, [
        'token',
      ], reason: 'the late token must not be left held');
    });
  });

  test('ending is bounded too, and reports done rather than throwing', () {
    fakeAsync((async) {
      final host = _RecordingHost(endDelay: const Duration(days: 1));
      BackgroundAssertionHandle? handle;
      unawaited(
        BackgroundAssertion.begin('n', host: host).then((h) => handle = h),
      );
      async.elapse(_tick);
      expect(handle!.granted, isTrue);

      Object? error;
      var ended = false;
      unawaited(
        handle!
            .end()
            .then<void>((_) {
              ended = true;
            })
            .catchError((Object e) {
              error = e;
            }),
      );

      async.elapse(BackgroundAssertion.hostTimeout - _tick);
      expect(ended, isFalse);

      async.elapse(_tick * 2);
      expect(ended, isTrue, reason: 'the sweep\'s finally must complete');
      expect(error, isNull, reason: 'this class never throws');
    });
  });
}

const _tick = Duration(milliseconds: 1);

class _RecordingHost implements BackgroundAssertionHost {
  _RecordingHost({
    this.beginDelay = Duration.zero,
    this.endDelay = Duration.zero,
  });

  final Duration beginDelay;
  final Duration endDelay;
  final List<String> ended = [];

  @override
  Future<String?> begin(String name) =>
      Future<String?>.delayed(beginDelay, () => 'token');

  @override
  Future<void> end(String token) =>
      Future<void>.delayed(endDelay, () => ended.add(token));
}
