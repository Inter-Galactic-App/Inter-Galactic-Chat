import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/matrix/components/server_discovery/matrix_server_discovery_service.dart';

void main() {
  test('queries account-local directory without remote server parameter', () {
    final scope = ServerDiscoveryScope(
      accountId: '@nick:ourgalaxy.space',
      homeserver: 'ourgalaxy.space',
      baseUrl: Uri.parse('https://matrix.ourgalaxy.space'),
    );

    expect(
      MatrixServerDiscoveryService.directoryServerParameterForScope(scope),
      isNull,
    );
  });

  test('knock routing prefers canonical alias and keeps via hints', () {
    const scope = ServerDiscoveryScope(
      accountId: '@nick:ourgalaxy.space',
      homeserver: 'ourgalaxy.space',
    );
    final entry = ServerDiscoveryEntry.fromDirectory(
      roomId: '!room:remote.example',
      roomType: null,
      name: 'Knock room',
      topic: null,
      avatarUrl: null,
      memberCount: 2,
      canonicalAlias: '#knock:alias.example',
      joinRule: 'knock',
      alreadyJoined: false,
      sourceAccountId: scope.accountId,
      worldReadable: false,
      guestCanJoin: false,
    );

    expect(
      MatrixServerDiscoveryService.directoryEntryAddress(entry),
      '#knock:alias.example',
    );
    expect(MatrixServerDiscoveryService.directoryEntryVia(entry, scope), [
      'ourgalaxy.space',
      'alias.example',
      'remote.example',
    ]);
  });

  test('directory routing prefers entry via hints before derived servers', () {
    const scope = ServerDiscoveryScope(
      accountId: '@nick:ourgalaxy.space',
      homeserver: 'ourgalaxy.space',
    );
    final entry = ServerDiscoveryEntry.fromSpaceChild(
      roomId: '!room:remote.example',
      roomType: null,
      name: 'Restricted child',
      topic: null,
      avatarUrl: null,
      memberCount: 2,
      canonicalAlias: null,
      joinRule: 'restricted',
      alreadyJoined: false,
      sourceAccountId: scope.accountId,
      worldReadable: false,
      guestCanJoin: false,
      via: const ['space.example', 'ourgalaxy.space'],
    );

    expect(MatrixServerDiscoveryService.directoryEntryVia(entry, scope), [
      'space.example',
      'ourgalaxy.space',
      'remote.example',
    ]);
  });

  test('directory routing preserves Matrix identifier homeserver ports', () {
    const scope = ServerDiscoveryScope(
      accountId: '@nick:ourgalaxy.space:443',
      homeserver: 'ourgalaxy.space:443',
    );
    final entry = ServerDiscoveryEntry.fromDirectory(
      roomId: '!room:remote.example:8448',
      roomType: null,
      name: 'Port room',
      topic: null,
      avatarUrl: null,
      memberCount: 2,
      canonicalAlias: '#port:alias.example:8448',
      joinRule: 'public',
      alreadyJoined: false,
      sourceAccountId: scope.accountId,
      worldReadable: false,
      guestCanJoin: false,
    );

    expect(MatrixServerDiscoveryService.directoryEntryVia(entry, scope), [
      'ourgalaxy.space:443',
      'alias.example:8448',
      'remote.example:8448',
    ]);
  });

  test(
    'knock routing falls back to room id server names without duplicates',
    () {
      const scope = ServerDiscoveryScope(
        accountId: '@nick:ourgalaxy.space',
        homeserver: 'ourgalaxy.space',
      );
      final entry = ServerDiscoveryEntry.fromDirectory(
        roomId: '!room:ourgalaxy.space',
        roomType: null,
        name: 'Knock room',
        topic: null,
        avatarUrl: null,
        memberCount: 2,
        canonicalAlias: null,
        joinRule: 'knock_restricted',
        alreadyJoined: false,
        sourceAccountId: scope.accountId,
        worldReadable: false,
        guestCanJoin: false,
      );

      expect(
        MatrixServerDiscoveryService.directoryEntryAddress(entry),
        '!room:ourgalaxy.space',
      );
      expect(MatrixServerDiscoveryService.directoryEntryVia(entry, scope), [
        'ourgalaxy.space',
      ]);
    },
  );

  test('tracked knock records the canonical id after alias routing', () async {
    final calls = <String>[];

    await sendTrackedServerDiscoveryKnock(
      roomId: '!room:remote.example',
      address: '#knock:alias.example',
      via: const ['alias.example'],
      requestKnock: (address, {via}) async {
        calls.add('request:$address:${via!.join(',')}');
      },
      recordOutstandingKnock: (roomId) async {
        calls.add('track:$roomId');
      },
    );

    expect(calls, [
      'request:#knock:alias.example:alias.example',
      'track:!room:remote.example',
    ]);
  });

  test('tracked knock does not record when the request fails', () async {
    final recorded = <String>[];

    await expectLater(
      sendTrackedServerDiscoveryKnock(
        roomId: '!room:remote.example',
        address: '#knock:alias.example',
        via: const ['alias.example'],
        requestKnock: (address, {via}) async {
          throw StateError('knock failed');
        },
        recordOutstandingKnock: (roomId) async {
          recorded.add(roomId);
        },
      ),
      throwsStateError,
    );

    expect(recorded, isEmpty);
  });
}
