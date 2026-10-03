import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/components/threads/thread_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/atoms/thread_reply_footer.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_thread.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const String _replyBody = 'the first thread reply';
const String _replySender = '@alice:example.org';
const String _secondReplyBody = 'the other thread reply';
const String _secondReplySender = '@carol:example.org';

/// Keyed by the root event's id, so a root whose index this row is given
/// resolves to its own reply. `$root-no-reply` is deliberately absent: that
/// is the "event is on screen, its first reply is not known yet" case, which
/// renders the footer with the Unknown Sender placeholder.
const Map<String, _FakeThreadReplyEvent> _repliesByRoot = {
  r'$root': _FakeThreadReplyEvent(),
  r'$root-2': _FakeThreadReplyEvent(
    eventId: r'$thread-reply-2',
    senderId: _secondReplySender,
    body: _secondReplyBody,
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The sender name is rendered as text only under `if (Layout.desktop)`
  // (thread_reply_footer.dart:91), and these tests run under the mobile
  // layout override below. It still reaches the avatar's placeholder on every
  // layout, so that is where the sender half of the state is asserted - a
  // `find.text` on it would pass vacuously here.
  Finder senderPlaceholder(String name) => find.byWidgetPredicate(
    (widget) => widget is Avatar && widget.placeholderText == name,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject({required Timeline timeline, required int index}) {
    return MaterialApp(
      // The footer renders through tiamat atoms, which read ThemeSettings off
      // the theme.
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewThread(
          initialIndex: index,
          timeline: timeline,
          component: _FakeThreadsComponent(),
        ),
      ),
    );
  }

  // The first two tests deliberately use two separate mounts. They pin the
  // range guard, and a fresh mount is the path that reaches it in production.
  //
  // They used to have to: TimelineEventViewThread had no `didUpdateWidget` at
  // all, so re-pumping kept the first mount's state and would have asserted
  // nothing. It has one now, and the re-pump tests below are what pin it.
  testWidgets('an index that resolves renders the thread footer', (
    tester,
  ) async {
    final timeline = _FakeTimeline(events: [const _FakeThreadRootEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(find.byType(ThreadReplyFooter), findsOneWidget);
    expect(find.text(_replyBody), findsOneWidget);
  });

  testWidgets('an index past the end of the timeline renders no footer', (
    tester,
  ) async {
    // getStateFromIndex read `events[index]` unguarded, and the index is only
    // accurate at the moment the owning entry handed it over: TimelineViewEntry
    // has no didUpdateWidget, so after a removal it keeps its old index until
    // the next update() corrects it, and this row can be mounted in between.
    //
    // "Renders no footer" rather than "does not throw": this footer names a
    // thread on a specific message and opens it on tap, so drawing it for an
    // event that is not in the timeline is a wrong thread rather than a blank
    // one. It also fails an early return that left `threadEventId` as a `late`
    // field, which would have deferred the crash to the next tap.
    final timeline = _FakeTimeline(events: [const _FakeThreadRootEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 3));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ThreadReplyFooter),
      findsNothing,
      reason: 'an index with no event must render nothing, not an empty footer',
    );
  });

  testWidgets('a changed index repoints the footer at the new event', (
    tester,
  ) async {
    // The gap CodeRabbit found from one side and a PR 337 subagent from the
    // other. The owning TimelineEventViewMessage rebuilds this child with a
    // new index whenever its own loadEventState runs, and nothing here is
    // keyed, so the same State object is reused. Without didUpdateWidget the
    // footer kept naming the thread resolved at initState - tapping it opens
    // a thread on a message that is no longer the one above it.
    final timeline = _FakeTimeline(
      events: [
        const _FakeThreadRootEvent(),
        const _FakeThreadRootEvent(eventId: r'$root-2'),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_replyBody), findsOneWidget);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_secondReplyBody), findsOneWidget);
    expect(senderPlaceholder(_secondReplySender), findsOneWidget);
    expect(
      find.text(_replyBody),
      findsNothing,
      reason: 'a new index must not keep the previous thread reply',
    );
    expect(senderPlaceholder(_replySender), findsNothing);
  });

  testWidgets('a replacement at the SAME index repoints the footer', (
    tester,
  ) async {
    // The half the index comparison cannot see, and the one that fires in
    // production. `onEventRemoved` shrinks the list without calling
    // `update()`, so the rows below keep their old indexes; the next
    // `onRoomUpdated` then calls `update(i)` on every mounted row with the
    // index it already had. This row is therefore rebuilt with the same index
    // against a list in which a DIFFERENT event now sits at it.
    //
    // This is the wrong-data outcome rather than a stale-looking one, so the
    // assertion that earns its keep is the last one: `threadEventId` is what
    // `onTap` hands the event bus, and a footer that merely LOOKS refreshed
    // can still open the previous message's thread.
    final timeline = _FakeTimeline(
      events: [
        const _FakeThreadRootEvent(),
        const _FakeThreadRootEvent(eventId: r'$root-2'),
      ],
    );

    final openedThreads = <(String, String, String)>[];
    // Not `close()`d, and the controller is a shared static: closing a
    // broadcast controller another test may still be listening on is how this
    // tree has hung dispose before. Cancelling the subscription is enough.
    final subscription = EventBus.openThread.stream.listen(openedThreads.add);
    addTearDown(subscription.cancel);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_replyBody), findsOneWidget);

    // The removal production performs, leaving $root-2 at index 0.
    timeline.events.removeAt(0);
    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_secondReplyBody),
      findsOneWidget,
      reason: 'the event at index 0 changed, so the footer must follow',
    );
    expect(senderPlaceholder(_secondReplySender), findsOneWidget);
    expect(
      find.text(_replyBody),
      findsNothing,
      reason: 'a replaced event must not keep the previous thread reply',
    );

    // Called rather than tapped: the callback is the whole subject here, and
    // driving it directly keeps the assertion off hit-test geometry.
    tester.widget<ThreadReplyFooter>(find.byType(ThreadReplyFooter)).onTap!();
    // The broadcast controller delivers on a microtask, so the listener has
    // not run yet at the point of the call above.
    await tester.pump();

    expect(
      openedThreads.map((opened) => opened.$3),
      [r'$root-2'],
      reason: 'the footer must open the thread of the event now at index 0',
    );
  });

  testWidgets('an index that becomes valid again resolves the footer', (
    tester,
  ) async {
    // The recovery half. The range guard leaves threadEventId null, and
    // before didUpdateWidget existed it stayed null for the life of the
    // State: an entry corrected by update() got its index back, but the
    // footer stayed absent until something remounted the row.
    final timeline = _FakeTimeline(events: [const _FakeThreadRootEvent()]);

    await tester.pumpWidget(subject(timeline: timeline, index: 3));
    await tester.pump();
    expect(find.byType(ThreadReplyFooter), findsNothing);

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(ThreadReplyFooter), findsOneWidget);
    expect(find.text(_replyBody), findsOneWidget);
  });

  testWidgets('a new event with no known reply clears the previous one', (
    tester,
  ) async {
    // Re-resolving is not enough on its own. getStateFromIndex returns early
    // when the new root has no first reply yet, and that path assigns none of
    // senderName, body, senderAvatar or senderColor - so without the clear in
    // didUpdateWidget the footer would caption the new thread with the
    // previous thread's reply, which is the wrong-thread render the range
    // guard exists to avoid.
    //
    // `$root-no-reply` is absent from _repliesByRoot, which is the real "the
    // event is here, its first reply is not known yet" state.
    final timeline = _FakeTimeline(
      events: [
        const _FakeThreadRootEvent(),
        const _FakeThreadRootEvent(eventId: r'$root-no-reply'),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_replyBody), findsOneWidget);
    expect(senderPlaceholder(_replySender), findsOneWidget);

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(ThreadReplyFooter),
      findsOneWidget,
      reason: 'the root event resolves, so the footer itself stays',
    );
    expect(
      find.text(_replyBody),
      findsNothing,
      reason: 'but it must not keep the previous reply body',
    );
    expect(
      senderPlaceholder(_replySender),
      findsNothing,
      reason: 'nor the previous reply sender',
    );
    expect(senderPlaceholder('Unknown Sender'), findsOneWidget);
  });
}

class _FakeThreadsComponent implements ThreadsComponent {
  @override
  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline) {
    return _repliesByRoot[event.eventId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeThreadRootEvent implements TimelineEvent {
  const _FakeThreadRootEvent({this.eventId = r'$root'});

  @override
  final String eventId;

  @override
  String get senderId => '@bob:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 10);

  @override
  String get plainTextBody => 'thread root';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeThreadReplyEvent implements TimelineEventMessage {
  const _FakeThreadReplyEvent({
    this.eventId = r'$thread-reply',
    this.senderId = _replySender,
    this.body = _replyBody,
  });

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final String? body;

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 11);

  @override
  String get plainTextBody => body ?? '';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required List<TimelineEvent> events}) {
    room = _FakeRoom(client: _FakeClient());
    client = room.client;
    this.events = List<TimelineEvent>.of(events);
  }

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
