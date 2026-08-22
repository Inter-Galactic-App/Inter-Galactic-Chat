import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_cache.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_publication_controller.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_service.dart';

void main() {
  test('publish success updates state and invalidates scoped cache', () async {
    final cache = ServerDiscoveryPageCache();
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    cache.store(ServerDiscoveryPage(
      scope: scope,
      request: const ServerDiscoveryRequest(),
      entries: [_entry()],
    ));
    final target = _target(canManage: true);
    final service = _FakePublicationService(
      scope: scope,
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.private,
        canManage: true,
      ),
      publishResult: ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.published,
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: ServerDiscoveryPublicationVisibility.public,
          canManage: true,
        ),
      ),
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: cache,
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    final result = await controller.publish();

    expect(result.success, isTrue);
    expect(controller.isPublished, isTrue);
    expect(cache.length, 0);
  });

  test('unpublish success updates state', () async {
    final target = _target(canManage: true);
    final service = _FakePublicationService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.public,
        canManage: true,
      ),
      unpublishResult: ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.unpublished,
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: ServerDiscoveryPublicationVisibility.private,
          canManage: true,
        ),
      ),
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    await controller.unpublish();

    expect(controller.isPublished, isFalse);
  });

  test('permission denial is exposed without success invalidation', () async {
    final cache = ServerDiscoveryPageCache();
    const scope = ServerDiscoveryScope(
      accountId: '@a:one.example',
      homeserver: 'one.example',
    );
    cache.store(ServerDiscoveryPage(
      scope: scope,
      request: const ServerDiscoveryRequest(),
      entries: [_entry()],
    ));
    final target = _target(canManage: false);
    final service = _FakePublicationService(
      scope: scope,
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.unknown,
        canManage: false,
        failureKind: ServerDiscoveryFailureKind.permissionDenied,
      ),
      publishResult: const ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.permissionDenied,
      ),
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: cache,
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    final result = await controller.publish();

    expect(controller.canManage, isFalse);
    expect(result.outcome, ServerDiscoveryPublicationOutcome.permissionDenied);
    expect(cache.length, 1);
  });

  test('homeserver policy denial is exposed as failed action', () async {
    final target = _target(canManage: true);
    final service = _FakePublicationService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.private,
        canManage: true,
      ),
      publishResult: ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.serverPolicyDenied,
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: ServerDiscoveryPublicationVisibility.private,
          canManage: true,
          failureKind: ServerDiscoveryFailureKind.serverPolicyDenied,
          matrixErrorCode: 'M_FORBIDDEN',
        ),
        matrixErrorCode: 'M_FORBIDDEN',
      ),
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    await controller.refresh();
    final result = await controller.publish();

    expect(result.success, isFalse);
    expect(controller.state?.serverPolicyDenied, isTrue);
    expect(controller.state?.matrixErrorCode, 'M_FORBIDDEN');
  });

  test('coalesces concurrent publish mutations', () async {
    final target = _target(canManage: true);
    final completer = Completer<ServerDiscoveryPublicationResult>();
    final service = _FakePublicationService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.private,
        canManage: true,
      ),
      publishCompleter: completer,
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    final first = controller.publish();
    final second = controller.publish();
    completer.complete(ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.published,
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.public,
        canManage: true,
      ),
    ));

    final results = await Future.wait([first, second]);

    expect(service.publishCount, 1);
    expect(results[0].outcome, ServerDiscoveryPublicationOutcome.published);
    expect(results[1].outcome, ServerDiscoveryPublicationOutcome.published);
    expect(controller.isUpdating, isFalse);
  });

  test('rejects opposite publication mutation while publish is in flight',
      () async {
    final target = _target(canManage: true);
    final completer = Completer<ServerDiscoveryPublicationResult>();
    final service = _FakePublicationService(
      scope: const ServerDiscoveryScope(
        accountId: '@a:one.example',
        homeserver: 'one.example',
      ),
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.private,
        canManage: true,
      ),
      publishCompleter: completer,
    );
    final controller = ServerDiscoveryPublicationController(
      service: service,
      target: target,
      cache: ServerDiscoveryPageCache(),
    );
    addTearDown(controller.dispose);

    final publish = controller.publish();
    await expectLater(controller.unpublish(), throwsA(isA<StateError>()));
    completer.complete(ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.published,
      state: ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.public,
        canManage: true,
      ),
    ));
    await publish;

    expect(service.publishCount, 1);
    expect(service.unpublishCount, 0);
    expect(controller.isUpdating, isFalse);
  });
}

class _FakePublicationService implements ServerDiscoveryService {
  _FakePublicationService({
    required this.scope,
    required this.state,
    this.publishResult = const ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.published,
    ),
    this.unpublishResult = const ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.unpublished,
    ),
    this.publishCompleter,
  });

  @override
  final ServerDiscoveryScope scope;

  final ServerDiscoveryPublicationState state;
  final ServerDiscoveryPublicationResult publishResult;
  final ServerDiscoveryPublicationResult unpublishResult;
  final Completer<ServerDiscoveryPublicationResult>? publishCompleter;
  int publishCount = 0;
  int unpublishCount = 0;

  @override
  Future<ServerDiscoveryPage> fetchPage(ServerDiscoveryRequest request) {
    throw UnimplementedError();
  }

  @override
  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry) {
    throw UnimplementedError();
  }

  @override
  Future<ServerDiscoveryPublicationState> getPublicationState(
    ServerDiscoveryPublicationTarget target,
  ) async {
    return state;
  }

  @override
  Future<ServerDiscoveryPublicationResult> publish(
    ServerDiscoveryPublicationTarget target,
  ) async {
    publishCount++;
    final pending = publishCompleter;
    if (pending != null) {
      return pending.future;
    }
    return publishResult;
  }

  @override
  Future<ServerDiscoveryPublicationResult> unpublish(
    ServerDiscoveryPublicationTarget target,
  ) async {
    unpublishCount++;
    return unpublishResult;
  }
}

ServerDiscoveryPublicationTarget _target({required bool canManage}) {
  return ServerDiscoveryPublicationTarget(
    identifier: '!room:one.example',
    type: ServerDiscoveryEntryType.room,
    canManage: canManage,
  );
}

ServerDiscoveryEntry _entry() {
  return ServerDiscoveryEntry.fromDirectory(
    roomId: '!room:one.example',
    roomType: null,
    name: 'Room',
    topic: null,
    avatarUrl: null,
    memberCount: 1,
    canonicalAlias: null,
    joinRule: 'public',
    alreadyJoined: false,
    worldReadable: false,
    guestCanJoin: false,
  );
}
