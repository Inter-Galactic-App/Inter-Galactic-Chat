import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/attachment.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/components/read_receipts/read_receipt_component.dart';
import 'package:intergalactic/client/components/room_component.dart';
import 'package:intergalactic/client/member.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/molecules/room_timeline_widget/room_timeline_widget_view.dart';
import 'package:intergalactic/ui/molecules/timeline_events/timeline_view_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Characterisation only - these tests describe what the timeline does today,
/// they do not assert what it should do.
///
/// `MatrixRoom.onRoomSyncUpdate` fires `onUpdate` for *any* sync touching the
/// room, ephemeral-only ones (typing, read receipts) included, and a call room
/// adds one `org.matrix.msc3401.call.member` republish per participant every
/// 25s on top of that. `RoomTimelineWidgetViewState.onRoomUpdated` is what
/// receives each of those, so the shape of its fan-out decides what a long
/// call-room session costs.
///
/// Two properties are pinned here:
///
///  1. one room update rebuilds *every mounted* entry, not just the rows whose
///     content changed; and
///  2. that fan-out is bounded by the viewport, **not** by the number of loaded
///     events - the `for (i < eventKeys.length)` loop in `onRoomUpdated` is
///     O(loaded events) in iterations, but only mounted rows have a
///     `currentState`, so the rebuild count does not grow with history depth.
///
/// (2) is the load-bearing one: it is why a timeline that has accumulated
/// thousands of call-member events does not get proportionally more expensive
/// per sync. If a change ever makes the rebuild count track
/// `timeline.events.length`, this test is meant to fail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('one room update rebuilds every mounted timeline entry', (
    tester,
  ) async {
    final room = _FakeRoom();
    final timeline = _timelineWith(room, eventCount: 60);

    await tester.pumpWidget(_host(timeline));
    await tester.pump();

    final mounted = tester
        .stateList<TimelineViewEntryState>(find.byType(TimelineViewEntry))
        .toList();
    expect(mounted, isNotEmpty);

    final before = mounted.map((e) => e.eventUpdateRevision).toList();

    room.emitUpdate();
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (var i = 0; i < mounted.length; i++) {
      expect(
        mounted[i].eventUpdateRevision,
        greaterThan(before[i]),
        reason:
            'entry $i was not refreshed by a room update; onRoomUpdated is '
            'documented here as refreshing every mounted entry',
      );
    }
  });

  testWidgets(
    'room update fan-out is bounded by the viewport, not by history',
    (tester) async {
      // Two long timelines in an identical viewport, each given exactly one
      // room update. Counting mounted rows instead would measure the sliver's
      // laziness and nothing else - the fan-out is how many of those rows the
      // update actually refreshes.
      //
      // BOTH histories are past the sliver's mount window, and that is what
      // makes the comparison mean anything. A 60-event timeline mounts all 60,
      // so it refreshes exactly 60 and reports its own history length rather
      // than the viewport bound; measured against 2000 it differs (60 vs 100)
      // for a reason that is not the property under test. Comparing two
      // histories that are both past the window isolates it.
      final mediumRefreshed = await _entriesRefreshedByOneUpdate(
        tester,
        room: _FakeRoom(),
        eventCount: 500,
      );
      final deepRefreshed = await _entriesRefreshedByOneUpdate(
        tester,
        room: _FakeRoom(),
        eventCount: 2000,
      );

      expect(
        mediumRefreshed,
        greaterThan(0),
        reason:
            'no entry was refreshed at all, so this test is measuring nothing',
      );
      expect(
        deepRefreshed,
        equals(mediumRefreshed),
        reason:
            'the number of refreshed entries - and so the number of setState '
            'calls one sync triggers - must not grow with loaded history',
      );
      expect(
        mediumRefreshed,
        lessThan(500),
        reason:
            'the sliver must stay lazy. Asserted against the SMALLER history: '
            'a fan-out that already equals 500 is the unbounded case, and '
            'bounding it by 2000 instead would let it grow four times over '
            'before this noticed',
      );
    },
  );
}

