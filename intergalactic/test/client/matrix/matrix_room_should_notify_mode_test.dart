import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/timeline_events/matrix_timeline_event.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// REVIEW finding, 2026-09-06: the per-account fix was real and undefended.
///
/// `MatrixRoom.shouldNotify` used to read the DEVICE-WIDE
/// `preferences.notificationMode` raw, so muting one account silenced local
/// notifications for every other signed-in account. The fix routes it through
/// `resolveNotificationMode`, which resolves the SERVER master rule per account.
///
/// `notification_mode_policy_test.dart` pins the resolver, and REVIEW showed
/// that is not enough: reverting `_effectiveNotificationMode` to a raw
/// preference read left 445 tests green, because nothing reached the CALL SITE
/// where the device-wide read actually lived.
///
/// These two cases drive `shouldNotify` itself, against the SAME device-wide
/// stored `mute` for both accounts - the situation that produced the bug - and
/// both fail against that revert.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    // The device-wide leftover. Account A chose mute, so this is what BOTH
    // accounts' rooms read if the call site consults it directly.
    await globals.preferences.notificationMode.set('mute');
    await globals.preferences.enableNotifications.set(true);
  });

  MatrixRoom roomFor({
    required String accountId,
    required bool serverMuted,
    required bool migrated,
  }) {
    final sdkClient = _FakeSdkClient(allMuted: serverMuted);
    final sdkRoom = _FakeSdkRoom(sdkClient);
    final client = _FakeMatrixClient(identifier: accountId, sdk: sdkClient);
    if (migrated) {
      globals.preferences.markGlobalMutePushRuleMigrated(accountId);
    }
    return MatrixRoom(client, sdkRoom, sdkClient);
  }

  test('a migrated account muted on the server does not notify', () async {
    final room = roomFor(
      accountId: '@a:example.org',
      serverMuted: true,
      migrated: true,
    );

    expect(
      room.shouldNotify(_mentionEvent(room.client as MatrixClient)),
      isFalse,
    );
  });

  test('a second migrated account on the same device still notifies', () async {
    final room = roomFor(
      accountId: '@b:example.org',
      serverMuted: false,
      migrated: true,
    );

    expect(
      room.shouldNotify(_mentionEvent(room.client as MatrixClient)),
      isTrue,
      reason:
          'the stored device-wide mute belongs to the other account; reading '
          'it here is the regression this pins',
    );
  });
}

/// An @room mention, which `shouldNotify` answers before it reaches the push
/// rule evaluator - so these cases exercise the mode decision and nothing else.
MatrixTimelineEvent _mentionEvent(MatrixClient client) => _FakeTimelineEvent(
  matrix.Event(
    type: matrix.EventTypes.Message,
    content: const {
      'msgtype': 'm.text',
      'body': 'hello',
      'm.mentions': {'room': true},
    },
    senderId: '@someone-else:example.org',
    eventId: r'$event:example.org',
    originServerTs: DateTime.now(),
    room: _FakeSdkRoom(_FakeSdkClient(allMuted: false)),
  ),
  client: client,
);

class _FakeTimelineEvent extends MatrixTimelineEvent {
  _FakeTimelineEvent(super.event, {required super.client});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient({required this.identifier, required this.sdk});

  @override
  final String identifier;

  final _FakeSdkClient sdk;

  @override
  bool get firstSyncComplete => true;

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  matrix.Client get matrixClient => sdk;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient({required this.allMuted});

  final bool allMuted;

  @override
  bool get allPushNotificationsMuted => allMuted;

  // MatrixRoom's constructor subscribes to all three of these, so they have to
  // be real controllers rather than noSuchMethod nulls.
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

class _FakeSdkRoom implements matrix.Room {
  _FakeSdkRoom(this._client);

  final matrix.Client _client;

  @override
  String get id => '!room:example.org';

  @override
  matrix.Client get client => _client;

  @override
  String getLocalizedDisplayname([dynamic i18n, dynamic _]) => 'Room';

  @override
  matrix.Event? get lastEvent => null;

  // Read during construction by the emoticon component, via ComponentRegistry.
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
  Future<void> postLoad() async {}

  @override
  Uri? get avatar => null;

  @override
  bool get isDirectChat => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
