import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/single_instance_io.dart';

void main() {
  group('SingleInstance startup ownership', () {
    test(
      'does not allow the owner to continue before its socket bind completes',
      () async {
        final bindComplete = Completer<void>();
        var bindStarted = false;
        var claimCompleted = false;

        final claim = SingleInstance.debugClaimOrNotifyExistingForTesting(
          tryConnect: () async => false,
          tryClaimOwnership: () async => true,
          waitForOwner: () async => false,
          becomeOwner: () async {
            bindStarted = true;
            await bindComplete.future;
          },
          releaseOwnership: () async {},
        );
        claim.whenComplete(() {
          claimCompleted = true;
        });

        await Future<void>.delayed(Duration.zero);
        expect(bindStarted, isTrue);
        expect(claimCompleted, isFalse);

        bindComplete.complete();
        expect(await claim, isFalse);
      },
    );

    test(
      'joins the owner when another process claims startup ownership first',
      () async {
        var connectAttempts = 0;
        var bindAttempts = 0;

        final joinedExisting =
            await SingleInstance.debugClaimOrNotifyExistingForTesting(
              tryConnect: () async => connectAttempts++ > 0,
              tryClaimOwnership: () async => false,
              waitForOwner: () async => true,
              becomeOwner: () async {
                bindAttempts++;
              },
              releaseOwnership: () async {},
            );

        expect(joinedExisting, isTrue);
        expect(bindAttempts, 0);
        expect(connectAttempts, 1);
      },
    );

    test('claims ownership when the owner is gone by the time the wait '
        'ends', () async {
      // The reachable half of "the owner did not become ready". The lock is
      // released when its holder exits, and `becomeOwner` failing releases it
      // explicitly, so a wait that ends can mean there is no owner any more
      // rather than a slow one. Before the retry that ended in a StateError,
      // which is fatal at launch: the relaunch after a crashed startup could
      // not start.
      var claims = 0;
      var bindAttempts = 0;

      final joinedExisting =
          await SingleInstance.debugClaimOrNotifyExistingForTesting(
            tryConnect: () async => false,
            tryClaimOwnership: () async => claims++ > 0,
            waitForOwner: () async => false,
            becomeOwner: () async {
              bindAttempts++;
            },
            releaseOwnership: () async {},
          );

      expect(joinedExisting, isFalse, reason: 'this process is now the owner');
      expect(claims, 2);
      expect(bindAttempts, 1);
    });

    test('clears a dead socket before binding over it on the re-claim '
        'path', () async {
      // The owner that went away can have bound before it died. On Linux the
      // socket file outlives the process, and `waitForOwner` will not remove
      // it - deleting the socket of an owner that is merely slow would unbind
      // it. So without a connect between the second claim and the bind, the
      // file is still there when `bind` runs and startup dies on "Address
      // already in use". That connect is the one carrying stale-socket
      // removal, and it has to happen BEFORE the bind to be of any use.
      //
      // The whole sequence is recorded rather than counted. Counting proves a
      // step HAPPENED, never that it happened at the right moment, and here
      // the moment is the entire point: a connect that runs before the second
      // claim deletes a socket this process has not yet earned the right to
      // delete, and it satisfies every count this test could make.
      var claims = 0;
      final order = <String>[];

      final joinedExisting =
          await SingleInstance.debugClaimOrNotifyExistingForTesting(
            tryConnect: () async {
              order.add('connect');
              return false;
            },
            tryClaimOwnership: () async {
              order.add('claim');
              return claims++ > 0;
            },
            waitForOwner: () async {
              order.add('wait');
              return false;
            },
            becomeOwner: () async {
              order.add('bind');
            },
            releaseOwnership: () async {
              order.add('release');
            },
          );

      expect(joinedExisting, isFalse, reason: 'this process is now the owner');
      expect(
        order,
        ['connect', 'claim', 'wait', 'claim', 'connect', 'bind'],
        reason:
            'the second claim must come first - only holding the lock makes '
            'the socket safe to delete - and the connect it enables must run '
            'before the bind it is clearing the path for.',
      );
    });

    test('joins an owner that appears between the wait ending and the '
        'bind', () async {
      // The same extra connect answering true. The lock is held at that point,
      // so continuing to bind would put a second server on a live socket; and
      // exiting while still holding the lock would strand the next launch in
      // the wait. It has to release and report that it joined.
      //
      // Recorded rather than counted, for a sharper reason than on the bind
      // path: a connect that runs before the second claim makes this process
      // release a lock it never took. Every count below - two connects, no
      // bind, released true - is satisfied by that sequence, so only the
      // order distinguishes "released our own lock" from "released nothing".
      var claims = 0;
      var connects = 0;
      final order = <String>[];

      final joinedExisting =
          await SingleInstance.debugClaimOrNotifyExistingForTesting(
            tryConnect: () async {
              order.add('connect');
              return connects++ > 0;
            },
            tryClaimOwnership: () async {
              order.add('claim');
              return claims++ > 0;
            },
            waitForOwner: () async {
              order.add('wait');
              return false;
            },
            becomeOwner: () async {
              order.add('bind');
            },
            releaseOwnership: () async {
              order.add('release');
            },
          );

      expect(joinedExisting, isTrue, reason: 'the owner has been notified');
      expect(
        order,
        ['connect', 'claim', 'wait', 'claim', 'connect', 'release'],
        reason:
            'the release must follow the claim that took the lock. One '
            'notification at most, too: the first connect and the wait both '
            'returned false, and either returning true returns immediately.',
      );
    });

    test('does not continue when another owner cannot be reached', () async {
      await expectLater(
        SingleInstance.debugClaimOrNotifyExistingForTesting(
          tryConnect: () async => false,
          tryClaimOwnership: () async => false,
          waitForOwner: () async => false,
          becomeOwner: () async {},
          releaseOwnership: () async {},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('releases ownership if starting the IPC server fails', () async {
      var released = false;

      await expectLater(
        SingleInstance.debugClaimOrNotifyExistingForTesting(
          tryConnect: () async => false,
          tryClaimOwnership: () async => true,
          waitForOwner: () async => false,
          becomeOwner: () async => throw StateError('bind failed'),
          releaseOwnership: () async {
            released = true;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(released, isTrue);
    });
  });
}
