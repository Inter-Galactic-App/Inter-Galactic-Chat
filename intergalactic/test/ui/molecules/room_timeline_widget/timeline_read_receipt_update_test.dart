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

/// Read receipts name events the open timeline has not loaded. A remote user's
/// marker sits wherever they last read, and `m.receipt` also replays each
/// user's previous marker - either can be older than the oldest loaded event.
///
/// This is felt hardest in a voice room's chat side rail, which is opened onto
/// a single freshly loaded page and then left open while other participants
/// come and go, but nothing about it is voice specific.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('a receipt for an event outside the loaded window is dropped', (
    tester,
  ) async {
    final receipts = _FakeReceipts();
    final timeline = _timelineWith(receipts);

    await tester.pumpWidget(_host(timeline));
    await tester.pump();

    expect(find.byType(TimelineViewEntry), findsOneWidget);

    receipts.emit(r'$never-loaded');
    await tester.pump();

    // Two separate failures used to reach here: `Bad state: No element` from
    // the unguarded key lookup, and a rebuild at index -1 behind it.
    expect(tester.takeException(), isNull);
    expect(find.byType(TimelineViewEntry), findsOneWidget);
  });

  testWidgets('a receipt for a loaded event still refreshes its row', (
    tester,
  ) async {
    final receipts = _FakeReceipts();
    final timeline = _timelineWith(receipts);

    await tester.pumpWidget(_host(timeline));
    await tester.pump();

    final entry = tester.state<TimelineViewEntryState>(
      find.byType(TimelineViewEntry),
    );
    final revisionBefore = entry.eventUpdateRevision;

    receipts.emit(r'$loaded');
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      entry.eventUpdateRevision,
      greaterThan(revisionBefore),
      reason: 'the loaded row was not refreshed for its own receipt',
    );
  });
}

Widget _host(Timeline timeline) => MaterialApp(
  home: Scaffold(
    body: SizedBox(
      // The width the desktop call-room chat side rail uses.
      width: 340,
      height: 500,
      child: RoomTimelineWidgetView(timeline: timeline),
    ),
  ),
);

_FakeTimeline _timelineWith(ReadReceiptComponent receipts) {
  final room = _FakeRoom(
    identifier: '!call-room:example.org',
    client: _FakeClient(),
    receipts: receipts,
  );
  return _FakeTimeline(room: room)
    ..events = [
      _FakeTextEvent(
        eventId: r'$loaded',
        senderId: '@alice:example.org',
        originServerTs: DateTime.utc(2026, 8, 20, 12),
        body: 'loaded message',
      ),
    ];
}

class _FakeReceipts implements ReadReceiptComponent {
  final StreamController<String> _controller =
      StreamController<String>.broadcast();

  void emit(String eventId) => _controller.add(eventId);

  @override
  Stream<String> get onReadReceiptsUpdated => _controller.stream;

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
  _FakeRoom({
    required this.identifier,
    required this.client,
    required this.receipts,
  });

  @override
  final String identifier;

  @override
  final Client client;

  final ReadReceiptComponent receipts;

  @override
  String get localId => '${client.identifier}:$identifier';

  @override
  bool get shouldPreviewMedia => false;

  @override
  Stream<void> get onUpdate => const Stream<void>.empty();

  @override
  Permissions get permissions => _FakePermissions();

  @override
  T? getComponent<T extends RoomComponent>() {
    if (T == ReadReceiptComponent) {
      return receipts as T;
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
