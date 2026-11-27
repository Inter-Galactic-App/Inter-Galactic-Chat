import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';

void main() {
  test('classifies spaces from m.space room type', () {
    final entry = _entry(roomType: 'm.space');

    expect(entry.type, ServerDiscoveryEntryType.space);
    expect(entry.matchesFilter(ServerDiscoveryFilter.spaces), isTrue);
    expect(entry.matchesFilter(ServerDiscoveryFilter.rooms), isFalse);
  });

  test('classifies non-space room types as rooms', () {
    final entries = [
      _entry(roomType: null),
      _entry(roomType: 'chat.commet.calendar'),
      _entry(roomType: 'chat.intergalactic.app.forum'),
    ];

    expect(entries.map((entry) => entry.type).toSet(), {
      ServerDiscoveryEntryType.room,
    });
  });

  test('marks restricted space children as supplemental room entries', () {
    final entry = ServerDiscoveryEntry.fromSpaceChild(
      roomId: '!restricted:example',
      roomType: null,
      name: 'Restricted child',
      topic: null,
      avatarUrl: null,
      memberCount: 4,
      canonicalAlias: null,
      joinRule: 'restricted',
      alreadyJoined: false,
      sourceAccountId: '@alice:example',
      worldReadable: false,
      guestCanJoin: false,
      via: const ['example', 'example', 'remote.example'],
    );

    expect(entry.type, ServerDiscoveryEntryType.room);
    expect(entry.source, ServerDiscoveryEntrySource.spaceChild);
    expect(entry.joinRequirement, ServerDiscoveryJoinRequirement.restricted);
    expect(entry.via, ['example', 'remote.example']);
  });

  test('maps join rules to user action requirements', () {
    expect(_entry(joinRule: null).joinRequirement,
        ServerDiscoveryJoinRequirement.publicJoin);
    expect(_entry(joinRule: 'public').joinRequirement,
        ServerDiscoveryJoinRequirement.publicJoin);
    expect(_entry(joinRule: 'knock').joinRequirement,
        ServerDiscoveryJoinRequirement.knockRequired);
    expect(_entry(joinRule: 'knock_restricted').joinRequirement,
        ServerDiscoveryJoinRequirement.knockRequired);
    expect(_entry(joinRule: 'invite').joinRequirement,
        ServerDiscoveryJoinRequirement.inviteRequired);
    expect(_entry(joinRule: 'restricted').joinRequirement,
        ServerDiscoveryJoinRequirement.restricted);
    expect(_entry(joinRule: 'private').joinRequirement,
        ServerDiscoveryJoinRequirement.inviteRequired);
    expect(_entry(joinRule: 'custom').joinRequirement,
        ServerDiscoveryJoinRequirement.unsupported);
  });

  test('already joined entries do not request another join flow', () {
    final entry = _entry(alreadyJoined: true);

    expect(entry.joinRequirement, ServerDiscoveryJoinRequirement.alreadyJoined);
  });

  test('stale entries with empty room ids are unavailable', () {
    final entry = _entry(roomId: '');

    expect(entry.joinRequirement, ServerDiscoveryJoinRequirement.unavailable);
  });

  test('cache keys isolate account and homeserver', () {
    const request = ServerDiscoveryRequest(query: 'games');
    const keyA = ServerDiscoveryCacheKey(
      scope: ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      request: request,
    );
    const keyB = ServerDiscoveryCacheKey(
      scope: ServerDiscoveryScope(
        accountId: '@b:two.example',
        homeserver: 'two.example',
      ),
      request: request,
    );

    expect(keyA, isNot(keyB));
  });

  test('request copyWith preserves pagination token unless explicitly cleared',
      () {
    const request = ServerDiscoveryRequest(
      query: 'games',
      filter: ServerDiscoveryFilter.rooms,
      since: 'next',
      limit: 50,
    );

    expect(request.copyWith(query: 'music').since, 'next');
    expect(request.copyWith(since: null).since, isNull);
  });
}

ServerDiscoveryEntry _entry({
  String roomId = '!room:example',
  String? roomType,
  String? joinRule = 'public',
  bool alreadyJoined = false,
}) {
  return ServerDiscoveryEntry.fromDirectory(
    roomId: roomId,
    roomType: roomType,
    name: 'Room',
    topic: null,
    avatarUrl: null,
    memberCount: 1,
    canonicalAlias: '#room:example',
    joinRule: joinRule,
    alreadyJoined: alreadyJoined,
    worldReadable: false,
    guestCanJoin: false,
  );
}
