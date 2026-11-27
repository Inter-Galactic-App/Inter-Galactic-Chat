// BUG-317: opening a conversation from the Inbox on mobile selected the right
// room but never revealed the timeline panel, leaving the user on the
// space/room sidebar they had tapped from.
//
// `EventBus.focusTimeline` is the only thing that reveals the mobile timeline
// panel, so this asserts the emit, not the panel geometry. That distinction
// matters: a test that only asserted "a focusTimeline emit reveals the panel"
// would have passed against the defect, because the defect was the missing
// emit and the listener was always correct.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/utils/event_bus.dart';

import 'main_page_test_harness.dart';

InboxEventSnapshot _event(String eventId) => InboxEventSnapshot(
  eventId: eventId,
  timestamp: DateTime(2026, 9, 2),
  senderId: '@someone:example.org',
  plainTextBody: 'a message worth opening',
  isDirectMention: false,
);

InboxRoomSnapshot _snapshot({
  required String clientIdentifier,
  required String roomId,
  required InboxEventSnapshot event,
}) => InboxRoomSnapshot(
  clientIdentifier: clientIdentifier,
  roomId: roomId,
  roomName: roomId,
  unreadCount: 1,
  isSidebarEligible: true,
  readTargetEventId: event.eventId,
  newestUnreadEvent: event,
);

void main() {
  late List<void> focusEvents;
  late StreamSubscription<void> focusSubscription;

  setUp(() async {
    await initMainPageHarnessGlobals();
    focusEvents = <void>[];
    focusSubscription = EventBus.focusTimeline.stream.listen(focusEvents.add);
  });

  tearDown(() async {
    await focusSubscription.cancel();
    await resetMainPageHarnessGlobals();
  });

  testWidgets('opening an Inbox row surfaces the destination timeline', (
    tester,
  ) async {
    final client = FakeHarnessClient(
      identifier: 'client-a',
      rooms: [FakeHarnessRoom(identifier: 'room-1', displayName: 'Room One')],
    );
    addTearDown(client.dispose);

    final harness = await pumpMainPage(tester, clients: [client]);

    // No stand-in jump listener is registered here on purpose. Selecting the
    // room mounts the real Chat, which registers its own - so `opened: true`
    // below is evidence that the real destination received the jump, not that
    // the test answered its own question.
    final event = _event(r'$event-1');
    final opened = await harness.openInboxSnapshotAndSettle(
      _snapshot(clientIdentifier: 'client-a', roomId: 'room-1', event: event),
      event,
    );

    expect(opened, isTrue, reason: 'the room and the jump both resolved');
    expect(
      harness.state.currentRoom?.identifier,
      'room-1',
      reason: 'the right room was selected',
    );
    expect(
      focusEvents,
      isNotEmpty,
      reason:
          'BUG-317: the timeline panel was never revealed, so the user '
          'was left on the space/room sidebar',
    );
  });

  testWidgets('opening a row from another account surfaces it too', (
    tester,
  ) async {
    // The other-account path switches the active client before selecting, and
    // that switch is where an open can be superseded partway through.
    final clientA = FakeHarnessClient(
      identifier: 'client-a',
      rooms: [FakeHarnessRoom(identifier: 'room-1', displayName: 'Room One')],
    );
    final clientB = FakeHarnessClient(
      identifier: 'client-b',
      rooms: [FakeHarnessRoom(identifier: 'room-2', displayName: 'Room Two')],
    );
    addTearDown(clientA.dispose);
    addTearDown(clientB.dispose);

    final harness = await pumpMainPage(tester, clients: [clientA, clientB]);

    final event = _event(r'$event-2');
    final opened = await harness.openInboxSnapshotAndSettle(
      _snapshot(clientIdentifier: 'client-b', roomId: 'room-2', event: event),
      event,
    );

    expect(opened, isTrue);
    expect(harness.state.currentRoom?.identifier, 'room-2');
    expect(harness.state.filterClient?.identifier, 'client-b');
    expect(focusEvents, isNotEmpty);
  });

  testWidgets('an unknown room is refused without surfacing anything', (
    tester,
  ) async {
    final client = FakeHarnessClient(identifier: 'client-a');
    addTearDown(client.dispose);

    final harness = await pumpMainPage(tester, clients: [client]);

    final event = _event(r'$event-1');
    final opened = await harness.openInboxSnapshotAndSettle(
      _snapshot(
        clientIdentifier: 'client-a',
        roomId: 'room-that-went-away',
        event: event,
      ),
      event,
    );

    expect(opened, isFalse);
    expect(harness.state.currentRoom, isNull);
    expect(focusEvents, isEmpty);
  });
}
