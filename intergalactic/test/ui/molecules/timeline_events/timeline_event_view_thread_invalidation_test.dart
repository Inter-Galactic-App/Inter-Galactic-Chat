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

/// What this file pins, and why it is separate from
/// `timeline_event_view_thread_test.dart`.
///
/// That file pins the INDEX half of the invalidation key: a changed index, an
/// index that goes out of range, and a different event id arriving at an
/// unchanged index. Everything in it can be expressed with `const` fakes,
/// because it only ever needs two events that differ by id.
///
/// This file pins the half that a comparison of event IDS cannot express at
/// all: the entry at this index is REPLACED by a new object carrying the SAME
/// id. That is what `MatrixTimeline.onEventChanged` does - it assigns
/// `events[i] = convertEvent(...)` - and it is the SDK's signal for exactly
/// the three things CodeRabbit round 4 found the footer missing: a first
/// thread reply arriving, a reply decrypting, and a reply being redacted. All
/// three route through `matrix.Timeline.addAggregatedEvent` or
/// `removeAggregatedEvent`, both of which call `onChange` on the thread ROOT
/// rather than on the reply.
///
/// Every root fake here is therefore deliberately NOT `const`: two `const`
/// instances with the same id are canonicalised to one object, which is the
/// opposite of what these tests need to express.
const String _replyBody = 'the first thread reply';
const String _laterReplyBody = 'the decrypted thread reply';
const String _replySender = '@alice:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The sender name reaches rendered text only under `if (Layout.desktop)`
  // (thread_reply_footer.dart:91) and these tests run under the mobile
  // override below, so the sender half of the state is asserted through the
  // avatar placeholder - a `find.text` on it would pass vacuously here.
  Finder senderPlaceholder(String name) => find.byWidgetPredicate(
    (widget) => widget is Avatar && widget.placeholderText == name,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject({
    required Timeline timeline,
    required int index,
    required ThreadsComponent component,
  }) {
    return MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewThread(
          initialIndex: index,
          timeline: timeline,
          component: component,
        ),
      ),
    );
  }

  testWidgets('a first reply arriving under an unchanged event id resolves', (
    tester,
  ) async {
    // Reported independently by two CodeRabbit round 4 batches. The head event
    // of an empty thread renders the "Unknown Sender" footer, and its id does
    // not change when the thread's first reply arrives - so an invalidation
    // key made of the id alone never re-resolved and the footer stayed empty
    // for the life of the row.
    final component = _RecordingThreadsComponent();
    final timeline = _FakeTimeline(events: [_RootEvent()]);

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    expect(
      find.byType(ThreadReplyFooter),
      findsOneWidget,
      reason: 'the head event resolves, so the footer itself is present',
    );
    expect(senderPlaceholder('Unknown Sender'), findsOneWidget);
    expect(find.text(_replyBody), findsNothing);

    // What the SDK does when the first reply lands: `addAggregatedEvent` for
    // the reply fires `onChange` on the ROOT, and `MatrixTimeline
    // .onEventChanged` replaces the converted entry at that index with a new
    // object carrying the same id.
    component.replies[r'$root'] = const _ReplyEvent();
    timeline.events[0] = _RootEvent();

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_replyBody),
      findsOneWidget,
      reason: 'the thread gained a reply, so the footer must show it',
    );
    expect(senderPlaceholder(_replySender), findsOneWidget);
    expect(
      senderPlaceholder('Unknown Sender'),
      findsNothing,
      reason: 'the placeholder must not survive a resolved reply',
    );
  });

  testWidgets('a reply that changes under an unchanged reply id re-resolves', (
    tester,
  ) async {
    // The decrypt and redaction halves of the same finding. Neither the head
    // event's id nor the REPLY's id changes; only the reply's rendered body
    // does. A key made of either id is blind to both.
    final component = _RecordingThreadsComponent(
      replies: {r'$root': const _ReplyEvent(body: _replyBody)},
    );
    final timeline = _FakeTimeline(events: [_RootEvent()]);

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();
    expect(find.text(_replyBody), findsOneWidget);

    // A NEW reply object rather than a mutated one, and the same reply id: a
    // fake that handed back a value the test then mutated in place would stay
    // green against the very key this test exists to pin, because the widget
    // would see the new body without ever re-resolving.
    component.replies[r'$root'] = const _ReplyEvent(body: _laterReplyBody);
    timeline.events[0] = _RootEvent();

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_laterReplyBody),
      findsOneWidget,
      reason: 'the reply body changed under an unchanged id',
    );
    expect(
      find.text(_replyBody),
      findsNothing,
      reason: 'and the previous body must not survive it',
    );
  });

  testWidgets('a redacted reply leaves the footer with no reply at all', (
    tester,
  ) async {
    // The transition the test above does NOT make: reply -> null, rather than
    // reply -> different reply. CodeRabbit round 5 found that gap, and it was
    // worth finding because redaction is one of the three cases the entry-object
    // key was chosen FOR - #358 named it in its own justification while only
    // ever exercising the body-swap half of it.
    //
    // The distinction matters to the widget, not just to the coverage count:
    // `getStateFromIndex` returns EARLY when the thread has no first reply, and
    // that early return is the path that leaves the cleared fields cleared. A
    // regression that re-resolved but skipped the clear would still render the
    // redacted reply, and the body-swap test could never see it - there, the
    // resolve always finds a reply to overwrite the fields with.
    final component = _RecordingThreadsComponent(
      replies: {r'$root': const _ReplyEvent(body: _replyBody)},
    );
    final timeline = _FakeTimeline(events: [_RootEvent()]);

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();
    expect(find.text(_replyBody), findsOneWidget);

    // Redaction, as the SDK presents it: the aggregated reply is gone and the
    // root's entry is replaced, exactly as `removeAggregatedEvent` leaves it.
    component.replies.remove(r'$root');
    timeline.events[0] = _RootEvent();

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_replyBody),
      findsNothing,
      reason: 'a redacted reply must not stay in the footer',
    );
    expect(
      senderPlaceholder('Unknown Sender'),
      findsOneWidget,
      reason:
          'and the footer must fall back to the unresolved state rather than '
          'keeping the redacted sender beside a blank body',
    );
  });

  testWidgets('a re-resolve keeps the footer pointed at its own head event', (
    tester,
  ) async {
    // `threadEventId` is what `onTap` hands the event bus, and it is cleared
    // before every re-resolve. A footer that merely LOOKS refreshed can still
    // open the wrong thread - or, if the clear were not followed by a
    // successful resolve, none at all.
    final component = _RecordingThreadsComponent();
    final timeline = _FakeTimeline(events: [_RootEvent()]);

    final openedThreads = <(String, String, String)>[];
    // Not `close()`d: the controller is a shared static, and closing a
    // broadcast controller another test may still be listening on is how this
    // tree has hung dispose before. Cancelling the subscription is enough.
    final subscription = EventBus.openThread.stream.listen(openedThreads.add);
    addTearDown(subscription.cancel);

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    component.replies[r'$root'] = const _ReplyEvent();
    timeline.events[0] = _RootEvent();

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();

    // Called rather than tapped: the callback is the subject here, and driving
    // it directly keeps the assertion off hit-test geometry.
    tester.widget<ThreadReplyFooter>(find.byType(ThreadReplyFooter)).onTap!();
    // The broadcast controller delivers on a microtask.
    await tester.pump();

    expect(openedThreads.map((opened) => opened.$3), [r'$root']);
  });

  testWidgets('a rebuild that changes nothing does not re-resolve', (
    tester,
  ) async {
    // The other side of the key, and the reason it is not the owning widget's
    // `updateRevision`. That revision is bumped for EVERY mounted row on every
    // room update - any incoming message reaches `onRoomUpdated`, which calls
    // `update(i)` on all of them - so a row that re-resolved on it would run
    // its lookup on every message in the room to reach the same answer.
    //
    // Counting the lookup rather than asserting on the render: a re-resolve
    // that reaches the same answer is invisible on screen, which is exactly
    // why this regression could return unnoticed.
    final component = _RecordingThreadsComponent(
      replies: {r'$root': const _ReplyEvent()},
    );
    final timeline = _FakeTimeline(events: [_RootEvent()]);

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();
    expect(component.lookups, 1, reason: 'initState resolves once');

    for (var rebuild = 0; rebuild < 3; rebuild++) {
      await tester.pumpWidget(
        subject(timeline: timeline, index: 0, component: component),
      );
      await tester.pump();
    }

    expect(
      component.lookups,
      1,
      reason: 'nothing about this row changed, so nothing may be re-resolved',
    );
    expect(find.text(_replyBody), findsOneWidget);
  });

  testWidgets('a lookup that replaces its own entry still settles', (
    tester,
  ) async {
    // `getFirstReplyToThread` is not a pure read. On the `m.relations`
    // /`m.thread` path `MatrixThreadsComponent` calls `matrix.Timeline
    // .addAggregatedEvent`, which fires the SDK timeline's `onChange` for the
    // thread ROOT - this row's own event - and `MatrixTimeline
    // .onEventChanged` then REPLACES `events[i]`. `Timeline.onChange` is a
    // `sync: true` controller, so all of that happens inside the lookup call.
    //
    // The row's key is that entry object, so the lookup perturbs its own key.
    // This pins the property that keeps that from spinning: the object is
    // recorded AFTER the lookup, so the replacement the lookup itself caused
    // is what gets stored and the next rebuild finds nothing to do.
    //
    // Without it every frame re-resolves forever, which is strictly worse than
    // the wasted work the `updateRevision` key was rejected for.
    final component = _RecordingThreadsComponent(
      replies: {r'$root': const _ReplyEvent()},
    );
    final timeline = _FakeTimeline(events: [_RootEvent()]);
    component.onLookup = () => timeline.events[0] = _RootEvent();

    await tester.pumpWidget(
      subject(timeline: timeline, index: 0, component: component),
    );
    await tester.pump();
    expect(component.lookups, 1);

    for (var rebuild = 0; rebuild < 3; rebuild++) {
      await tester.pumpWidget(
        subject(timeline: timeline, index: 0, component: component),
      );
      await tester.pump();
    }

    expect(
      component.lookups,
      1,
      reason:
          'the lookup replaced this row\'s own entry, and must not '
          're-trigger itself for having done so',
    );
    expect(find.text(_replyBody), findsOneWidget);
  });
}

