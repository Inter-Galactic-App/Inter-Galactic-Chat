import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/voip_room/voip_room_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event_call.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';

/// A call room *is* the call, so "X started a call" and "X ended the call"
/// narrate what the user is already looking at. The chat beside a call is for
/// what people say to each other.
///
/// The scoping is the point of these tests. In a direct message the same lines
/// are useful history - a missed call is worth a record - so this must never
/// become a global rule. Owner decision, 2026-08-21.
///
/// Note what is NOT covered here, because it needs no code: the MatrixRTC
/// membership `org.matrix.msc3401.call.member`, which every participant
/// republishes every 25 seconds, has no case in the timeline-event switch in
/// `matrix_room.dart`. It is already an unknown event and already falls through
/// to `hidden`. It was never the visible noise.
void main() {
  late DemoClient client;

  setUp(() async {
    client = DemoClient.createOfflineDemo();
    await client.init(false);
  });

  tearDown(() async {
    await client.close();
  });

  test('a call event is hidden in a call room', () {
    final callRoom = client.getRoom(DemoClient.demoVoiceRoomId)!;
    expect(
      callRoom.getComponent<VoipRoomComponent>(),
      isNotNull,
      reason:
          'the premise of this test is that the demo voice room is a call '
          'room; if this fails the assertion below proves nothing',
    );

    expect(
      TimelineViewEntryState.eventToDisplayType(
        _FakeCallEvent(),
        room: callRoom,
      ),
      TimelineEventWidgetDisplayType.hidden,
    );
  });

  test('the same call event still shows in a room without a call', () {
    final textRoom = client.getRoom(DemoClient.demoLoungeRoomId)!;
    expect(
      textRoom.getComponent<VoipRoomComponent>(),
      isNull,
      reason: 'this test only means something if the lounge is not a call room',
    );

    expect(
      TimelineViewEntryState.eventToDisplayType(
        _FakeCallEvent(),
        room: textRoom,
      ),
      TimelineEventWidgetDisplayType.generic,
      reason:
          'hiding call events globally would delete missed-call history from '
          'direct messages, which the owner explicitly did not ask for',
    );
  });

  test('a direct message keeps its call history', () {
    final dm = client.getRoom(DemoClient.demoMiraDmRoomId)!;

    expect(
      TimelineViewEntryState.eventToDisplayType(_FakeCallEvent(), room: dm),
      TimelineEventWidgetDisplayType.generic,
    );
  });
}

/// `eventToDisplayType` only type-tests this branch, so a [Fake] is enough and
/// avoids standing up a real `MatrixClient` and matrix `Room` to reach a
/// constructor whose output would be discarded.
class _FakeCallEvent extends Fake implements MatrixTimelineEventCall {}
