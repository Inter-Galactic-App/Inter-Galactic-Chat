import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/inbox/inbox_query.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  test(
    'Inbox marker clears room and Favorites counts only after success',
    () async {
      final fixture = _Fixture();
      final updates = <void>[];
      final subscription = fixture.room.onUpdate.listen(updates.add);
      final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
      await fixture.sdkRoom.markerStarted.future;

      expect(fixture.sdkRoom.markedEventId, r'$old');
      expect(fixture.room.notificationCount, 3);
      expect(fixture.room.highlightedNotificationCount, 1);

      fixture.sdkRoom.completeMarker();
      await pending;

      expect(fixture.room.notificationCount, 0);
      expect(fixture.room.highlightedNotificationCount, 0);
      expect(await fixture.room.getInboxSnapshot(), isNull);
      expect(updates, hasLength(1));
      await subscription.cancel();
      await fixture.room.close();
    },
  );

  test('newer notification during marker request stays unread', () async {
    final fixture = _Fixture();
    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;

    fixture.sdkRoom.notificationCount = 4;
    fixture.sdkRoom.highlightCount = 2;
    fixture.sdkRoom.completeMarker();
    await pending;

    expect(fixture.sdkRoom.markedEventId, r'$old');
    expect(fixture.room.notificationCount, 1);
    expect(fixture.room.highlightedNotificationCount, 1);
    fixture.sdkClient.database.events = [
      fixture.sdkRoom.newerEvent,
      fixture.sdkRoom.oldEvent,
    ];
    final snapshot = await fixture.room.getInboxSnapshot();
    expect(snapshot?.newestUnreadEvent.eventId, r'$new');
    expect(snapshot?.newestDirectMention, isNull);
    await fixture.room.close();
  });

  test(
    'a frozen Inbox target does not clear an already newer notification',
    () async {
      final fixture = _Fixture();
      fixture.sdkRoom.notificationCount = 4;
      fixture.sdkClient.database.events = [
        fixture.sdkRoom.newerEvent,
        fixture.sdkRoom.oldEvent,
      ];
      fixture.room.onNotification(fixture.sdkRoom.newerEvent);

      final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
      await fixture.sdkRoom.markerStarted.future;
      fixture.sdkRoom.completeMarker();
      await pending;

      expect(fixture.room.notificationCount, 1);
      await fixture.room.close();
    },
  );

  test('same-millisecond newer notification stays unread', () async {
    final fixture = _Fixture();
    final newer = fixture.sdkRoom.newerEventAtSameTimestamp;
    fixture.sdkClient.database.events = [newer, fixture.sdkRoom.oldEvent];
    fixture.sdkRoom.notificationCount = 4;
    fixture.room.onNotification(newer);

    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;
    fixture.sdkRoom.completeMarker();
    await pending;

    expect(fixture.sdkRoom.markedEventId, r'$old');
    expect(fixture.room.notificationCount, 1);
    await fixture.room.close();
  });

  test(
    'same-millisecond cached message stays visible without callback',
    () async {
      final fixture = _Fixture();
      fixture.sdkClient.database.events = [
        fixture.sdkRoom.newerEventAtSameTimestamp,
        fixture.sdkRoom.oldEvent,
      ];
      fixture.sdkRoom.notificationCount = 4;

      final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
      await fixture.sdkRoom.markerStarted.future;
      fixture.sdkRoom.completeMarker();
      await pending;

      expect(fixture.room.notificationCount, 1);
      await fixture.room.close();
    },
  );

  test(
    'a newer synced count survives without a local notification callback',
    () async {
      final fixture = _Fixture();
      final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
      await fixture.sdkRoom.markerStarted.future;
      fixture.sdkRoom.completeMarker();
      await pending;

      fixture.sdkRoom.lastEventValue = fixture.sdkRoom.newerEvent;
      fixture.sdkRoom.notificationCount = 1;
      expect(fixture.room.notificationCount, 1);
      await fixture.room.close();
    },
  );

  test('same-millisecond newer mention keeps highlight count', () async {
    final fixture = _Fixture();
    final newer = fixture.sdkRoom.newerMentionAtSameTimestamp;
    fixture.sdkClient.database.events = [newer, fixture.sdkRoom.oldEvent];
    fixture.sdkRoom.notificationCount = 4;
    fixture.sdkRoom.highlightCount = 2;
    fixture.room.onNotification(newer);

    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;
    fixture.sdkRoom.completeMarker();
    await pending;

    expect(fixture.room.notificationCount, 1);
    expect(fixture.room.highlightedNotificationCount, 1);
    await fixture.room.close();
  });

  test('same-millisecond older notification remains marked read', () async {
    final fixture = _Fixture();
    final older = fixture.sdkRoom.olderEventAtSameTimestamp;
    fixture.sdkClient.database.events = [fixture.sdkRoom.oldEvent, older];
    fixture.room.onNotification(older);

    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;
    fixture.sdkRoom.completeMarker();
    await pending;

    expect(fixture.room.notificationCount, 0);
    fixture.room.onNotification(older);
    expect(fixture.room.notificationCount, 0);
    await fixture.room.close();
  });

  test('failed marker leaves unread counts and retry state visible', () async {
    final fixture = _Fixture();
    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;

    final failure = expectLater(pending, throwsStateError);
    fixture.sdkRoom.failMarker();
    await failure;

    expect(fixture.room.notificationCount, 3);
    expect(fixture.room.highlightedNotificationCount, 1);
    await fixture.room.close();
  });

  test(
    'pre-marker sync cannot retire projection; confirmed sync can',
    () async {
      final fixture = _Fixture();
      fixture.sdkRoom.fullyRead = r'$before';
      final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
      await fixture.sdkRoom.markerStarted.future;
      fixture.sdkRoom.completeMarker();
      await pending;

      fixture.sdkRoom.fullyRead = r'$before';
      fixture.room.onRoomSyncUpdate(
        fixture.syncUpdate(3, 1, markerEventId: r'$before'),
      );
      expect(fixture.room.notificationCount, 0);

      fixture.sdkRoom.notificationCount = 0;
      fixture.sdkRoom.highlightCount = 0;
      fixture.sdkRoom.fullyRead = r'$old';
      fixture.room.onRoomSyncUpdate(fixture.syncUpdate(0, 0));
      fixture.sdkRoom.notificationCount = 1;
      expect(fixture.room.notificationCount, 1);
      await fixture.room.close();
    },
  );

  test('partially reduced server count retires the projection', () async {
    final fixture = _Fixture();
    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;
    fixture.sdkRoom.completeMarker();
    await pending;
    expect(fixture.room.notificationCount, 0);

    fixture.sdkRoom.fullyRead = r'$old';
    fixture.sdkRoom.notificationCount = 1;
    fixture.sdkRoom.highlightCount = 0;
    fixture.room.onRoomSyncUpdate(fixture.syncUpdate(1, 0));
    expect(fixture.room.notificationCount, 1);
    fixture.sdkRoom.notificationCount = 2;
    expect(fixture.room.notificationCount, 2);
    await fixture.room.close();
  });

  test('a divergent synced marker retires the stale projection', () async {
    final fixture = _Fixture();
    fixture.sdkRoom.fullyRead = r'$before';
    final pending = fixture.room.markInboxSnapshotRead(fixture.snapshot);
    await fixture.sdkRoom.markerStarted.future;
    fixture.sdkRoom.completeMarker();
    await pending;
    expect(fixture.room.notificationCount, 0);

    fixture.sdkRoom.fullyRead = r'$other-device';
    fixture.room.onRoomSyncUpdate(
      fixture.syncUpdate(3, 1, markerEventId: r'$other-device'),
    );
    expect(fixture.room.notificationCount, 3);
    expect(fixture.room.highlightedNotificationCount, 1);
    await fixture.room.close();
  });

  test('room-row mark-as-read uses the exact synced timeline event', () async {
    final fixture = _Fixture();
    final pending = fixture.room.markAsRead();
    await fixture.sdkRoom.markerStarted.future;

    expect(fixture.sdkRoom.markedEventId, r'$old');
    fixture.sdkRoom.completeMarker();
    await pending;

    expect(fixture.room.notificationCount, 0);
    expect(fixture.sdkRoom.timeline.cancelCount, 1);
    await fixture.room.close();
  });

  test(
    'failed room-row marker preserves counts and cancels SDK timeline',
    () async {
      final fixture = _Fixture();
      final pending = fixture.room.markAsRead();
      await fixture.sdkRoom.markerStarted.future;

      final failure = expectLater(pending, throwsStateError);
      fixture.sdkRoom.failMarker();
      await failure;

      expect(fixture.room.notificationCount, 3);
      expect(fixture.sdkRoom.timeline.cancelCount, 1);
      await fixture.room.close();
    },
  );
}