/// Mounts a timeline of [eventCount] events on [room], emits ONE room update,
/// and returns how many mounted entries that update refreshed.
///
/// The count is taken from `eventUpdateRevision`, which `update()` increments
/// inside its own `setState`, so it is a direct count of the rebuilds one sync
/// costs rather than a count of what happened to be on screen.
Future<int> _entriesRefreshedByOneUpdate(
  WidgetTester tester, {
  required _FakeRoom room,
  required int eventCount,
}) async {
  await tester.pumpWidget(_host(_timelineWith(room, eventCount: eventCount)));
  await tester.pump();

  final mounted = tester
      .stateList<TimelineViewEntryState>(find.byType(TimelineViewEntry))
      .toList();
  final before = mounted.map((entry) => entry.eventUpdateRevision).toList();

  room.emitUpdate();
  await tester.pump();
  expect(tester.takeException(), isNull);

  var refreshed = 0;
  for (var i = 0; i < mounted.length; i++) {
    if (mounted[i].eventUpdateRevision > before[i]) {
      refreshed++;
    }
  }
  return refreshed;
}

Widget _host(Timeline timeline) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      // The width the desktop call-room chat side rail uses.
      width: 340,
      height: 500,
      // Keyed by the timeline. `RoomTimelineWidgetViewState` reads
      // `widget.timeline` once, in initState, and `didUpdateWidget` never
      // re-reads it - so pumping a second host without a key change keeps the
      // FIRST timeline mounted and any comparison between the two measures one
      // timeline twice.
      child: RoomTimelineWidgetView(
        key: ObjectKey(timeline),
        timeline: timeline,
      ),
    ),
  ),
);

_FakeTimeline _timelineWith(_FakeRoom room, {required int eventCount}) {
  final timeline = _FakeTimeline(room: room);
  for (var i = 0; i < eventCount; i++) {
    timeline.events.add(
      _FakeTextEvent(
        eventId: 'event-$i',
        senderId: '@alice:example.org',
        originServerTs: DateTime.utc(2026, 8, 20, 12).add(Duration(seconds: i)),
        body: 'message $i',
      ),
    );
  }
  return timeline;
}

class _FakeReceipts implements ReadReceiptComponent {
  @override
  Stream<String> get onReadReceiptsUpdated => const Stream<String>.empty();

  @override
  List<String>? getReceipts(TimelineEvent event) => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  Profile? self = const _FakeProfile('@self:example.org');

  @override
  String get identifier => 'fake-client';

  @override
  bool get supportsE2EE => true;

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRoom implements Room {
  final StreamController<void> _controller = StreamController<void>.broadcast();
  final _FakeReceipts _receipts = _FakeReceipts();

  /// Stands in for `MatrixRoom.onRoomSyncUpdate` firing `_onUpdate`.
  void emitUpdate() => _controller.add(null);

  @override
  String get identifier => '!call-room:example.org';

  @override
  final Client client = _FakeClient();

  @override
  String get localId => 'fake-client:!call-room:example.org';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => _controller.stream;

  @override
  Permissions get permissions => _FakePermissions();

  @override
  T? getComponent<T extends RoomComponent>() {
    if (T == ReadReceiptComponent) {
      return _receipts as T;
    }
    return null;
  }

  @override
  Member getMemberOrFallback(String id) => _FakeMember(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {}

class _FakeTimeline extends Timeline {
  _FakeTimeline({required Room room}) {
    this.room = room;
    client = room.client;
    events = List<TimelineEvent>.empty(growable: true);
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

class _FakeMember implements Member {
  const _FakeMember(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Alice';

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.teal;
}

class _FakeProfile implements Profile {
  const _FakeProfile(this.identifier);

  @override
  final String identifier;

  @override
  String get userName => identifier;

  @override
  String get displayName => 'Self';

  @override
  String? get detail => null;

  @override
  ImageProvider? get avatar => null;

  @override
  ImageProvider? get banner => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  String get source => '{}';
}

class _FakeTextEvent implements TimelineEventMessage {
  _FakeTextEvent({
    required this.eventId,
    required this.senderId,
    required this.originServerTs,
    required String body,
  }) : _body = body;

  final String _body;

  @override
  final String eventId;

  @override
  final String senderId;

  @override
  final DateTime originServerTs;

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
  Widget? buildFormattedContent({Timeline? timeline}) => null;

  @override
  String getPlaintextBody(Timeline timeline) => plainTextBody;

  @override
  bool isEdited(Timeline timeline) => false;

  @override
  List<Uri>? getLinks({Timeline? timeline}) => const [];
}
