import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/components/voip_room/livekit_room_teardown_barrier.dart';

void main() {
  setUp(LiveKitRoomTeardownBarrier.debugResetForTesting);
  tearDown(LiveKitRoomTeardownBarrier.debugResetForTesting);

  test('waits for the prior room disposal from the same client', () async {
    final ticket = LiveKitRoomTeardownBarrier.register('client-a');
    var joined = false;

    final wait =
        LiveKitRoomTeardownBarrier.waitForPending(
          clientKey: 'client-a',
          timeout: const Duration(seconds: 1),
        ).then((completed) {
          joined = completed;
        });

    await Future<void>.delayed(Duration.zero);
    expect(joined, isFalse);

    ticket.complete();
    await wait;

    expect(joined, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(LiveKitRoomTeardownBarrier.debugPendingClientCount, 0);
  });

  test('does not block an unrelated Matrix client', () async {
    final ticket = LiveKitRoomTeardownBarrier.register('client-a');

    final completed = await LiveKitRoomTeardownBarrier.waitForPending(
      clientKey: 'client-b',
      timeout: Duration.zero,
    );

    expect(completed, isTrue);
    ticket.complete();
  });

  test('reports a bounded timeout while disposal is still pending', () async {
    final ticket = LiveKitRoomTeardownBarrier.register('client-a');

    final completed = await LiveKitRoomTeardownBarrier.waitForPending(
      clientKey: 'client-a',
      timeout: Duration.zero,
    );

    expect(completed, isFalse);
    ticket.complete();
  });

  test(
    'waits for a teardown registered while an earlier one is awaited',
    () async {
      final first = LiveKitRoomTeardownBarrier.register('client-a');
      var completed = false;
      final wait = LiveKitRoomTeardownBarrier.waitForPending(
        clientKey: 'client-a',
        timeout: const Duration(seconds: 1),
      ).then((value) => completed = value);

      await Future<void>.delayed(Duration.zero);
      final second = LiveKitRoomTeardownBarrier.register('client-a');
      first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      second.complete();
      await wait;
      expect(completed, isTrue);
    },
  );

  test('uses one timeout budget across late teardown registrations', () async {
    var now = DateTime.utc(2026, 8, 6);
    final first = LiveKitRoomTeardownBarrier.register('client-a');
    final wait = LiveKitRoomTeardownBarrier.waitForPending(
      clientKey: 'client-a',
      timeout: const Duration(seconds: 10),
      now: () => now,
    );

    await Future<void>.delayed(Duration.zero);
    final second = LiveKitRoomTeardownBarrier.register('client-a');
    first.complete();
    now = now.add(const Duration(seconds: 10));

    expect(await wait, isFalse);
    second.complete();
  });

  test('quarantines a client after native teardown failure', () async {
    final ticket = LiveKitRoomTeardownBarrier.register('client-a');

    ticket.fail();
    await Future<void>.delayed(Duration.zero);

    expect(
      await LiveKitRoomTeardownBarrier.waitForPending(
        clientKey: 'client-a',
        timeout: Duration.zero,
      ),
      isFalse,
    );
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);
  });

  // The quarantine used to be permanent for the process: `_failedClients` was
  // a `static final Set<String>` keyed on the *Matrix account*, written only by
  // `fail()` and erased only by `debugResetForTesting()`. One slow teardown in
  // one room therefore blocked calling in every room until the app was
  // restarted, and the test that stood here asserted that permanence as
  // intended behaviour. These four tests replace it: the quarantine still
  // fires, but every route out of it is now exercised.

  test('a later successful teardown lifts the quarantine', () async {
    final failed = LiveKitRoomTeardownBarrier.register('client-a');
    failed.fail();
    await Future<void>.delayed(Duration.zero);
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

    final recovered = LiveKitRoomTeardownBarrier.register('client-a');
    expect(
      LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'),
      isFalse,
      reason: 'registering a fresh teardown supersedes the failed one',
    );

    recovered.complete();
    await Future<void>.delayed(Duration.zero);

    expect(
      await LiveKitRoomTeardownBarrier.waitForPending(
        clientKey: 'client-a',
        timeout: Duration.zero,
      ),
      isTrue,
    );
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isFalse);
  });

  test('a late dispose that finishes after its timeout clears the '
      'quarantine it set', () async {
    // `_disposeNativeLiveKitRoomAfterDisconnect` bounds the native dispose at
    // two seconds and calls `fail()` when that bound is exceeded, but the
    // underlying `Room.dispose()` keeps running and calls `complete()` when it
    // finally lands. A slow success must not read as a permanent failure.
    final ticket = LiveKitRoomTeardownBarrier.register('client-a');

    ticket.fail();
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

    ticket.complete();
    await Future<void>.delayed(Duration.zero);

    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isFalse);
    expect(
      await LiveKitRoomTeardownBarrier.waitForPending(
        clientKey: 'client-a',
        timeout: Duration.zero,
      ),
      isTrue,
    );
  });

  test('the quarantine expires on its own so no restart is required', () async {
    var now = DateTime.utc(2026, 8, 8);
    LiveKitRoomTeardownBarrier.debugSetClockForTesting(() => now);

    final ticket = LiveKitRoomTeardownBarrier.register('client-a');
    ticket.fail();
    await Future<void>.delayed(Duration.zero);
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

    now = now.add(
      LiveKitRoomTeardownBarrier.failedTeardownQuarantine -
          const Duration(milliseconds: 1),
    );
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

    now = now.add(const Duration(milliseconds: 1));
    expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isFalse);
    expect(
      await LiveKitRoomTeardownBarrier.waitForPending(
        clientKey: 'client-a',
        timeout: Duration.zero,
      ),
      isTrue,
    );
  });

  test(
    'a failed teardown does not quarantine another Matrix account',
    () async {
      final ticket = LiveKitRoomTeardownBarrier.register('client-a');
      ticket.fail();
      await Future<void>.delayed(Duration.zero);

      expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-b'), isFalse);
      expect(
        await LiveKitRoomTeardownBarrier.waitForPending(
          clientKey: 'client-b',
          timeout: Duration.zero,
        ),
        isTrue,
      );
    },
  );

  test('reports how long a quarantine still has to run', () async {
    var now = DateTime.utc(2026, 8, 8);
    LiveKitRoomTeardownBarrier.debugSetClockForTesting(() => now);

    expect(LiveKitRoomTeardownBarrier.quarantineRemaining('client-a'), isNull);

    LiveKitRoomTeardownBarrier.register('client-a').fail();
    expect(
      LiveKitRoomTeardownBarrier.quarantineRemaining('client-a'),
      LiveKitRoomTeardownBarrier.failedTeardownQuarantine,
    );

    now = now.add(const Duration(seconds: 10));
    expect(
      LiveKitRoomTeardownBarrier.quarantineRemaining('client-a'),
      LiveKitRoomTeardownBarrier.failedTeardownQuarantine -
          const Duration(seconds: 10),
    );
  });

  test('waits for every pending teardown from one client', () async {
    final first = LiveKitRoomTeardownBarrier.register('client-a');
    final second = LiveKitRoomTeardownBarrier.register('client-a');
    var completed = false;
    final wait =
        LiveKitRoomTeardownBarrier.waitForPending(
          clientKey: 'client-a',
          timeout: const Duration(seconds: 1),
        ).then((value) {
          completed = value;
        });

    second.complete();
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);

    first.complete();
    await wait;
    expect(completed, isTrue);
  });

  test(
    'a late completion does not clear a quarantine another ticket set',
    () async {
      // Two teardowns overlap for the same client - the BUG-268 shape. The
      // first times out, `fail()`s, then finally lands and `complete()`s. Its
      // completion must clear only the quarantine IT set. Without the
      // `identical(failure.owner, owner)` ownership check in `_clearFailure`,
      // the stale ticket lifts the newer ticket's quarantine and the next join
      // proceeds against a room that is still being released.
      final stale = LiveKitRoomTeardownBarrier.register('client-a');
      stale.fail();
      await Future<void>.delayed(Duration.zero);
      expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

      // A fresh teardown supersedes the stale failure and then fails in turn,
      // so the quarantine now belongs to `fresh`.
      final fresh = LiveKitRoomTeardownBarrier.register('client-a');
      expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isFalse);
      fresh.fail();
      await Future<void>.delayed(Duration.zero);
      expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isTrue);

      stale.complete();
      await Future<void>.delayed(Duration.zero);

      expect(
        LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'),
        isTrue,
        reason:
            'the stale ticket owns no quarantine, so its late completion must '
            'leave the newer one standing',
      );

      // The owner clearing its own quarantine still works.
      fresh.complete();
      await Future<void>.delayed(Duration.zero);
      expect(LiveKitRoomTeardownBarrier.hasFailedTeardown('client-a'), isFalse);
    },
  );
}
