import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/utils/background_assertion.dart';

/// WHAT WOULD MAKE THIS WRONG, stated first: the guarded property is that a
/// future COMPLETES, and a host whose `end` answers - at any delay - cannot
/// tell a bounded wait from an unbounded one, because both complete. So the
/// host below never answers `end` at all, and the assertion is on when the
/// cleanup was let go. Under real timers an unbounded wait would hang the
/// runner rather than fail it, which is why this runs under `fakeAsync`.
///
/// Why it matters: `_endLateToken` is the path taken when `begin` misses
/// [BackgroundAssertion.hostTimeout]. The caller has already been let go with
/// an ungranted handle, so the cleanup is `unawaited` and nothing else in the
/// process observes it. An unbounded wait there retains the cleanup - and the
/// host and token it closes over - for the life of the process, once for every
/// timed-out acquisition, on exactly the wedged-platform-thread condition that
/// produced the timeout in the first place.
///
/// `background_assertion_test.dart` covers `begin` and the handle's `end`.
/// This file is separate only because it is the one case that needs a test
/// seam into the private late-token path.
void main() {
  test('the late-token cleanup is bounded when the host never answers', () {
    fakeAsync((async) {
      final host = _WedgedEndHost();
      var cleanedUp = false;

      unawaited(
        BackgroundAssertion.debugEndLateTokenForTesting(
          host,
          Future<String?>.value('token'),
        ).then((_) => cleanedUp = true),
      );

      async.elapse(BackgroundAssertion.hostTimeout - _tick);
      expect(
        host.endCalls,
        ['token'],
        reason:
            'the end must actually have been issued, or the wait being '
            'bounded is being asserted about a call that never happened.',
      );
      expect(cleanedUp, isFalse, reason: 'inside the budget it keeps waiting');

      async.elapse(_tick * 2);
      expect(
        cleanedUp,
        isTrue,
        reason:
            'a host that never answers must not retain the cleanup for the '
            'life of the process.',
      );
    });
  });

  test('a host that answers late still ends the token, and only once', () {
    fakeAsync((async) {
      // The bound must not have turned the cleanup into a no-op: the reason
      // this path exists at all is that iOS kills the app when an unended
      // `beginBackgroundTask` expires.
      // Every duration here is stated relative to the budget, and the elapses
      // are stated relative to those durations. The literals this used to
      // carry - a 5s begin answered by a 4s and a 3s elapse - only worked
      // because `hostTimeout` happened to be 2s: the end completes at
      // `beginDelay + endDelay`, which is `5s + hostTimeout - _tick`, so any
      // budget above 2s pushed it past the fixed 7s the test looked at and
      // failed on `completedEnds` with nothing about the bound having
      // regressed. Deriving `endDelay` alone, as round 3 did, is not enough
      // while the elapses stay fixed - it is the pair that has to move.
      //
      // `endDelay` is strictly inside the budget, so an `end` that answers is
      // not racing the bound: a host answering at exactly [hostTimeout] would
      // make this pass or fail on tie-breaking rather than on behaviour.
      final endDelay = BackgroundAssertion.hostTimeout - _tick;
      // Strictly outside it, so the token really is a late one.
      final beginDelay = BackgroundAssertion.hostTimeout * 2;
      final host = _WedgedEndHost(endDelay: endDelay);
      var cleanedUp = false;

      unawaited(
        BackgroundAssertion.debugEndLateTokenForTesting(
          host,
          Future<String?>.delayed(beginDelay, () => 'token'),
        ).then((_) => cleanedUp = true),
      );

      async.elapse(beginDelay - _tick);
      expect(host.endCalls, isEmpty, reason: 'the host has not answered begin');

      // Past the begin, and then past the end it issues.
      async.elapse(_tick * 2 + endDelay);
      expect(host.endCalls, ['token'], reason: 'the end must still be issued');
      expect(
        host.completedEnds,
        ['token'],
        reason:
            'the bound must not have turned a host that does answer into an '
            'abandoned end - an unended assertion is what kills the app.',
      );
      expect(cleanedUp, isTrue);
    });
  });

  test('nothing is ended when the late begin resolves to no token', () {
    fakeAsync((async) {
      final host = _WedgedEndHost();
      var cleanedUp = false;

      unawaited(
        BackgroundAssertion.debugEndLateTokenForTesting(
          host,
          Future<String?>.value(null),
        ).then((_) => cleanedUp = true),
      );

      async.flushMicrotasks();
      expect(cleanedUp, isTrue);
      expect(host.endCalls, isEmpty);
    });
  });
}

const _tick = Duration(milliseconds: 1);

/// A host whose `end` never answers by default - no timer, no completion - so
/// the only thing that can release a waiter on it is a bound in the code under
/// test.
class _WedgedEndHost implements BackgroundAssertionHost {
  _WedgedEndHost({this.endDelay});

  /// When null, `end` returns a future that is never completed.
  final Duration? endDelay;
  final List<String> endCalls = [];
  final List<String> completedEnds = [];

  @override
  Future<String?> begin(String name) async => 'token';

  @override
  Future<void> end(String token) {
    endCalls.add(token);
    final delay = endDelay;
    if (delay == null) {
      return Completer<void>().future;
    }
    return Future<void>.delayed(delay, () => completedEnds.add(token));
  }
}
