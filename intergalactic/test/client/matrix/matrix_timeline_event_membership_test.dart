import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_membership.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('MatrixTimelineEventMembership', () {
    test('classifies knock requests as visible invite-style events', () {
      final event = MatrixTimelineEventMembership(
        _membershipEvent(
          content: const {
            'membership': 'knock',
            'displayname': 'Rey',
          },
        ),
        client: _FakeMatrixClient(),
      );

      expect(event.isKnockEvent, isTrue);
      expect(event.isInviteEvent, isTrue);
      expect(event.icon, Icons.front_hand);
      expect(event.plainTextBody, 'Rey requested to join the room');
    });
  });
}

matrix.Event _membershipEvent({
  required Map<String, dynamic> content,
}) {
  return matrix.Event(
    content: content,
    type: matrix.EventTypes.RoomMember,
    eventId: r'$knock',
    senderId: '@rey:example.org',
    stateKey: '@rey:example.org',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(0),
    room: _FakeSdkRoom(),
  );
}

class _FakeMatrixClient implements MatrixClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  @override
  String get id => '!room:example.org';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
