import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_cache.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_controller.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_service.dart';

void main() {
  test('evicts oldest cached discovery pages beyond the size limit', () {
    final cache = ServerDiscoveryPageCache(maxEntries: 2);
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );

    cache
      ..store(
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(query: 'one'),
          entries: [_entry('!one:one.example')],
        ),
      )
      ..store(
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(query: 'two'),
          entries: [_entry('!two:one.example')],
        ),
      )
      ..store(
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(query: 'three'),
          entries: [_entry('!three:one.example')],
        ),
      );

    expect(cache.length, 2);
    expect(
      cache.read(
        scope: scope,
        request: const ServerDiscoveryRequest(query: 'one'),
      ),
      isNull,
    );
    expect(
      cache.read(
        scope: scope,
        request: const ServerDiscoveryRequest(query: 'two'),
      ),
      isNotNull,
    );
    expect(
      cache.read(
        scope: scope,
        request: const ServerDiscoveryRequest(query: 'three'),
      ),
      isNotNull,
    );
  });

  test('evicts expired cached discovery pages', () {
    var now = DateTime(2026, 6, 25, 12);
    final cache = ServerDiscoveryPageCache(
      maxAge: const Duration(minutes: 5),
      clock: () => now,
    );
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );

    cache.store(
      ServerDiscoveryPage(
        scope: scope,
        request: const ServerDiscoveryRequest(query: 'old'),
        entries: [_entry('!old:one.example')],
      ),
    );
    now = now.add(const Duration(minutes: 6));

    expect(
      cache.read(
        scope: scope,
        request: const ServerDiscoveryRequest(query: 'old'),
      ),
      isNull,
    );
    expect(cache.length, 0);
  });

  test('keeps cached results isolated by account and homeserver', () async {
    final cache = ServerDiscoveryPageCache();
    final serviceA = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      pages: [_page('one.example', '!a:one.example')],
    );
    final serviceB = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@b:two.example',
        homeserver: 'two.example',
      ),
      pages: [_page('two.example', '!b:two.example')],
    );

    final controllerA = ServerDiscoveryController(
      service: serviceA,
      cache: cache,
    );
    final controllerB = ServerDiscoveryController(
      service: serviceB,
      cache: cache,
    );
    addTearDown(controllerA.dispose);
    addTearDown(controllerB.dispose);

    await controllerA.loadInitial();
    await controllerB.loadInitial();

    expect(controllerA.entries.single.roomId, '!a:one.example');
    expect(controllerB.entries.single.roomId, '!b:two.example');
    expect(serviceA.fetchCount, 1);
    expect(serviceB.fetchCount, 1);
    expect(cache.length, 2);
  });

  test('uses server search and pagination request state', () async {
    final service = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      pages: [
        _page('one.example', '!one:one.example', nextBatch: 'next'),
        _page('one.example', '!two:one.example'),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.setQuery('  games  ');
    await controller.loadMore();

    expect(service.requests[0].normalizedQuery, 'games');
    expect(service.requests[0].since, isNull);
    expect(service.requests[1].since, 'next');
    expect(controller.entries.map((entry) => entry.roomId), [
      '!one:one.example',
      '!two:one.example',
    ]);
  });

  test(
    'filter changes reload results and preserve filter in request',
    () async {
      final service = _FakeDiscoveryService(
        scope: const ServerDiscoveryScope(
          accountId: '@a:one.example',
          homeserver: 'one.example',
        ),
        pages: [
          _page('one.example', '!space:one.example', roomType: 'm.space'),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.setFilter(ServerDiscoveryFilter.spaces);

      expect(service.requests.single.filter, ServerDiscoveryFilter.spaces);
      expect(controller.entries.single.type, ServerDiscoveryEntryType.space);
    },
  );

  test(
    'unjoined filter is local and does not reload directory results',
    () async {
      final service = _FakeDiscoveryService(
        scope: const ServerDiscoveryScope(
          accountId: '@a:one.example',
          homeserver: 'one.example',
        ),
        pages: [
          ServerDiscoveryPage(
            scope: const ServerDiscoveryScope(
              accountId: '@a:one.example',
              homeserver: 'one.example',
            ),
            request: const ServerDiscoveryRequest(),
            entries: [
              _entry(
                '!joined:one.example',
                name: 'Joined',
                alreadyJoined: true,
              ),
              _entry('!open:one.example', name: 'Open', alreadyJoined: false),
            ],
          ),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.setAccessFilter(ServerDiscoveryAccessFilter.unjoined);

      expect(service.fetchCount, 1);
      expect(controller.entries.map((entry) => entry.roomId), [
        '!open:one.example',
      ]);
    },
  );

  test('sort modes reorder currently loaded results locally', () async {
    final service = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      pages: [
        ServerDiscoveryPage(
          scope: const ServerDiscoveryScope(
            accountId: '@a:one.example',
            homeserver: 'one.example',
          ),
          request: const ServerDiscoveryRequest(),
          entries: [
            _entry(
              '!joined-room:one.example',
              name: 'Zeta',
              alreadyJoined: true,
            ),
            _entry(
              '!space:one.example',
              roomType: serverDiscoverySpaceRoomType,
              name: 'Beta',
            ),
            _entry('!open-room:one.example', name: 'Alpha'),
          ],
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    expect(controller.entries.map((entry) => entry.roomId), [
      '!joined-room:one.example',
      '!space:one.example',
      '!open-room:one.example',
    ]);

    await controller.setSortMode(ServerDiscoverySortMode.alphabetical);
    expect(controller.entries.map((entry) => entry.roomId), [
      '!open-room:one.example',
      '!space:one.example',
      '!joined-room:one.example',
    ]);

    await controller.setSortMode(ServerDiscoverySortMode.space);
    expect(controller.entries.map((entry) => entry.roomId), [
      '!space:one.example',
      '!open-room:one.example',
      '!joined-room:one.example',
    ]);

    await controller.setSortMode(ServerDiscoverySortMode.joinedStatus);
    expect(controller.entries.map((entry) => entry.roomId), [
      '!open-room:one.example',
      '!space:one.example',
      '!joined-room:one.example',
    ]);
    expect(service.fetchCount, 1);
  });

  test('space sort keeps each space with its rooms alphabetically', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(),
          entries: [
            _entry(
              '!space-y:one.example',
              roomType: serverDiscoverySpaceRoomType,
              name: 'Space Y',
              sourceAccountId: scope.accountId,
            ),
            _entry(
              '!ungrouped:one.example',
              name: 'Arcade',
              sourceAccountId: scope.accountId,
            ),
            _entry(
              '!space-x:one.example',
              roomType: serverDiscoverySpaceRoomType,
              name: 'Space X',
              sourceAccountId: scope.accountId,
            ),
          ],
        ),
      ],
      supplementalEntries: [
        _entry(
          '!x-room-b:one.example',
          name: 'Room B',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          parentSpaceId: '!space-x:one.example',
          parentSpaceName: 'Space X',
        ),
        _entry(
          '!y-room-b:one.example',
          name: 'Room B',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          parentSpaceId: '!space-y:one.example',
          parentSpaceName: 'Space Y',
        ),
        _entry(
          '!x-room-a:one.example',
          name: 'Room A',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          parentSpaceId: '!space-x:one.example',
          parentSpaceName: 'Space X',
        ),
        _entry(
          '!y-room-a:one.example',
          name: 'Room A',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          parentSpaceId: '!space-y:one.example',
          parentSpaceName: 'Space Y',
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    await controller.setSortMode(ServerDiscoverySortMode.space);

    expect(controller.entries.map((entry) => entry.roomId), [
      '!space-x:one.example',
      '!x-room-a:one.example',
      '!x-room-b:one.example',
      '!space-y:one.example',
      '!y-room-a:one.example',
      '!y-room-b:one.example',
      '!ungrouped:one.example',
    ]);
    expect(service.fetchCount, 1);
  });

  test(
    'space sort preserves supplemental group order and parent metadata',
    () async {
      const scope = ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      );
      final service = _FakeDiscoveryService(
        scope: scope,
        pages: [
          ServerDiscoveryPage(
            scope: scope,
            request: const ServerDiscoveryRequest(),
            entries: [
              _entry(
                '!joined-a:one.example',
                name: 'Auto Room A',
                alreadyJoined: true,
                sourceAccountId: scope.accountId,
              ),
              _entry(
                '!space-a:one.example',
                roomType: serverDiscoverySpaceRoomType,
                name: 'Space A',
                sourceAccountId: scope.accountId,
              ),
              _entry(
                '!space-b:one.example',
                roomType: serverDiscoverySpaceRoomType,
                name: 'Space B',
                sourceAccountId: scope.accountId,
              ),
            ],
          ),
        ],
        supplementalEntries: [
          _entry(
            '!joined-b:one.example',
            name: 'Auto Room B',
            source: ServerDiscoveryEntrySource.spaceChild,
            sourceAccountId: scope.accountId,
            parentSpaceId: '!space-b:one.example',
            parentSpaceName: 'Space B',
          ),
          _entry(
            '!joined-a:one.example',
            name: 'Auto Room A',
            source: ServerDiscoveryEntrySource.spaceChild,
            sourceAccountId: scope.accountId,
            parentSpaceId: '!space-a:one.example',
            parentSpaceName: 'Space A',
          ),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      await controller.setSortMode(ServerDiscoverySortMode.space);

      expect(controller.entries.map((entry) => entry.roomId), [
        '!space-b:one.example',
        '!joined-b:one.example',
        '!space-a:one.example',
        '!joined-a:one.example',
      ]);
      expect(
        controller.entries
            .firstWhere((entry) => entry.roomId == '!joined-a:one.example')
            .parentSpaceId,
        '!space-a:one.example',
      );
      expect(service.fetchCount, 1);
    },
  );

  test('exposes loading and empty states', () async {
    final completer = Completer<ServerDiscoveryPage>();
    final service = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      completer: completer,
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    final load = controller.loadInitial();
    expect(controller.isLoading, isTrue);

    completer.complete(
      ServerDiscoveryPage(
        scope: service.scope,
        request: const ServerDiscoveryRequest(),
        entries: const [],
      ),
    );
    await load;

    expect(controller.isLoading, isFalse);
    expect(controller.isEmpty, isTrue);
  });

  test('retry reloads after failure', () async {
    final service =
        _FakeDiscoveryService(
            scope: const ServerDiscoveryScope(
              accountId: '@a:one.example',
              homeserver: 'one.example',
            ),
            pages: [_page('one.example', '!room:one.example')],
          )
          ..error = const ServerDiscoveryError(
            kind: ServerDiscoveryFailureKind.networkFailure,
            message: 'failed',
          );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    expect(controller.error?.kind, ServerDiscoveryFailureKind.networkFailure);

    service.error = null;
    await controller.retry();

    expect(controller.error, isNull);
    expect(controller.entries.single.roomId, '!room:one.example');
  });

  test('merges scoped supplemental restricted child entries', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        const ServerDiscoveryPage(
          scope: scope,
          request: ServerDiscoveryRequest(),
          entries: [],
        ),
      ],
      supplementalEntries: [
        _entry(
          '!restricted:one.example',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          joinRule: 'restricted',
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    expect(controller.entries.single.roomId, '!restricted:one.example');
    expect(
      controller.entries.single.source,
      ServerDiscoveryEntrySource.spaceChild,
    );
    expect(service.supplementalFetchCount, 1);
  });

  test(
    'recomputes supplemental entries when using cached directory page',
    () async {
      const scope = ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      );
      final service = _FakeDiscoveryService(
        scope: scope,
        pages: [
          const ServerDiscoveryPage(
            scope: scope,
            request: ServerDiscoveryRequest(),
            entries: [],
          ),
        ],
        supplementalEntries: [
          _entry(
            '!first:one.example',
            source: ServerDiscoveryEntrySource.spaceChild,
            sourceAccountId: scope.accountId,
            joinRule: 'restricted',
          ),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      service.supplementalEntries = [
        _entry(
          '!second:one.example',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          joinRule: 'restricted',
        ),
      ];
      await controller.loadInitial();

      expect(service.fetchCount, 1);
      expect(service.supplementalFetchCount, 2);
      expect(controller.entries.single.roomId, '!second:one.example');
    },
  );

  test('drops cached supplemental entries if refresh source fails', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        const ServerDiscoveryPage(
          scope: scope,
          request: ServerDiscoveryRequest(),
          entries: [],
        ),
      ],
      supplementalEntries: [
        _entry(
          '!first:one.example',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          joinRule: 'restricted',
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    service.throwSupplemental = true;
    service.supplementalEntries = const [];
    await controller.loadInitial();

    expect(service.fetchCount, 1);
    expect(service.supplementalFetchCount, 2);
    expect(controller.entries, isEmpty);
  });

  test(
    'removes stale supplemental entries after successful recompute',
    () async {
      const scope = ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      );
      final service = _FakeDiscoveryService(
        scope: scope,
        pages: [
          const ServerDiscoveryPage(
            scope: scope,
            request: ServerDiscoveryRequest(),
            entries: [],
          ),
        ],
        supplementalEntries: [
          _entry(
            '!first:one.example',
            source: ServerDiscoveryEntrySource.spaceChild,
            sourceAccountId: scope.accountId,
            joinRule: 'restricted',
          ),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();
      service.supplementalEntries = const [];
      await controller.loadInitial();

      expect(controller.entries, isEmpty);
    },
  );

  test('dedupes supplemental entries and lets directory rows win', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        const ServerDiscoveryPage(
          scope: scope,
          request: ServerDiscoveryRequest(),
          entries: [],
          nextBatch: 'next',
        ),
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(since: 'next'),
          entries: [
            _entry(
              '!same:one.example',
              name: 'Directory',
              sourceAccountId: scope.accountId,
            ),
          ],
        ),
      ],
      supplementalEntries: [
        _entry(
          '!same:one.example',
          name: 'Supplemental',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: scope.accountId,
          joinRule: 'restricted',
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    await controller.loadMore();

    expect(controller.entries, hasLength(1));
    expect(
      controller.entries.single.source,
      ServerDiscoveryEntrySource.directory,
    );
    expect(controller.entries.single.displayName, 'Directory');
  });

  test(
    'keeps directory row while filling missing avatar from supplemental',
    () async {
      const scope = ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      );
      final avatarUrl = Uri.parse('mxc://one.example/avatar');
      final service = _FakeDiscoveryService(
        scope: scope,
        pages: [
          ServerDiscoveryPage(
            scope: scope,
            request: const ServerDiscoveryRequest(),
            entries: [
              _entry(
                '!same:one.example',
                name: 'Directory',
                sourceAccountId: scope.accountId,
              ),
            ],
          ),
        ],
        supplementalEntries: [
          _entry(
            '!same:one.example',
            name: 'Supplemental',
            avatarUrl: avatarUrl,
            source: ServerDiscoveryEntrySource.spaceChild,
            sourceAccountId: scope.accountId,
            joinRule: 'restricted',
          ),
        ],
      );
      final controller = ServerDiscoveryController(
        service: service,
        cache: ServerDiscoveryPageCache(),
      );
      addTearDown(controller.dispose);

      await controller.loadInitial();

      expect(controller.entries, hasLength(1));
      expect(
        controller.entries.single.source,
        ServerDiscoveryEntrySource.directory,
      );
      expect(controller.entries.single.displayName, 'Directory');
      expect(controller.entries.single.avatarUrl, avatarUrl);
    },
  );

  test('drops supplemental entries from another account scope', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@focused:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        const ServerDiscoveryPage(
          scope: scope,
          request: ServerDiscoveryRequest(),
          entries: [],
        ),
      ],
      supplementalEntries: [
        _entry(
          '!foreign:one.example',
          source: ServerDiscoveryEntrySource.spaceChild,
          sourceAccountId: '@other:one.example',
          joinRule: 'restricted',
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    expect(controller.entries, isEmpty);
  });

  test('keeps directory results when supplemental source fails', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(),
          entries: [_entry('!room:one.example')],
        ),
      ],
      throwSupplemental: true,
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    expect(controller.error, isNull);
    expect(controller.entries.single.roomId, '!room:one.example');
  });

  test('join marks successful public joins as already joined', () async {
    final entry = _entry('!room:one.example');
    final service = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      pages: [
        ServerDiscoveryPage(
          scope: const ServerDiscoveryScope(
            accountId: '@a:one.example',
            homeserver: 'one.example',
          ),
          request: const ServerDiscoveryRequest(),
          entries: [entry],
        ),
      ],
      joinResult: const ServerDiscoveryJoinResult(
        outcome: ServerDiscoveryJoinOutcome.joined,
      ),
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    expect(controller.cache.length, 1);
    await controller.join(entry);

    expect(controller.entries.single.alreadyJoined, isTrue);
    expect(controller.cache.length, 0);
  });

  test('successful joins leave the unjoined local filter', () async {
    final entry = _entry('!room:one.example');
    final service = _FakeDiscoveryService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      pages: [
        ServerDiscoveryPage(
          scope: const ServerDiscoveryScope(
            accountId: '@a:one.example',
            homeserver: 'one.example',
          ),
          request: const ServerDiscoveryRequest(),
          entries: [entry],
        ),
      ],
      joinResult: const ServerDiscoveryJoinResult(
        outcome: ServerDiscoveryJoinOutcome.joined,
      ),
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();
    await controller.setAccessFilter(ServerDiscoveryAccessFilter.unjoined);
    expect(controller.entries.single.roomId, '!room:one.example');

    await controller.join(entry);

    expect(controller.entries, isEmpty);
  });

  test('drops cached entries from another account scope', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@focused:one.example',
      homeserver: 'one.example',
    );
    final service = _FakeDiscoveryService(
      scope: scope,
      pages: [
        ServerDiscoveryPage(
          scope: scope,
          request: const ServerDiscoveryRequest(),
          entries: [
            _entry(
              '!foreign:one.example',
              alreadyJoined: true,
              sourceAccountId: '@other:one.example',
            ),
            _entry(
              '!focused:one.example',
              alreadyJoined: false,
              sourceAccountId: '@focused:one.example',
            ),
          ],
        ),
      ],
    );
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.loadInitial();

    expect(controller.entries.map((entry) => entry.roomId), [
      '!focused:one.example',
    ]);
    expect(controller.entries.single.alreadyJoined, isFalse);
  });

  test('does not join entries from another account scope', () async {
    const scope = ServerDiscoveryScope(
      accountId: '@focused:one.example',
      homeserver: 'one.example',
    );
    final entry = _entry(
      '!foreign:one.example',
      sourceAccountId: '@other:one.example',
    );
    final service = _FakeDiscoveryService(scope: scope);
    final controller = ServerDiscoveryController(
      service: service,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    final result = await controller.join(entry);

    expect(result.outcome, ServerDiscoveryJoinOutcome.staleEntry);
    expect(service.joinCount, 0);
  });
}

class _FakeDiscoveryService
    implements ServerDiscoveryService, ServerDiscoverySupplementalService {
  _FakeDiscoveryService({
    required this.scope,
    this.pages = const [],
    this.completer,
    this.joinResult = const ServerDiscoveryJoinResult(
      outcome: ServerDiscoveryJoinOutcome.joined,
    ),
    this.supplementalEntries = const [],
    this.throwSupplemental = false,
  });

  @override
  final ServerDiscoveryScope scope;

  final List<ServerDiscoveryPage> pages;
  final Completer<ServerDiscoveryPage>? completer;
  final ServerDiscoveryJoinResult joinResult;
  List<ServerDiscoveryEntry> supplementalEntries;
  bool throwSupplemental;
  final List<ServerDiscoveryRequest> requests = [];
  final List<ServerDiscoveryRequest> supplementalRequests = [];
  ServerDiscoveryError? error;
  int fetchCount = 0;
  int supplementalFetchCount = 0;
  int joinCount = 0;
  int _pageIndex = 0;

  @override
  Future<ServerDiscoveryPage> fetchPage(ServerDiscoveryRequest request) async {
    fetchCount++;
    requests.add(request);
    final nextError = error;
    if (nextError != null) {
      throw nextError;
    }
    final pending = completer;
    if (pending != null) {
      return pending.future;
    }
    final page = pages[_pageIndex.clamp(0, pages.length - 1)];
    _pageIndex++;
    return ServerDiscoveryPage(
      scope: scope,
      request: request,
      entries: page.entries,
      nextBatch: page.nextBatch,
      prevBatch: page.prevBatch,
      totalEstimate: page.totalEstimate,
    );
  }

  @override
  Future<List<ServerDiscoveryEntry>> fetchSupplementalEntries(
    ServerDiscoveryRequest request,
  ) async {
    supplementalFetchCount++;
    supplementalRequests.add(request);
    if (throwSupplemental) {
      throw Exception('supplemental failed');
    }
    return supplementalEntries;
  }

  @override
  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry) async {
    joinCount++;
    return joinResult;
  }

  @override
  Future<ServerDiscoveryPublicationState> getPublicationState(
    ServerDiscoveryPublicationTarget target,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ServerDiscoveryPublicationResult> publish(
    ServerDiscoveryPublicationTarget target,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<ServerDiscoveryPublicationResult> unpublish(
    ServerDiscoveryPublicationTarget target,
  ) {
    throw UnimplementedError();
  }
}

ServerDiscoveryPage _page(
  String homeserver,
  String roomId, {
  String? nextBatch,
  String? roomType,
}) {
  final scope = ServerDiscoveryScope(
    accountId: '@user:$homeserver',
    homeserver: homeserver,
  );
  return ServerDiscoveryPage(
    scope: scope,
    request: const ServerDiscoveryRequest(),
    entries: [_entry(roomId, roomType: roomType)],
    nextBatch: nextBatch,
  );
}

ServerDiscoveryEntry _entry(
  String roomId, {
  String? roomType,
  String name = 'Room',
  String? joinRule = 'public',
  bool alreadyJoined = false,
  Uri? avatarUrl,
  String? sourceAccountId,
  ServerDiscoveryEntrySource source = ServerDiscoveryEntrySource.directory,
  String? parentSpaceId,
  String? parentSpaceName,
}) {
  if (source == ServerDiscoveryEntrySource.spaceChild) {
    return ServerDiscoveryEntry.fromSpaceChild(
      roomId: roomId,
      roomType: roomType,
      name: name,
      topic: null,
      avatarUrl: avatarUrl,
      memberCount: 1,
      canonicalAlias: null,
      joinRule: joinRule,
      alreadyJoined: alreadyJoined,
      sourceAccountId: sourceAccountId ?? '@user:example',
      worldReadable: false,
      guestCanJoin: false,
      parentSpaceId: parentSpaceId,
      parentSpaceName: parentSpaceName,
    );
  }
  return ServerDiscoveryEntry.fromDirectory(
    roomId: roomId,
    roomType: roomType,
    name: name,
    topic: null,
    avatarUrl: avatarUrl,
    memberCount: 1,
    canonicalAlias: null,
    joinRule: joinRule,
    alreadyJoined: alreadyJoined,
    sourceAccountId: sourceAccountId,
    worldReadable: false,
    guestCanJoin: false,
  );
}
