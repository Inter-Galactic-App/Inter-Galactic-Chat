import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_message.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const String _newestBody = 'the newest message';
const String _oldestBody = 'the oldest message';

/// Both fake events share a sender, and [_FakeMember] reports the identifier as
/// the display name, so this is the string the sender header paints.
const String _senderName = '@alice:example.org';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
    // Bubble mode is what routes `build` through shouldShowBubbleAvatar, which
    // is where the second test's read lands.
    await globals.preferences.bubbleMessages.set(true);
  });

  Widget subject({required Timeline timeline, required int index}) {
    return MaterialApp(
      // The layout renders through tiamat atoms, which read ThemeSettings off
      // the theme.
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        // Wide enough that the row's own Flex does not overflow. 360 was, by
        // 81 pixels - and because these tests assert on `takeException()`
        // being null, a RenderFlex overflow fails them exactly like the
        // RangeError they exist to catch. The width is harness, not subject:
        // if a future change makes this overflow again, widen it rather than
        // relax the assertion, which is the only thing here proving the guard
        // holds.
        body: SizedBox(
          width: 800,
          child: TimelineEventViewMessage(timeline: timeline, index: index),
        ),
      ),
    );
  }

  testWidgets('an index that goes out of range clears the row', (tester) async {
    // loadEventState read `events[eventIndex]` unguarded. It runs from
    // didUpdateWidget as well as initState, so an index change that lands past
    // the end of the list reached it directly.
    //
    // A bare early return was not available here: `build` reads senderName,
    // senderId, senderColor, eventId and sentTime unconditionally and all five
    // are `late`, so returning without loading would have swapped RangeError
    // for LateInitializationError - the trap TimelineEventViewPoll hit. Hence
    // `_hasEvent`, and hence this asserting on what is rendered rather than
    // only on the absence of an exception.
    final timeline = _FakeTimeline(
      events: [
        _FakeTextMessageEvent(id: r'$newest', body: _newestBody, seconds: 20),
        _FakeTextMessageEvent(id: r'$oldest', body: _oldestBody, seconds: 0),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_newestBody), findsOneWidget);

    await tester.pumpWidget(subject(timeline: timeline, index: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_newestBody),
      findsNothing,
      reason: 'an out-of-range index must clear, not keep the previous event',
    );
    expect(
      find.text(_oldestBody),
      findsNothing,
      reason: 'and must not fall back to a neighbouring event either',
    );
  });

  testWidgets('a rebuild after the list shrinks under a fixed index is safe', (
    tester,
  ) async {
    // The path the index-change test above cannot reach, and the one that
    // actually fires in production. TimelineViewEntry has no didUpdateWidget,
    // so after a removal it keeps handing this row the SAME index while the
    // list under it is already shorter. The index prop does not change, so
    // this widget's own didUpdateWidget body does not run and loadEventState
    // is never re-entered - `build` is where the stale index is read, at
    // shouldShowBubbleAvatar's `events[index]` and at the attachment slot's.
    //
    // That is why the guard is a check in `build` and not only a check at load
    // time; a guard placed only in loadEventState passes the test above and
    // still throws here.
    final timeline = _FakeTimeline(
      events: [
        _FakeTextMessageEvent(id: r'$newest', body: _newestBody, seconds: 20),
        _FakeTextMessageEvent(id: r'$oldest', body: _oldestBody, seconds: 0),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();
    expect(find.text(_oldestBody), findsOneWidget);

    // The real removal API, so the list shrinks the way production shrinks it.
    expect(timeline.removeEvent(r'$newest'), isTrue);
    await tester.pumpWidget(subject(timeline: timeline, index: 1));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_oldestBody),
      findsNothing,
      reason: 'the row must go blank rather than repaint a stale event',
    );
  });

  testWidgets('a new initialEvent replaces the rendered row', (tester) async {
    // The other half of this widget's input. TimelineEventViewSingle drives
    // it with `initialEvent` and no timeline, at a constant index and
    // revision, so the branch above can never fire there - and before this
    // the event was read once, at initState, and never again.
    //
    // Reachable through room_event_search_widget.dart:96, whose results
    // arrive over a stream and replace the list in place under an unkeyed
    // AnimatedList: a result inserted above this row hands the same State a
    // different event.
    final room = _FakeRoom(client: _FakeClient());

    Widget single(TimelineEvent event) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: TimelineEventViewMessage(
            room: room,
            overrideShowSender: true,
            index: 0,
            detailed: true,
            initialEvent: event,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      single(
        _FakeTextMessageEvent(id: r'$newest', body: _newestBody, seconds: 20),
      ),
    );
    await tester.pump();
    expect(find.text(_newestBody), findsOneWidget);

    await tester.pumpWidget(
      single(
        _FakeTextMessageEvent(id: r'$oldest', body: _oldestBody, seconds: 0),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_oldestBody), findsOneWidget);
    expect(
      find.text(_newestBody),
      findsNothing,
      reason: 'a new initialEvent must replace the row, not sit under it',
    );
  });

  testWidgets('an initialEvent that goes away clears the whole row', (
    tester,
  ) async {
    // The other direction of the branch above, and the one it did not cover:
    // the condition tested `initialEvent != null` first, so an event that
    // became null fell through and the removed message stayed on screen.
    //
    // No caller does this today - TimelineEventViewSingle's own `event` is
    // non-nullable - so this test is pinning the widget's contract rather
    // than a reproduction: the parameter is nullable, so "the event was
    // withdrawn" is a state a caller can express, and the empty row is the
    // only render for it that is not a lie.
    //
    // `_hasEvent` is what has to be cleared, not the fields: senderName and
    // the other four `late` fields still hold the previous event, and
    // `_hasEvent` is the flag that stops `build` reading them.
    //
    // Which is exactly why the body text cannot be the only thing asserted.
    // The five stale fields are still there and still renderable; only
    // `_hasEvent` stops `build` from painting a sender header, an avatar and a
    // timestamp for a message that has been withdrawn. A clear path that
    // dropped the CONTENT instead of the flag - `formattedContent = null`
    // rather than `_hasEvent = false` - removes the body and leaves the header
    // naming the vanished sender, and a body-only assertion calls that a pass.
    //
    // So this asserts the row's disappearance from both ends: the sender name,
    // which is a user-visible non-body element on screen before the
    // withdrawal, and the layout widget itself, which is what `_hasEvent`
    // actually gates.
    final room = _FakeRoom(client: _FakeClient());

    Widget single(TimelineEvent? event) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          child: TimelineEventViewMessage(
            room: room,
            overrideShowSender: true,
            index: 0,
            detailed: true,
            initialEvent: event,
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      single(
        _FakeTextMessageEvent(id: r'$newest', body: _newestBody, seconds: 20),
      ),
    );
    await tester.pump();
    // Both halves of the row are on screen first, so both assertions after the
    // withdrawal are observing a state that actually changed.
    expect(find.text(_newestBody), findsOneWidget);
    // The sender header is the non-body half, and asserting it is the whole
    // point of this case. `detailed: true` with `overrideShowSender` renders
    // the row as sender + timestamp + body, so a clear path that emptied the
    // caption while leaving the header painted would satisfy a body-only
    // assertion and leave a headed, dateless, textless row on screen.
    expect(
      find.text(_senderName),
      findsOneWidget,
      reason:
          'the header must be on screen first, or its absence after the '
          'withdrawal proves nothing',
    );

    await tester.pumpWidget(single(null));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_newestBody),
      findsNothing,
      reason: 'a removed event must not stay on screen',
    );
    expect(
      find.text(_senderName),
      findsNothing,
      reason: 'nor may the sender header outlive the event it described',
    );
  });
}

