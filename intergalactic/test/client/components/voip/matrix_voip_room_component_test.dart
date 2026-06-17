import 'package:flutter_test/flutter_test.dart';
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

    test('prunes Inter Galactic legacy memberships with long relative expiry',
        () {
      final event = _callMemberEvent({
        'application': 'm.call',
        'expires':
            MatrixVoipRoomComponent.legacyMembershipMaxAge.inMilliseconds * 10,
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
    });

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
}

StrippedStateEvent _callMemberEvent(Map<String, Object?> content) {
  return StrippedStateEvent(
    type: MatrixVoipRoomComponent.callMemberStateEvent,
    content: content,
    senderId: '@alice:example.org',
    stateKey: '_@alice:example.org_DEVICE_m.call',
  );
}