class _RecordingThreadsComponent implements ThreadsComponent {
  _RecordingThreadsComponent({Map<String, TimelineEvent>? replies})
    : replies = <String, TimelineEvent>{...?replies};

  /// Keyed by the head event's id. An absent key is the real "the event is
  /// here, its first reply is not known yet" state, which renders the footer
  /// with the Unknown Sender placeholder.
  final Map<String, TimelineEvent> replies;

  int lookups = 0;

  /// Stands in for the aggregation write the real component performs as a side
  /// effect of the lookup. See the settling test.
  void Function()? onLookup;

  @override
  TimelineEvent? getFirstReplyToThread(TimelineEvent event, Timeline timeline) {
    lookups += 1;
    onLookup?.call();
    return replies[event.eventId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Deliberately not `const`: these tests turn on two instances with the same
/// id being DIFFERENT objects, and `const` would canonicalise them into one.
class _RootEvent implements TimelineEvent {
  _RootEvent();

  @override
  String get eventId => r'$root';

  @override
  String get senderId => '@bob:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 10);

  @override
  String get plainTextBody => 'thread root';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReplyEvent implements TimelineEventMessage {
  const _ReplyEvent({this.body = _replyBody});

  /// Constant across every instance on purpose: the decrypt/redaction test
  /// turns on the reply's CONTENT changing while its id does not.
  @override
  String get eventId => r'$thread-reply';

  @override
  String get senderId => _replySender;

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
  String get displayName => identifier;

  @override
  final String identifier;

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
