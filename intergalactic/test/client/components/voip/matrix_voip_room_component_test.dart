import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_livekit_backend.dart';
import 'package:intergalactic/client/matrix/components/voip_room/matrix_voip_room_component.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:matrix/matrix.dart';

void main() {
  group('MatrixVoipRoomComponent membership expiry', () {
    test('keeps untagged legacy memberships visible', () {
      final event = _callMemberEvent({
        'application': 'm.call',
        'expires':
            MatrixVoipRoomComponent.legacyMembershipMaxAge.inMilliseconds * 10,
        MatrixVoipRoomComponent.callMembershipsKey: [
          {
            'application': 'm.call',
            'device_id': 'DEVICE',
            'membershipID': 'DEVICE',
          },
        ],
      });

      expect(MatrixVoipRoomComponent.isCallMembershipActive(event), isTrue);
    });

    test(
      'prunes Inter Galactic legacy memberships with long relative expiry',
      () {
        final event = _callMemberEvent({
          'application': 'm.call',
          'expires':
              MatrixVoipRoomComponent.legacyMembershipMaxAge.inMilliseconds *
              10,
          MatrixVoipRoomComponent.callClientInfoKey: {
            'app': BuildConfig.app,
            'version': '0.6.4',
          },
          MatrixVoipRoomComponent.callMembershipsKey: [
            {
              'application': 'm.call',
              'device_id': 'DEVICE',
              'membershipID': 'DEVICE',
            },
          ],
        });

        expect(MatrixVoipRoomComponent.isCallMembershipActive(event), isFalse);
      },
    );

    test('uses absolute membership expiry when present', () {
      const now = 1000;
      final event = _callMemberEvent({
        'application': 'm.call',
        'expires':
            MatrixVoipRoomComponent.legacyMembershipMaxAge.inMilliseconds * 10,
        MatrixVoipRoomComponent.callMembershipsKey: [
          {
            'application': 'm.call',
            'device_id': 'DEVICE',
            'membershipID': 'DEVICE',
            MatrixVoipRoomComponent.callMembershipExpiresTsKey: now + 1000,
          },
        ],
      });

      expect(
        MatrixVoipRoomComponent.isCallMembershipActive(event, nowMs: now),
        isTrue,
      );
    });
  });

  group('MatrixVoipRoomComponent session connection lifecycle', () {
    test('ignores ended state from a replaced session', () async {
      final component = MatrixVoipRoomComponent(
        _FakeMatrixClient(),
        _FakeMatrixRoom(),
      );
      final oldSession = _FakeVoipSession('old-session');
      final replacementSession = _FakeVoipSession('replacement-session');

      component.currentSession = replacementSession;
      component.onConnectionStateChangedForSession(oldSession, VoipState.ended);

      expect(component.currentSession, same(replacementSession));

      await component.dispose();
    });

    test('refuses to hand back a session that is leaving', () async {
      final component = MatrixVoipRoomComponent(
        _FakeMatrixClient(),
        _FakeMatrixRoom(),
      );
      final leavingSession = _FakeVoipSession(
        'leaving-session',
        state: VoipState.leaving,
      );
      component.currentSession = leavingSession;

      // The guard could previously only ask `state != ended`, which is true for
      // the whole teardown window, so the caller was handed a session whose
      // LiveKit room was already being released - a call it could neither use
      // nor leave.
      await expectLater(
        component.joinCall(),
        throwsA(isA<MatrixLivekitCallJoinSessionLeavingException>()),
      );
      expect(component.currentSession, same(leavingSession));

      await component.dispose();
    });

    test('still returns a session that is genuinely active', () async {
      final component = MatrixVoipRoomComponent(
        _FakeMatrixClient(),
        _FakeMatrixRoom(),
      );
      final activeSession = _FakeVoipSession(
        'active-session',
        state: VoipState.connected,
      );
      component.currentSession = activeSession;

      await expectLater(component.joinCall(), completion(same(activeSession)));

      await component.dispose();
    });

    test(
      'recovers session connection subscription cancellation failures',
      () async {
        final subscription = _FailingCancelSubscription();

        await expectLater(
          debugCancelMatrixVoipRoomSessionConnectionSubscriptionForTesting(
            subscription,
          ),
          completes,
        );

        expect(subscription.cancelAttempts, 1);
      },
    );
  });
}

StrippedStateEvent _callMemberEvent(Map<String, Object?> content) {
  return StrippedStateEvent(
    type: MatrixVoipRoomComponent.callMemberStateEvent,
    content: content,
    senderId: '@alice:example.org',
    stateKey: '_@alice:example.org_DEVICE_m.call',
  );
}

class _FakeVoipSession implements VoipSession {
  _FakeVoipSession(this.sessionId, {this.state = VoipState.connected});

  @override
  final String sessionId;

  @override
  final VoipState state;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingCancelSubscription implements StreamSubscription<VoipState> {
  int cancelAttempts = 0;

  @override
  Future<void> cancel() {
    cancelAttempts++;
    return Future<void>.error(StateError('connection cancel failed'));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixRoom implements MatrixRoom {
  /// Only the join-rejection log reads this, and it hashes it before writing.
  @override
  String get identifier => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
