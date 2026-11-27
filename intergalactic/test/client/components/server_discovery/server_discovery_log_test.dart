import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_log.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';

void main() {
  test('fetch logs omit raw homeserver and full search query', () {
    const scope = ServerDiscoveryScope(
      accountId: '@alice:one.example',
      homeserver: 'one.example',
    );
    const request = ServerDiscoveryRequest(query: 'private search term');

    final message = ServerDiscoveryLogFormatter.fetchSuccess(
      scope: scope,
      request: request,
      resultCount: 3,
      hasMore: true,
    );

    expect(message, isNot(contains('one.example')));
    expect(message, isNot(contains('private search term')));
    expect(message, contains('hasSearch=true'));
    expect(message, contains('count=3'));
  });

  test('join logs omit raw room identifiers', () {
    const scope = ServerDiscoveryScope(
      accountId: '@alice:one.example',
      homeserver: 'one.example',
    );
    final entry = ServerDiscoveryEntry.fromDirectory(
      roomId: '!secret:one.example',
      roomType: null,
      name: 'Secret Room',
      topic: 'Private topic',
      avatarUrl: null,
      memberCount: 2,
      canonicalAlias: '#secret:one.example',
      joinRule: 'public',
      alreadyJoined: false,
      worldReadable: false,
      guestCanJoin: false,
    );

    final message = ServerDiscoveryLogFormatter.joinOutcome(
      scope: scope,
      entry: entry,
      outcome: ServerDiscoveryJoinOutcome.joined,
      matrixErrorCode: 'M_FORBIDDEN',
    );

    expect(message, isNot(contains('!secret:one.example')));
    expect(message, isNot(contains('#secret:one.example')));
    expect(message, isNot(contains('Secret Room')));
    expect(message, isNot(contains('Private topic')));
    expect(message, contains('matrixError=M_FORBIDDEN'));
  });

  test('supplemental logs omit raw homeserver and full search query', () {
    const scope = ServerDiscoveryScope(
      accountId: '@alice:one.example',
      homeserver: 'one.example',
    );
    const request = ServerDiscoveryRequest(query: 'restricted project');

    final message = ServerDiscoveryLogFormatter.supplementalFailure(
      scope: scope,
      request: request,
      matrixErrorCode: 'M_FORBIDDEN',
    );

    expect(message, isNot(contains('one.example')));
    expect(message, isNot(contains('restricted project')));
    expect(message, contains('hasSearch=true'));
    expect(message, contains('matrixError=M_FORBIDDEN'));
  });
}
