// The Android background-startup fix has two halves. MatrixBackgroundClient's
// early return is compiler-enforced - deleting it fails the build - but
// BackgroundNotificationsManager2's `if (!client.isInitialized) continue;` was
// guarded by nothing: removing it left the suite green while the app went on to
// register a client that cannot answer anything.
//
// The committed matrix_background_client_init_test.dart covers only the pure
// predicate and never constructs a client, so it cannot see this skip.

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';
import 'package:intergalactic/client/matrix_background/matrix_background_client.dart';
import 'package:intergalactic/service/background_service_notifications/background_service_task_notification2.dart';

/// Models only what `ClientManager.addClient` reads, plus [isInitialized].
///
/// Everything else throws through [noSuchMethod] rather than answering
/// plausibly, so a test that drifts into unmodelled behaviour fails loudly.
class _FakeBackgroundClient implements MatrixBackgroundClient {
  _FakeBackgroundClient({
    required this.identifier,
    required this.isInitialized,
  });

  @override
  final String identifier;

  @override
  final bool isInitialized;

  @override
  Profile? self;

  @override
  List<Room> get rooms => const [];

  @override
  List<Room> get singleRooms => const [];

  @override
  List<Space> get spaces => const [];

  @override
  Stream<void> get onSelfUpdated => const Stream<void>.empty();

  @override
  Stream<void> get onSync => const Stream<void>.empty();

  @override
  Stream<int> get onRoomAdded => const Stream<int>.empty();

  @override
  Stream<int> get onRoomRemoved => const Stream<int>.empty();

  @override
  Stream<int> get onSpaceAdded => const Stream<int>.empty();

  @override
  Stream<int> get onSpaceRemoved => const Stream<int>.empty();

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw UnimplementedError(
      '_FakeBackgroundClient does not model ${invocation.memberName}.',
    );
  }
}

void main() {
  late BackgroundNotificationsManager2 manager;

  setUp(() {
    manager = BackgroundNotificationsManager2(null);
  });

  Future<ClientManager> addAll(Map<String, bool> initialisedById) async {
    final clientManager = ClientManager();
    await manager.addInitializedBackgroundClients(
      clientManager,
      initialisedById.keys,
      createClient: (id) async => _FakeBackgroundClient(
        identifier: id,
        isInitialized: initialisedById[id]!,
      ),
    );
    return clientManager;
  }

  test(
    'a registered id whose account never initialised is not added',
    () async {
      final clientManager = await addAll({'no-stored-account': false});

      expect(clientManager.clients, isEmpty);
    },
  );

  test('an initialised client is added', () async {
    final clientManager = await addAll({'usable': true});

    expect(
      clientManager.clients.map((client) => client.identifier),
      ['usable'],
      reason:
          'the positive control - without it the first test passes for a '
          'client that was never added for some unrelated reason',
    );
  });

  test('one unusable account does not stop the others being added', () async {
    final clientManager = await addAll({
      'usable-first': true,
      'no-stored-account': false,
      'usable-last': true,
    });

    expect(
      clientManager.clients.map((client) => client.identifier),
      ['usable-first', 'usable-last'],
      reason: 'the skip must continue the loop, not abandon it',
    );
  });
}
