import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_feature_related.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_reply.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _originalBody = 'the original message';
const String _originalSender = '@alice:example.org';
const String _secondOriginalBody = 'the other original message';
const String _secondOriginalSender = '@carol:example.org';

/// Everything [_FakeTimeline.tryGetEvent] can resolve without a round trip.
/// `$unfetched` is deliberately absent, so a reply pointing at it takes the
/// asynchronous `Room.getEvent` path instead.
const Map<String, _FakeOriginalEvent> _knownOriginals = {
  r'$original': _FakeOriginalEvent(),
  r'$second-original': _FakeOriginalEvent(
    eventId: r'$second-original',
    senderId: _secondOriginalSender,
    plainTextBody: _secondOriginalBody,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  Widget subject({required Timeline timeline, required int index}) {
    return MaterialApp(
      home: Scaffold(
        // The bubble layout renders the sender and body as plain Text widgets,
        // so the assertions below can name them. The guard under test sits at
        // the top of `build`, ahead of the bubble/non-bubble split, so it
        // covers both layouts.
        body: TimelineEventViewReply(
          timeline: timeline,
          index: index,
          bubbleMessages: true,
        ),
      ),
    );
  }

  // The first two tests deliberately use two separate mounts. They pin the
  // range guard, and a fresh mount is the path that reaches it in production.
  //
  // They used to have to: TimelineEventViewReply had no `didUpdateWidget` at
  // all, so re-pumping kept the first mount's state and would have asserted
  // nothing. It has one now, and the re-pump tests below are what pin it.
  testWidgets('an index that resolves renders the reply', (tester) async {
    final timeline = _FakeTimeline(events: [const _FakeReplyEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(find.text('Replying to $_originalSender'), findsOneWidget);
    expect(find.text(_originalBody), findsOneWidget);
  });

  testWidgets('an index past the end of the timeline renders nothing', (
    tester,
  ) async {
    // The index is the position the owning entry handed over, and it is only
    // accurate at that moment: TimelineViewEntry has no didUpdateWidget, so
    // after a removal it keeps its old index until the next update() corrects
    // it, and this row can be mounted in between. The unguarded
    // `events[index]` in getStateFromIndex threw RangeError from initState.
    //
    // The second assertion is the one that earns its keep. "No exception"
    // alone passes for an early return that leaves the null fields in place,
    // which renders "Replying to Loading / Unknown" - a reply that is not on
    // screen, claimed to be there.
    final timeline = _FakeTimeline(events: [const _FakeReplyEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('Replying to'),
      findsNothing,
      reason: 'an index with no event must render nothing, not a placeholder',
    );
  });

  testWidgets('a changed index repoints the reply at the new event', (
    tester,
  ) async {
    // The gap CodeRabbit found from one side and a PR 337 subagent from the
    // other. The owning TimelineEventViewMessage rebuilds this child with a
    // new index whenever its own loadEventState runs, and nothing here is
    // keyed, so the same State object is reused. Without didUpdateWidget the
    // reply body stayed pinned to the event resolved at initState - a reply
    // attributed to a message it does not belong to.
    //
    // The last two assertions are the ones that earn their keep: "the new
    // reply is shown" alone passes for a widget that happens to resolve
    // late, while "the old one is gone" only passes if the state was actually
    // re-resolved.
    final timeline = _FakeTimeline(
      events: [
        const _FakeReplyEvent(),
        const _FakeReplyEvent(
          eventId: r'$reply-2',
          relatedEventId: r'$second-original',
        ),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text('Replying to $_originalSender'), findsOneWidget);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Replying to $_secondOriginalSender'), findsOneWidget);
    expect(find.text(_secondOriginalBody), findsOneWidget);
    expect(
      find.text('Replying to $_originalSender'),
      findsNothing,
      reason: 'a new index must not keep the previous reply target',
    );
    expect(find.text(_originalBody), findsNothing);
  });

  testWidgets('an index that becomes valid again resolves the reply', (
    tester,
  ) async {
    // The recovery half. The range guard leaves indexResolved false, and
    // before didUpdateWidget existed it stayed false for the life of the
    // State: an entry corrected by update() got its index back, but this row
    // stayed blank until something remounted it.
    final timeline = _FakeTimeline(events: [const _FakeReplyEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();
    expect(find.textContaining('Replying to'), findsNothing);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Replying to $_originalSender'), findsOneWidget);
    expect(find.text(_originalBody), findsOneWidget);
  });

  testWidgets('a replacement at the SAME index repoints the reply', (
    tester,
  ) async {
    // The half the index comparison cannot see, and the one that fires in
    // production. `onEventRemoved` shrinks the list without calling
    // `update()`, so the rows below keep their old indexes; the next
    // `onRoomUpdated` then calls `update(i)` on every mounted row with the
    // index it already had. This row is therefore rebuilt with the same index
    // against a list in which a DIFFERENT event now sits at it.
    //
    // The index is identical on both pumps, so a didUpdateWidget comparing
    // only index and timeline skips the re-resolve and the row keeps naming
    // the previous reply target - under a message body that has already moved
    // on.
    final timeline = _FakeTimeline(
      events: [
        const _FakeReplyEvent(eventId: r'$reply-1'),
        const _FakeReplyEvent(
          eventId: r'$reply-2',
          relatedEventId: r'$second-original',
        ),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text('Replying to $_originalSender'), findsOneWidget);

    // The removal production performs, leaving $reply-2 at index 0.
    timeline.events.removeAt(0);
    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Replying to $_secondOriginalSender'),
      findsOneWidget,
      reason: 'the event at index 0 changed, so the reply target must follow',
    );
    expect(find.text(_secondOriginalBody), findsOneWidget);
    expect(
      find.text('Replying to $_originalSender'),
      findsNothing,
      reason: 'a replaced event must not keep the previous reply target',
    );
    expect(find.text(_originalBody), findsNothing);
  });

  testWidgets('an unchanged event does not restart an in-flight fetch', (
    tester,
  ) async {
    // The guard on the fix above, and the reason it compares the event rather
    // than the owning widget's `updateRevision`. That revision is bumped for
    // every mounted row on every room update, so re-resolving on it would
    // clear this row and re-issue Room.getEvent each time a message arrives:
    // a reply target outside the timeline dictionary would drop back to
    // "Replying to Loading" on every incoming message and, in a busy room,
    // never resolve at all.
    //
    // Rebuilding with everything unchanged is what a revision bump looks like
    // from in here. One fetch must still be the only fetch.
    final timeline = _FakeTimeline(
      events: [
        const _FakeReplyEvent(
          eventId: r'$reply-1',
          relatedEventId: r'$unfetched',
        ),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(timeline.fakeRoom.pendingEventFetches, hasLength(1));

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(
      timeline.fakeRoom.pendingEventFetches,
      hasLength(1),
      reason: 'a rebuild that changed nothing must not re-issue the fetch',
    );

    // And the fetch that was issued still lands, rather than being discarded
    // by a generation bump from a re-resolve that should not have happened.
    //
    // Both halves of what the completion writes are asserted, not just the
    // sender. This is the only test in this file that observes the RENDER of
    // the asynchronous branch: every other resolve here comes back through the
    // synchronous `tryGetEvent` path, and the one other test that completes a
    // fetch does so expecting it to be DISCARDED by the generation guard. So a
    // completion that set the sender and left `body` null - the row's own
    // "Unknown" placeholder, which looks nothing like a failure - would be
    // caught nowhere if this test checked the sender alone.
    timeline.fakeRoom.pendingEventFetches.first.complete(
      const _FakeOriginalEvent(),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Replying to $_originalSender'), findsOneWidget);
    expect(
      find.text(_originalBody),
      findsOneWidget,
      reason:
          'the fetch that landed must render the reply it resolved, not a '
          'sender line over a blank or stale body',
    );
    expect(
      find.text('Unknown'),
      findsNothing,
      reason: 'and the loading placeholder must be gone once it has landed',
    );
  });

  testWidgets('a fetch issued for the previous index cannot repaint the row', (
    tester,
  ) async {
    // Re-resolving on its own is not enough. A reply target that is not in
    // the timeline's dictionary is fetched through Room.getEvent, and that
    // future outlives the index that asked for it. `mounted` does not catch
    // it - the State is still mounted, it has just moved to another event -
    // and the late completion renders a sender and a body, so it looks
    // exactly like a successful resolve. Hence the generation counter.
    final timeline = _FakeTimeline(
      events: [
        const _FakeReplyEvent(
          eventId: r'$reply-1',
          relatedEventId: r'$unfetched',
        ),
        const _FakeReplyEvent(
          eventId: r'$reply-2',
          relatedEventId: r'$second-original',
        ),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(
      timeline.fakeRoom.pendingEventFetches,
      hasLength(1),
      reason: 'the unresolvable reply target must go out to Room.getEvent',
    );
    expect(find.text('Replying to Loading'), findsOneWidget);

    // The row moves to a different event while that fetch is still in flight.
    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();
    expect(find.text('Replying to $_secondOriginalSender'), findsOneWidget);

    // ...and only now does the fetch for the abandoned index land.
    timeline.fakeRoom.pendingEventFetches.first.complete(
      const _FakeOriginalEvent(),
    );
    // Not a pump count. One pump runs the `.then` microtask but the repaint it
    // asks for lands on the frame after, so with a single pump this test
    // passed with the generation guard removed - it was asserting on a frame
    // the stale value had not reached yet. Three pumps fixed that by encoding
    // the schedule measured at the time, which is the same defect one frame
    // further out: a stale repaint that needs a fourth frame would again be
    // asserted before it arrives.
    //
    // `pumpAndSettle` states the condition instead of the count - keep
    // pumping until nothing is scheduled - so the assertions run on the last
    // frame the stale completion could possibly reach. Safe here specifically:
    // this subtree is a `Scaffold` holding one `TimelineEventViewReply`, which
    // runs no animation and no periodic timer, and `_FakeTimeline` completes
    // `getEvent` only when a test tells it to. Nothing can keep scheduling
    // frames, which is the one way `pumpAndSettle` fails - it times out rather
    // than settling.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Replying to $_secondOriginalSender'),
      findsOneWidget,
      reason: 'the stale completion must not overwrite the current reply',
    );
    expect(
      find.text(_secondOriginalBody),
      findsOneWidget,
      reason:
          'the sender alone leaves the body unchecked, so a guard that '
          'discards the stale result by clearing the row - the same blank the '
          'range guard produces - passes every other assertion here',
    );
    expect(find.text('Replying to $_originalSender'), findsNothing);
    expect(find.text(_originalBody), findsNothing);
  });
}

class _FakeReplyEvent implements TimelineEvent, TimelineEventFeatureRelated {
  const _FakeReplyEvent({
    this.eventId = r'$reply',
    this.relatedEventId = r'$original',
  });

  @override
  final String eventId;

  @override
  final String? relatedEventId;

  @override
  String get senderId => '@bob:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 10);

  @override
  String get plainTextBody => 'a reply';

  @override
  EventRelationshipType? get relationshipType => EventRelationshipType.reply;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeOriginalEvent implements TimelineEvent {
  const _FakeOriginalEvent({
    this.eventId = r'$original',
    this.senderId = _originalSender,
    this.plainTextBody = _originalBody,
  });

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final String plainTextBody;

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 9);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required List<TimelineEvent> events}) {
    final fake = _FakeRoom(client: _FakeClient());
    fakeRoom = fake;
    room = fake;
    client = room.client;
    this.events = List<TimelineEvent>.of(events);
  }

  /// The same object as [room], typed so a test can drive its pending
  /// `getEvent` futures.
  late final _FakeRoom fakeRoom;

  /// The reply target is resolved through the events dictionary, which only
  /// the real insert path populates.
  @override
  TimelineEvent? tryGetEvent(String eventId) => _knownOriginals[eventId];

  @override
  bool get canLoadFuture => false;

  @override
  bool get canLoadHistory => false;

  @override
  bool get isLoadingFuture => false;

  @override
  bool get isLoadingHistory => false;

  @override
  Stream<void> get onLoadingStatusChanged => const Stream<void>.empty();

  @override
  Future<void> close() async {}

  @override
  bool canDeleteEvent(TimelineEvent event) => false;

  @override
  void deleteEvent(TimelineEvent event) {}

  @override
  Future<TimelineEvent?> fetchEventByIdInternal(String eventId) async => null;

  @override
  bool isEventRedacted(TimelineEvent event) => false;

  @override
  Future<void> loadMoreFuture() async {}

  @override
  Future<void> loadMoreHistory() async {}

  @override
  void markAsRead(TimelineEvent event) {}
}

class _FakeRoom implements Room {
  _FakeRoom({required this.client});

  @override
  final Client client;

  /// One entry per outstanding [getEvent], in call order. Held rather than
  /// completed so a test can decide when - and whether - a fetch lands.
  final List<Completer<TimelineEvent?>> pendingEventFetches =
      <Completer<TimelineEvent?>>[];

  @override
  Future<TimelineEvent?> getEvent(String eventId) {
    final completer = Completer<TimelineEvent?>();
    pendingEventFetches.add(completer);
    return completer.future;
  }

  @override
  String get identifier => '!room:example.org';

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  _FakeClient() : self = const _FakeProfile('@self:example.org');

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMember implements Member {
  _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get displayName => identifier;

  @override
  String get userName => identifier;

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => const Color(0xFF534CDD);
}
