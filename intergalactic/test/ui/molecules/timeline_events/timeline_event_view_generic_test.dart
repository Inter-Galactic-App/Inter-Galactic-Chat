import 'dart:async';

import 'package:flutter/foundation.dart';
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
import 'package:intergalactic/ui/molecules/read_indicator.dart';
import 'package:intergalactic/ui/molecules/timeline_events/events/timeline_event_view_generic.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/avatar.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

const String _firstBody = 'alice joined the room';
const String _secondBody = 'bob changed the topic';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('mobile');
  });

  Widget subject({required Timeline timeline, required int index}) {
    return MaterialApp(
      // The row renders through tiamat atoms, which read ThemeSettings off the
      // theme.
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewGeneric(
          timeline: timeline,
          index: index,
          room: timeline.room,
        ),
      ),
    );
  }

  testWidgets('an index that goes out of range clears the previous row', (
    tester,
  ) async {
    // This view does have a didUpdateWidget, so unlike the reply and thread
    // views the index it is given really can change under a mounted row - and
    // an entry that was corrected by `update()` in one frame can be built
    // against a list a later removal has already shortened.
    //
    // The assertion is "the first event's text is gone", not "no exception".
    // An early return that kept `text` would caption this row with the event
    // it used to show, which is a wrong row rather than a blank one.
    final timeline = _FakeTimeline(
      events: [
        const _FakeGenericEvent(id: r'$second', body: _secondBody),
        const _FakeGenericEvent(id: r'$first', body: _firstBody),
      ],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 0));
    await tester.pump();
    expect(find.text(_secondBody), findsOneWidget);

    // The index itself has to change for didUpdateWidget to re-read anything;
    // it compares the index and the timeline and nothing else.
    await tester.pumpWidget(subject(timeline: timeline, index: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_secondBody),
      findsNothing,
      reason: 'an out-of-range index must clear, not keep the previous event',
    );
    expect(
      find.text(_firstBody),
      findsNothing,
      reason: 'and must not fall back to a neighbouring event either',
    );
  });

  testWidgets('mounting straight onto an out-of-range index renders nothing', (
    tester,
  ) async {
    final timeline = _FakeTimeline(
      events: [const _FakeGenericEvent(id: r'$only', body: _firstBody)],
    );

    await tester.pumpWidget(subject(timeline: timeline, index: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_firstBody), findsNothing);
  });

  testWidgets('a new initialEvent replaces the rendered row', (tester) async {
    // The other half of this widget's input. TimelineEventViewSingle drives
    // it with `initialEvent` and no timeline, at a constant index of 0, so
    // the index/timeline branch of didUpdateWidget can never fire there - and
    // before this the event was read once, at initState, and never again.
    //
    // Reachable through room_event_search_widget.dart:96, whose results
    // arrive over a stream and replace the list in place under an unkeyed
    // AnimatedList: a result inserted above this row hands the same State a
    // different event.
    final room = _FakeRoom(client: _FakeClient());

    Widget single(TimelineEvent event) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewGeneric(
          index: 0,
          initialEvent: event,
          room: room,
        ),
      ),
    );

    await tester.pumpWidget(
      single(const _FakeGenericEvent(id: r'$first', body: _firstBody)),
    );
    await tester.pump();
    expect(find.text(_firstBody), findsOneWidget);

    await tester.pumpWidget(
      single(const _FakeGenericEvent(id: r'$second', body: _secondBody)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_secondBody), findsOneWidget);
    expect(
      find.text(_firstBody),
      findsNothing,
      reason: 'a new initialEvent must replace the row, not sit under it',
    );
  });

  testWidgets('an initialEvent that goes away clears the whole row', (
    tester,
  ) async {
    // The other direction of the branch above, and the one it did not cover:
    // the condition tested `initialEvent != null` first, so an event that
    // became null fell through and the previous text, icon and avatar stayed
    // on screen indefinitely.
    //
    // No caller does this today - TimelineEventViewSingle's own `event` is
    // non-nullable - so this test is pinning the widget's contract rather
    // than a reproduction: the parameter is nullable, so "the event was
    // withdrawn" is a state a caller can express, and the empty row is the
    // only render for it that is not a lie.
    //
    // The withdrawal clears three fields - `text`, `icon` and `senderAvatar` -
    // and mounts the event WITH an avatar so that all three are observable.
    // `_FakeGenericEvent` defaults `showSenderAvatar` to false, so a version of
    // this test built on the default never rendered an avatar at all: the
    // avatar half of "the row is gone" could not fail for any change to this
    // widget, which is the fake's default masquerading as coverage.
    //
    // Asserting the set rather than the text alone is what separates "the row
    // is gone" from "the body string is gone". `build` short-circuits on a null
    // `text`, so a clear path that emptied the caption without clearing the
    // state - `text = ''` rather than `text = null` - leaves the icon, the
    // avatar and the read indicator painted beside a blank caption, and a
    // text-only assertion reports that as a pass.
    final room = _FakeRoom(client: _FakeClient());

    Widget single(TimelineEvent? event) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewGeneric(
          index: 0,
          initialEvent: event,
          room: room,
        ),
      ),
    );

    await tester.pumpWidget(
      single(
        const _FakeGenericEvent(
          id: r'$first',
          body: _firstBody,
          showSenderAvatar: true,
        ),
      ),
    );
    await tester.pump();
    // Every slot the withdrawal has to clear is on screen first, so each
    // assertion below is a state this test can actually observe changing.
    expect(find.text(_firstBody), findsOneWidget);
    expect(find.byType(Avatar), findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byType(ReadIndicator), findsOneWidget);

    await tester.pumpWidget(single(null));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.text(_firstBody),
      findsNothing,
      reason: 'a removed event must not stay on screen',
    );
    expect(
      find.byType(Avatar),
      findsNothing,
      reason: 'nor may the withdrawn sender\'s avatar outlive the event',
    );
    expect(
      find.byIcon(Icons.info_outline),
      findsNothing,
      reason: 'nor the icon the withdrawn event supplied',
    );
    expect(
      find.byType(ReadIndicator),
      findsNothing,
      reason:
          'the empty render is an empty Container, so no part of the row - '
          'including the trailing read indicator - may survive the withdrawal',
    );
  });

  testWidgets('swapping to an event without an avatar drops the old one', (
    tester,
  ) async {
    // loadStateFromEvent assigns `text` and `icon` on every path but only
    // assigns `senderAvatar` for an event that wants one, so "this row now
    // shows THIS event" was not true of the avatar slot: a swap to an event
    // without one kept the previous sender's face beside the new text.
    //
    // Reachable from both callers of that method - setStateFromindex as well
    // as the initialEvent branch this test drives it through.
    final room = _FakeRoom(client: _FakeClient());

    Widget single(TimelineEvent event) => MaterialApp(
      theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
      home: Scaffold(
        body: TimelineEventViewGeneric(
          index: 0,
          initialEvent: event,
          room: room,
        ),
      ),
    );

    await tester.pumpWidget(
      single(
        const _FakeGenericEvent(
          id: r'$first',
          body: _firstBody,
          showSenderAvatar: true,
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(Avatar), findsOneWidget);

    await tester.pumpWidget(
      single(const _FakeGenericEvent(id: r'$second', body: _secondBody)),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text(_secondBody), findsOneWidget);
    expect(
      find.byType(Avatar),
      findsNothing,
      reason: 'an event that wants no avatar must not inherit the previous one',
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

/// An [ImageProvider] whose load never completes.
///
/// The avatar tests only read whether the slot is filled, and a provider that
/// actually decoded could fail and land in `takeException`, which these tests
/// assert on for a different reason.
class _NeverLoadingImage extends ImageProvider<_NeverLoadingImage> {
  const _NeverLoadingImage();

  @override
  Future<_NeverLoadingImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_NeverLoadingImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _NeverLoadingImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
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
  ImageProvider? get avatar => const _NeverLoadingImage();

  @override
  Color get defaultColor => const Color(0xFF534CDD);
}