class _FakeTextMessageEvent implements TimelineEventMessage {
  _FakeTextMessageEvent({
    required String id,
    required String body,
    required int seconds,
  }) : _id = id,
       _body = body,
       _seconds = seconds;

  final String _id;
  final String _body;
  final int _seconds;

  @override
  String get eventId => _id;

  @override
  String get senderId => _senderName;

  @override
  DateTime get originServerTs =>
      DateTime.utc(2026, 9, 7, 10).add(Duration(seconds: _seconds));

  @override
  TimelineEventStatus get status => TimelineEventStatus.synced;

  @override
  String get plainTextBody => _body;

  @override
  String get source => '{}';

  @override
  bool get editable => false;

  @override
  String? get body => _body;

  @override
  String? get bodyFormat => null;

  @override
  String? get formattedBody => null;

  @override
  List<Attachment>? get attachments => null;

  @override
  Widget? buildFormattedContent({Timeline? timeline}) => Text(_body);

  @override
  String getPlaintextBody(Timeline timeline) => _body;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => const [];

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
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  T? getComponent<T extends RoomComponent>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}

class _FakeClient implements Client {
  _FakeClient() : self = const _FakeProfile('@self:example.org');

  @override
  final Profile self;

  @override
  String get identifier => 'client-${self.identifier}';

  @override
  bool get supportsE2EE => true;

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
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
