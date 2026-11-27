import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_generic.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// This row has two possible sources of truth - a `timeline` plus an `index`,
/// and a directly passed `initialEvent` - and `didUpdateWidget` has a branch
/// for each. The case CodeRabbit round 4 found is the one where BOTH are
/// withdrawn: a timeline that goes from non-null to null while `initialEvent`
/// stays null satisfied the first branch's comparison but failed its
/// `timeline != null` guard, and left the second branch's comparison
/// unchanged - so neither ran, and the previous event's text, icon and
/// sender avatar stayed on screen with nothing behind them.
///
/// `timeline_event_view_generic_test.dart` covers the index and
/// `initialEvent` halves; this file covers only the withdrawal, and the
/// symmetric case that a withdrawal must NOT clear.
/// A 1x1 transparent PNG, decodable so the avatar actually paints. See
/// [_FakeMember.avatar].
final Uint8List _transparentPixel = Uint8List.fromList(const <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

const String _timelineBody = 'alice joined the room';
const String _directBody = 'bob changed the topic';
const String _secondTimelineBody = 'carol set the topic';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject({
    required Room room,
    Timeline? timeline,
    TimelineEvent? initialEvent,
    int index = 0,
  }) {
    return MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewGeneric(
          timeline: timeline,
          initialEvent: initialEvent,
          index: index,
          room: room,
        ),
      ),
    );
  }

  testWidgets('a withdrawn timeline with no event clears the row', (
    tester,
  ) async {
    // The assertion is "the previous text is gone", not "no exception". A
    // fall-through kept a row captioned with an event this widget can no
    // longer reach through either of its inputs, which is a wrong row rather
    // than a blank one - the same rule the range guard inside
    // `setStateFromindex` already follows.
    // Rendered WITH an avatar so all three cleared slots are observable. Round
    // 5 found this test asserting only the caption - and the widget clears
    // `text`, `icon` and `senderAvatar` together, so a clear path that emptied
    // one of them would have passed. That is the same gap round 4 was removing
    // from the neighbouring generic test while this file was being written on
    // another branch; disjoint branches stop conflicts, not pattern leakage.
    final timeline = _FakeTimeline(
      events: [
        const _FakeGenericEvent(
          id: r'$first',
          body: _timelineBody,
          showSenderAvatar: true,
        ),
      ],
    );
    final room = timeline.room;

    await tester.pumpWidget(subject(room: room, timeline: timeline));
    await tester.pump();
    expect(find.text(_timelineBody), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);

    await tester.pumpWidget(subject(room: room));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_timelineBody),
      findsNothing,
      reason: 'no timeline and no event leaves nothing this row may render',
    );
    expect(
      find.byType(Avatar),
      findsNothing,
      reason: 'the withdrawn sender\'s avatar may not outlive its event',
    );
    expect(
      find.byIcon(Icons.info_outline),
      findsNothing,
      reason: 'nor the icon that event supplied',
    );
  });

  testWidgets('a withdrawn timeline keeps a row driven by its own event', (
    tester,
  ) async {
    // The over-clearing half, and the reason the clear is guarded on
    // `initialEvent == null` rather than applied to every withdrawal. An
    // event passed directly is this row's own source of truth and does not
    // stop being one because a timeline was taken away - that is exactly how
    // TimelineEventViewSingle drives this view, with no timeline at all.
    final timeline = _FakeTimeline(
      events: [const _FakeGenericEvent(id: r'$first', body: _timelineBody)],
    );
    final room = timeline.room;
    const direct = _FakeGenericEvent(id: r'$direct', body: _directBody);

    await tester.pumpWidget(
      subject(room: room, timeline: timeline, initialEvent: direct),
    );
    await tester.pump();
    expect(find.text(_directBody), findsOneWidget);

    await tester.pumpWidget(subject(room: room, initialEvent: direct));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_directBody),
      findsOneWidget,
      reason: 'the event this row was given is still its source of truth',
    );
  });

  testWidgets('an index change does not override a directly passed event', (
    tester,
  ) async {
    // The precedence CodeRabbit round 5 found stated-but-not-kept. Both
    // sources present, `initialEvent` unchanged, only the index moves: the
    // reload branch fired and replaced the direct event with whatever the
    // timeline held at the new index, while the comment two lines above it
    // said `initialEvent` outranks the timeline.
    //
    // Unreachable in production - `timeline_view_entry` passes a timeline and
    // an index, `timeline_event_view_single` passes an event and no timeline,
    // and nothing passes both. This test is here because the contract was
    // asserted in prose and checked by nothing, which is how it came to
    // disagree with the branch below it in the same method.
    final timeline = _FakeTimeline(
      events: [
        const _FakeGenericEvent(id: r'$first', body: _timelineBody),
        const _FakeGenericEvent(id: r'$second', body: _secondTimelineBody),
      ],
    );
    final room = timeline.room;
    const direct = _FakeGenericEvent(id: r'$direct', body: _directBody);

    await tester.pumpWidget(
      subject(room: room, timeline: timeline, initialEvent: direct, index: 0),
    );
    await tester.pump();
    expect(find.text(_directBody), findsOneWidget);

    await tester.pumpWidget(
      subject(room: room, timeline: timeline, initialEvent: direct, index: 1),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_directBody),
      findsOneWidget,
      reason:
          'the directly passed event outranks the timeline in BOTH '
          'branches, not just the withdrawal one',
    );
    expect(
      find.text(_secondTimelineBody),
      findsNothing,
      reason:
          'the index moved, but the timeline is the fallback source and '
          'must not displace the event this row was handed',
    );
  });
}

class _FakeGenericEvent implements TimelineEventGeneric {
  const _FakeGenericEvent({
    required String id,
    required String body,
    this.showSenderAvatar = false,
  }) : _id = id,
       _body = body;

  final String _id;
  final String _body;

  /// Settable, and false by default only to leave the other cases as they
  /// were. It was a hardcoded `=> false` getter, which meant no test in this
  /// file could observe the avatar at all - the withdrawal clears `text`,
  /// `icon` AND `senderAvatar`, and a third of that was unobservable by
  /// construction. A fake's default is not a neutral choice when it decides
  /// which assertions are able to fail.
  @override
  final bool showSenderAvatar;

  @override
  String get eventId => _id;

  @override
  String get senderId => '@alice:example.org';

  @override
  DateTime get originServerTs => DateTime.utc(2026, 9, 7, 10);

  @override
  String get plainTextBody => _body;

  @override
  String getBody({Timeline? timeline}) => _body;

  @override
  IconData? get icon => Icons.info_outline;

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

  /// A real provider, because `senderAvatar` is only assigned from THIS, and
  /// `build` only renders the `Avatar` when it is non-null. Returning null
  /// here made `showSenderAvatar: true` insufficient on its own - the second
  /// place the avatar could be silently unobservable.
  ///
  /// A real 1x1 PNG rather than an `AssetImage`: the provider IS resolved when
  /// the row pumps, and a missing asset surfaces as a FlutterError that these
  /// tests catch on `takeException()` - failing them for the harness rather
  /// than for the behaviour.
  @override
  ImageProvider? get avatar => MemoryImage(_transparentPixel);

  @override
  Color get defaultColor => const Color(0xFF534CDD);
}
