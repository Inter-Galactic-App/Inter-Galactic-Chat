// The Matrix half of the call-session surface.
//
// `MatrixLivekitVoipSession` takes a `MatrixRoom` alongside its `lk.Room`, and
// touches a narrow slice of it: the app-level `Client` (for the teardown
// barrier key and the local user id), the Matrix SDK `Room`/`Client` (for the
// delayed-event heartbeat and the call-member state clear), and member display
// names for the call-health snapshot.
//
// Everything outside that slice routes to `noSuchMethod` and throws, so a test
// that wanders into unmodelled territory fails loudly rather than reading a
// plausible default.

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/member.dart';
import 'package:matrix/matrix.dart' as matrix;

/// A room-state write recorded by [FakeCallMatrixSdkClient].
class RecordedRoomStateWrite {
  const RecordedRoomStateWrite({
    required this.roomId,
    required this.eventType,
    required this.stateKey,
    required this.body,
  });

  final String roomId;
  final String eventType;
  final String stateKey;
  final Map<String, Object?> body;

  bool get isClear => body.isEmpty;
}

/// A raw `Client.request` recorded by [FakeCallMatrixSdkClient].
class RecordedMatrixRequest {
  const RecordedMatrixRequest({required this.method, required this.path});

  final String method;
  final String path;
}

class FakeCallProfile implements Profile {
  FakeCallProfile(this.identifier, {String? displayName})
    : displayName = displayName ?? identifier;

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => identifier;

  @override
  String? get detail => null;

  @override
  String get source => 'fake';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCallMember implements Member {
  FakeCallMember(this.identifier, {String? displayName})
    : displayName = displayName ?? identifier;

  @override
  final String identifier;

  @override
  final String displayName;

  @override
  String get userName => identifier;

  @override
  String? get detail => null;

  @override
  String? get avatarId => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// App-level `Client`. `identifier` is the key the process-global
/// `LiveKitRoomTeardownBarrier` quarantines on, so tests that exercise
/// teardown should give each client its own value and reset the barrier.
class FakeCallClient implements Client {
  FakeCallClient({this.identifier = 'client-a', String? selfUserId})
    : self = FakeCallProfile(selfUserId ?? '@alice:example.org');

  @override
  final String identifier;

  @override
  Profile? self;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Matrix SDK `Client`. Only the three calls the session makes are modelled.
class FakeCallMatrixSdkClient implements matrix.Client {
  FakeCallMatrixSdkClient({
    this.deviceID = 'DEVICE',
    this.userID = '@alice:example.org',
    this.supportsDelayedEvents = false,
  });

  @override
  final String? deviceID;

  @override
  final String? userID;

  /// When false, `startHeartbeat` logs "Homeserver does not support delayed
  /// events" and returns before issuing any request - the quiet path a test
  /// usually wants.
  final bool supportsDelayedEvents;

  final List<RecordedRoomStateWrite> roomStateWrites =
      <RecordedRoomStateWrite>[];
  final List<RecordedMatrixRequest> requests = <RecordedMatrixRequest>[];

  @override
  Future<matrix.GetVersionsResponse> getVersions({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async {
    return matrix.GetVersionsResponse(
      versions: const <String>['v1.11'],
      unstableFeatures: supportsDelayedEvents
          ? const <String, bool>{'org.matrix.msc4140': true}
          : null,
    );
  }

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    roomStateWrites.add(
      RecordedRoomStateWrite(
        roomId: roomId,
        eventType: eventType,
        stateKey: stateKey,
        body: body,
      ),
    );
    return '\$fake-event-${roomStateWrites.length}';
  }

  @override
  Future<Map<String, Object?>> request(
    matrix.RequestType type,
    String action, {
    dynamic data = '',
    String contentType = 'application/json',
    Map<String, Object?>? query,
  }) async {
    requests.add(RecordedMatrixRequest(method: type.name, path: action));
    return <String, Object?>{'delay_id': 'fake-delay-id'};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Matrix SDK `Room`.
class FakeCallMatrixSdkRoom implements matrix.Room {
  FakeCallMatrixSdkRoom({required this.id, required this.client});

  @override
  final String id;

  @override
  final matrix.Client client;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// App-level `MatrixRoom` wired to the two Matrix SDK fakes above.
class FakeCallMatrixRoom implements MatrixRoom {
  FakeCallMatrixRoom({
    String roomId = '!call:example.org',
    Client? client,
    FakeCallMatrixSdkClient? matrixClient,
    Map<String, String> memberDisplayNames = const <String, String>{},
  }) : identifier = roomId,
       client = client ?? FakeCallClient(),
       matrixRoom = FakeCallMatrixSdkRoom(
         id: roomId,
         client: matrixClient ?? FakeCallMatrixSdkClient(),
       ),
       _memberDisplayNames = Map<String, String>.of(memberDisplayNames);

  @override
  final String identifier;

  @override
  final Client client;

  @override
  final matrix.Room matrixRoom;

  final Map<String, String> _memberDisplayNames;

  FakeCallMatrixSdkClient get sdkClient =>
      matrixRoom.client as FakeCallMatrixSdkClient;

  @override
  Member getMemberOrFallback(String id) =>
      FakeCallMember(id, displayName: _memberDisplayNames[id]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
