import 'server_discovery_models.dart';

abstract class ServerDiscoveryService {
  ServerDiscoveryScope get scope;

  Future<ServerDiscoveryPage> fetchPage(ServerDiscoveryRequest request);

  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry);

  Future<ServerDiscoveryPublicationState> getPublicationState(
    ServerDiscoveryPublicationTarget target,
  );

  Future<ServerDiscoveryPublicationResult> publish(
    ServerDiscoveryPublicationTarget target,
  );

  Future<ServerDiscoveryPublicationResult> unpublish(
    ServerDiscoveryPublicationTarget target,
  );
}

abstract class ServerDiscoverySupplementalService {
  Future<List<ServerDiscoveryEntry>> fetchSupplementalEntries(
    ServerDiscoveryRequest request,
  );
}

class UnsupportedServerDiscoveryService implements ServerDiscoveryService {
  UnsupportedServerDiscoveryService({
    required this.scope,
  });

  @override
  final ServerDiscoveryScope scope;

  @override
  Future<ServerDiscoveryPage> fetchPage(ServerDiscoveryRequest request) async {
    throw const ServerDiscoveryError(
      kind: ServerDiscoveryFailureKind.unsupportedClient,
      message: 'Server Discovery is only available for Matrix accounts.',
    );
  }

  @override
  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry) async {
    return const ServerDiscoveryJoinResult(
      outcome: ServerDiscoveryJoinOutcome.failed,
    );
  }

  @override
  Future<ServerDiscoveryPublicationState> getPublicationState(
    ServerDiscoveryPublicationTarget target,
  ) async {
    return ServerDiscoveryPublicationState(
      target: target,
      visibility: ServerDiscoveryPublicationVisibility.unknown,
      canManage: false,
      failureKind: ServerDiscoveryFailureKind.unsupportedClient,
    );
  }

  @override
  Future<ServerDiscoveryPublicationResult> publish(
    ServerDiscoveryPublicationTarget target,
  ) async {
    return const ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.unsupported,
    );
  }

  @override
  Future<ServerDiscoveryPublicationResult> unpublish(
    ServerDiscoveryPublicationTarget target,
  ) async {
    return const ServerDiscoveryPublicationResult(
      outcome: ServerDiscoveryPublicationOutcome.unsupported,
    );
  }
}