class _Fixture {
  _Fixture() {
    sdkClient = _FakeSdkClient();
    sdkRoom = _FakeSdkRoom(sdkClient);
    sdkClient.database.events = [sdkRoom.oldEvent];
    room = MatrixRoom(_FakeMatrixClient(sdkClient), sdkRoom, sdkClient);
  }

  late final _FakeSdkClient sdkClient;
  late final _FakeSdkRoom sdkRoom;
  late final MatrixRoom room;

  InboxRoomSnapshot get snapshot => InboxRoomSnapshot(
    clientIdentifier: '@self:example.org',
    roomId: sdkRoom.id,
    roomName: 'Room',
    unreadCount: 3,
    isSidebarEligible: true,
    readTargetEventId: r'$old',
    newestUnreadEvent: InboxEventSnapshot(
      eventId: r'$old',
      timestamp: DateTime.utc(2026, 9, 23, 12),
      senderId: '@other:example.org',
      plainTextBody: 'old',
      isDirectMention: false,
    ),
  );

  matrix.SyncUpdate syncUpdate(
    int notifications,
    int highlights, {
    String? markerEventId,
  }) => matrix.SyncUpdate(
    nextBatch: 'next',
    rooms: matrix.RoomsUpdate(
      join: {
        sdkRoom.id: matrix.JoinedRoomUpdate(
          accountData: markerEventId == null
              ? null
              : [
                  matrix.BasicEvent(
                    type: 'm.fully_read',
                    content: {'event_id': markerEventId},
                  ),
                ],
          unreadNotifications: matrix.UnreadNotificationCounts(
            notificationCount: notifications,
            highlightCount: highlights,
          ),
        ),
      },
    ),
  );
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this.sdk);

  final _FakeSdkClient sdk;

  @override
  matrix.Client get matrixClient => sdk;

  @override
  bool get firstSyncComplete => false;

  @override
  String get identifier => '@self:example.org';

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  @override
  final _FakeDatabase database = _FakeDatabase();

  @override
  String get userID => '@self:example.org';

  @override
  final CachedStreamController<
    ({String roomId, matrix.StrippedStateEvent state})
  >
  onRoomState = CachedStreamController();

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  final CachedStreamController<matrix.Event> onTimelineEvent =
      CachedStreamController();

  @override
  final CachedStreamController<matrix.Event> onNotification =
      CachedStreamController();

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeDatabase implements matrix.DatabaseApi {
  List<matrix.Event> events = [];

  @override
  Future<List<matrix.Event>> getEventList(
    matrix.Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async => events;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkRoom implements matrix.Room {
  _FakeSdkRoom(this._client) {
    timeline = _FakeSdkTimeline(this);
  }

  final _FakeSdkClient _client;
  late final _FakeSdkTimeline timeline;
  final Completer<void> _marker = Completer<void>();
  final Completer<void> markerStarted = Completer<void>();
  String? markedEventId;
  matrix.Event? lastEventValue;

  matrix.Event get newerEvent => matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {'msgtype': 'm.text', 'body': 'new'},
    senderId: '@other:example.org',
    eventId: r'$new',
    originServerTs: DateTime.utc(2026, 9, 23, 13),
    room: this,
  );

  matrix.Event get newerEventAtSameTimestamp => matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {'msgtype': 'm.text', 'body': 'new'},
    senderId: '@other:example.org',
    eventId: r'$new',
    originServerTs: DateTime.utc(2026, 9, 23, 12),
    room: this,
  );

  matrix.Event get olderEventAtSameTimestamp => matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {'msgtype': 'm.text', 'body': 'older'},
    senderId: '@other:example.org',
    eventId: r'$older',
    originServerTs: DateTime.utc(2026, 9, 23, 12),
    room: this,
  );

  matrix.Event get newerMentionAtSameTimestamp => matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {
      'msgtype': 'm.text',
      'body': 'new mention',
      'm.mentions': {
        'user_ids': ['@self:example.org'],
      },
    },
    senderId: '@other:example.org',
    eventId: r'$new-mention',
    originServerTs: DateTime.utc(2026, 9, 23, 12),
    room: this,
  );

  matrix.Event get oldEvent => matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {
      'msgtype': 'm.text',
      'body': 'old',
      'm.mentions': {
        'user_ids': ['@self:example.org'],
      },
    },
    senderId: '@other:example.org',
    eventId: r'$old',
    originServerTs: DateTime.utc(2026, 9, 23, 12),
    room: this,
  );

  @override
  int notificationCount = 3;

  @override
  int highlightCount = 1;

  @override
  String fullyRead = '';

  @override
  matrix.LatestReceiptState get receiptState =>
      matrix.LatestReceiptState.empty();

  @override
  String get id => '!room:example.org';

  @override
  String get name => 'Room';

  @override
  matrix.Client get client => _client;

  @override
  String getLocalizedDisplayname([dynamic i18n, dynamic fallback]) => 'Room';

  @override
  matrix.Event? get lastEvent => lastEventValue;

  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> get states => const {};

  @override
  Map<String, matrix.BasicEvent> get roomAccountData => const {};

  @override
  bool get encrypted => false;

  @override
  matrix.Membership get membership => matrix.Membership.join;

  @override
  bool get isSpace => false;

  @override
  bool get isDirectChat => false;

  @override
  Uri? get avatar => null;

  @override
  Future<void> postLoad() async {}

  @override
  Future<matrix.Timeline> getTimeline({
    void Function(int)? onChange,
    void Function(int)? onRemove,
    void Function(int)? onInsert,
    void Function()? onNewEvent,
    void Function()? onUpdate,
    String? eventContextId,
    int? limit = matrix.Room.defaultHistoryCount,
  }) async => timeline;

  @override
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async {
    markedEventId = eventId;
    markerStarted.complete();
    await _marker.future;
  }

  void completeMarker() => _marker.complete();

  void failMarker() => _marker.completeError(StateError('marker failed'));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkTimeline implements matrix.Timeline {
  _FakeSdkTimeline(this.room);

  @override
  final _FakeSdkRoom room;

  int cancelCount = 0;

  @override
  List<matrix.Event> get events => [room.oldEvent];

  @override
  Future<void> setReadMarker({String? eventId, bool? public}) =>
      room.setReadMarker(eventId, mRead: eventId, public: public);

  @override
  void cancelSubscriptions() => cancelCount++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
