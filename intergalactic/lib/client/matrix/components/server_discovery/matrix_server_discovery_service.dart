import 'package:flutter/foundation.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_log.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_models.dart';
import 'package:intergalactic/client/components/server_discovery/server_discovery_service.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

typedef ServerDiscoveryKnockRequester =
    Future<void> Function(String address, {List<String>? via});
typedef OutstandingKnockRecorder = Future<void> Function(String roomId);

/// Sends a discovery knock and records its canonical room id only after the
/// homeserver accepted the request. The invite after approval uses this id, not
/// a directory alias used to route the knock request.
@visibleForTesting
Future<void> sendTrackedServerDiscoveryKnock({
  required String roomId,
  required String address,
  required List<String>? via,
  required ServerDiscoveryKnockRequester requestKnock,
  required OutstandingKnockRecorder recordOutstandingKnock,
}) async {
  await requestKnock(address, via: via);
  await recordOutstandingKnock(roomId);
}

class MatrixServerDiscoveryService
    implements ServerDiscoveryService, ServerDiscoverySupplementalService {
  MatrixServerDiscoveryService(this.client);

  final MatrixClient client;

  matrix.Client get _matrixClient => client.matrixClient;

  @override
  late final ServerDiscoveryScope scope = _buildScope(client);

  @override
  Future<ServerDiscoveryPage> fetchPage(ServerDiscoveryRequest request) async {
    try {
      final response = await _queryPublicRooms(request);
      final entries = response.chunk
          .map(_entryFromChunk)
          .where((entry) => entry.matchesFilter(request.filter))
          .toList();
      final page = ServerDiscoveryPage(
        scope: scope,
        request: request,
        entries: entries,
        nextBatch: response.nextBatch,
        prevBatch: response.prevBatch,
        totalEstimate: response.totalRoomCountEstimate,
      );
      Log.i(
        ServerDiscoveryLogFormatter.fetchSuccess(
          scope: scope,
          request: request,
          resultCount: entries.length,
          hasMore: page.hasMore,
        ),
        category: LogCategory.matrix,
        source: 'server-discovery',
      );
      return page;
    } on matrix.MatrixException catch (error) {
      if (error.error == matrix.MatrixError.M_UNRECOGNIZED &&
          !request.hasSearch) {
        return _fetchPublicRoomsFallback(request);
      }
      _logFetchFailure(request, error.errcode);
      throw _discoveryErrorFromMatrixException(error);
    } catch (_) {
      _logFetchFailure(request, null);
      throw const ServerDiscoveryError(
        kind: ServerDiscoveryFailureKind.networkFailure,
        message: 'Could not reach the homeserver directory.',
      );
    }
  }

  @override
  Future<List<ServerDiscoveryEntry>> fetchSupplementalEntries(
    ServerDiscoveryRequest request,
  ) async {
    if (request.since != null ||
        request.filter == ServerDiscoveryFilter.spaces) {
      return const [];
    }

    final entries = <ServerDiscoveryEntry>[];
    final seenRoomIds = <String>{};
    for (final space in client.spaces.whereType<MatrixSpace>()) {
      final chunks = await _restrictedSpaceChildChunks(space, request);
      for (final chunk in chunks) {
        final entry = _entryFromSpaceChildChunk(space, chunk);
        if (entry == null ||
            !entry.matchesFilter(request.filter) ||
            !_matchesSupplementalSearch(entry, request)) {
          continue;
        }
        if (seenRoomIds.add(entry.roomId)) {
          entries.add(entry);
        }
      }
    }
    return entries;
  }

  @override
  Future<ServerDiscoveryJoinResult> join(ServerDiscoveryEntry entry) async {
    if (entry.roomId.trim().isEmpty) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.staleEntry);
    }

    if (entry.alreadyJoined) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.alreadyJoined);
    }

    final requirement = entry.joinRequirement;
    if (requirement == ServerDiscoveryJoinRequirement.inviteRequired) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.inviteRequired);
    }
    if (requirement == ServerDiscoveryJoinRequirement.unsupported) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.unsupportedJoinRule);
    }
    if (requirement == ServerDiscoveryJoinRequirement.unavailable) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.staleEntry);
    }

    try {
      final address = directoryEntryAddress(entry);
      final via = directoryEntryVia(entry, scope);
      if (requirement == ServerDiscoveryJoinRequirement.knockRequired) {
        await sendTrackedServerDiscoveryKnock(
          roomId: entry.roomId,
          address: address,
          via: via,
          requestKnock: _matrixClient.knockRoom,
          recordOutstandingKnock: client.recordOutstandingKnock,
        );
        return _joinResult(entry, ServerDiscoveryJoinOutcome.knockRequested);
      }

      final joinAddress = _addressWithVia(address, via);
      if (entry.type == ServerDiscoveryEntryType.space) {
        await client.joinSpace(joinAddress);
      } else {
        await client.joinRoom(joinAddress);
      }
      return _joinResult(entry, ServerDiscoveryJoinOutcome.joined);
    } on matrix.MatrixException catch (error) {
      return _joinResult(
        entry,
        _joinOutcomeFromMatrixException(error),
        matrixErrorCode: error.errcode,
      );
    } catch (_) {
      return _joinResult(entry, ServerDiscoveryJoinOutcome.networkFailure);
    }
  }

  @override
  Future<ServerDiscoveryPublicationState> getPublicationState(
    ServerDiscoveryPublicationTarget target,
  ) async {
    try {
      final visibility = await _matrixClient.getRoomVisibilityOnDirectory(
        target.identifier,
      );
      return ServerDiscoveryPublicationState(
        target: target,
        visibility: _publicationVisibilityFromMatrix(visibility),
        canManage: target.canManage,
        failureKind: target.canManage
            ? null
            : ServerDiscoveryFailureKind.permissionDenied,
      );
    } on matrix.MatrixException catch (error) {
      return ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.unknown,
        canManage: target.canManage,
        failureKind: _publicationFailureFromMatrix(error),
        matrixErrorCode: error.errcode,
      );
    } catch (_) {
      return ServerDiscoveryPublicationState(
        target: target,
        visibility: ServerDiscoveryPublicationVisibility.unknown,
        canManage: target.canManage,
        failureKind: ServerDiscoveryFailureKind.networkFailure,
      );
    }
  }

  @override
  Future<ServerDiscoveryPublicationResult> publish(
    ServerDiscoveryPublicationTarget target,
  ) {
    return _setPublication(
      target,
      matrix.Visibility.public,
      ServerDiscoveryPublicationOutcome.published,
      ServerDiscoveryPublicationOutcome.alreadyPublished,
    );
  }

  @override
  Future<ServerDiscoveryPublicationResult> unpublish(
    ServerDiscoveryPublicationTarget target,
  ) {
    return _setPublication(
      target,
      matrix.Visibility.private,
      ServerDiscoveryPublicationOutcome.unpublished,
      ServerDiscoveryPublicationOutcome.alreadyUnpublished,
    );
  }

  Future<ServerDiscoveryPublicationResult> _setPublication(
    ServerDiscoveryPublicationTarget target,
    matrix.Visibility visibility,
    ServerDiscoveryPublicationOutcome successOutcome,
    ServerDiscoveryPublicationOutcome noOpOutcome,
  ) async {
    if (!target.canManage) {
      final result = ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.permissionDenied,
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: ServerDiscoveryPublicationVisibility.unknown,
          canManage: false,
          failureKind: ServerDiscoveryFailureKind.permissionDenied,
        ),
      );
      _logPublication(target, result);
      return result;
    }

    final current = await getPublicationState(target);
    final desiredVisibility = _publicationVisibilityFromMatrix(visibility);
    if (current.visibility == desiredVisibility) {
      final result = ServerDiscoveryPublicationResult(
        outcome: noOpOutcome,
        state: current,
        matrixErrorCode: current.matrixErrorCode,
      );
      _logPublication(target, result);
      return result;
    }

    try {
      await _matrixClient.setRoomVisibilityOnDirectory(
        target.identifier,
        visibility: visibility,
      );
      final state = ServerDiscoveryPublicationState(
        target: target,
        visibility: desiredVisibility,
        canManage: target.canManage,
      );
      final result = ServerDiscoveryPublicationResult(
        outcome: successOutcome,
        state: state,
      );
      _logPublication(target, result);
      return result;
    } on matrix.MatrixException catch (error) {
      final result = ServerDiscoveryPublicationResult(
        outcome: _publicationOutcomeFromMatrix(error),
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: current.visibility,
          canManage: target.canManage,
          failureKind: _publicationFailureFromMatrix(error),
          matrixErrorCode: error.errcode,
        ),
        matrixErrorCode: error.errcode,
      );
      _logPublication(target, result);
      return result;
    } catch (_) {
      final result = ServerDiscoveryPublicationResult(
        outcome: ServerDiscoveryPublicationOutcome.networkFailure,
        state: ServerDiscoveryPublicationState(
          target: target,
          visibility: current.visibility,
          canManage: target.canManage,
          failureKind: ServerDiscoveryFailureKind.networkFailure,
        ),
      );
      _logPublication(target, result);
      return result;
    }
  }

  Future<matrix.QueryPublicRoomsResponse> _queryPublicRooms(
    ServerDiscoveryRequest request,
  ) {
    return _matrixClient.queryPublicRooms(
      server: directoryServerParameterForScope(scope),
      filter: matrix.PublicRoomQueryFilter(
        genericSearchTerm: request.hasSearch ? request.normalizedQuery : null,
        roomTypes: request.filter.matrixRoomTypes,
      ),
      includeAllNetworks: false,
      limit: request.limit,
      since: request.since,
    );
  }

  Future<ServerDiscoveryPage> _fetchPublicRoomsFallback(
    ServerDiscoveryRequest request,
  ) async {
    try {
      final response = await _matrixClient.getPublicRooms(
        server: directoryServerParameterForScope(scope),
        limit: request.limit,
        since: request.since,
      );
      final entries = response.chunk
          .map(_entryFromChunk)
          .where((entry) => entry.matchesFilter(request.filter))
          .toList();
      final page = ServerDiscoveryPage(
        scope: scope,
        request: request,
        entries: entries,
        nextBatch: response.nextBatch,
        prevBatch: response.prevBatch,
        totalEstimate: response.totalRoomCountEstimate,
      );
      Log.i(
        ServerDiscoveryLogFormatter.fetchSuccess(
          scope: scope,
          request: request,
          resultCount: entries.length,
          hasMore: page.hasMore,
        ),
        category: LogCategory.matrix,
        source: 'server-discovery',
      );
      return page;
    } on matrix.MatrixException catch (error) {
      _logFetchFailure(request, error.errcode);
      throw _discoveryErrorFromMatrixException(error);
    } catch (_) {
      _logFetchFailure(request, null);
      throw const ServerDiscoveryError(
        kind: ServerDiscoveryFailureKind.networkFailure,
        message: 'Could not reach the homeserver directory.',
      );
    }
  }

  ServerDiscoveryEntry _entryFromChunk(matrix.PublishedRoomsChunk chunk) {
    return ServerDiscoveryEntry.fromDirectory(
      roomId: chunk.roomId,
      roomType: chunk.roomType,
      name: chunk.name,
      topic: chunk.topic,
      avatarUrl: _avatarUrlForKnownEntry(chunk.roomId, chunk.avatarUrl),
      memberCount: chunk.numJoinedMembers,
      canonicalAlias: chunk.canonicalAlias,
      joinRule: chunk.joinRule,
      alreadyJoined:
          client.hasRoom(chunk.roomId) || client.hasSpace(chunk.roomId),
      sourceAccountId: scope.accountId,
      worldReadable: chunk.worldReadable,
      guestCanJoin: chunk.guestCanJoin,
    );
  }

  Future<List<matrix.SpaceRoomsChunk$2>> _restrictedSpaceChildChunks(
    MatrixSpace space,
    ServerDiscoveryRequest request,
  ) async {
    try {
      final response = await _matrixClient.getSpaceHierarchy(
        space.identifier,
        maxDepth: 1,
      );
      return response.rooms
          .where((chunk) => chunk.roomId != space.identifier)
          .where((chunk) => chunk.roomType != serverDiscoverySpaceRoomType)
          .where(
            (chunk) =>
                ServerDiscoveryJoinRule.fromRaw(chunk.joinRule) ==
                ServerDiscoveryJoinRule.restricted,
          )
          .toList(growable: false);
    } on matrix.MatrixException catch (error) {
      Log.w(
        ServerDiscoveryLogFormatter.supplementalFailure(
          scope: scope,
          request: request,
          matrixErrorCode: error.errcode,
        ),
        category: LogCategory.matrix,
        source: 'server-discovery',
      );
      return const [];
    } catch (_) {
      Log.w(
        ServerDiscoveryLogFormatter.supplementalFailure(
          scope: scope,
          request: request,
          matrixErrorCode: null,
        ),
        category: LogCategory.matrix,
        source: 'server-discovery',
      );
      return const [];
    }
  }

  ServerDiscoveryEntry? _entryFromSpaceChildChunk(
    MatrixSpace parentSpace,
    matrix.SpaceRoomsChunk$2 chunk,
  ) {
    if (chunk.roomId.trim().isEmpty) {
      return null;
    }

    return ServerDiscoveryEntry.fromSpaceChild(
      roomId: chunk.roomId,
      roomType: chunk.roomType,
      name: chunk.name,
      topic: chunk.topic,
      avatarUrl: _avatarUrlForKnownEntry(chunk.roomId, chunk.avatarUrl),
      memberCount: chunk.numJoinedMembers,
      canonicalAlias: chunk.canonicalAlias,
      joinRule: chunk.joinRule,
      alreadyJoined:
          client.hasRoom(chunk.roomId) || client.hasSpace(chunk.roomId),
      sourceAccountId: scope.accountId,
      worldReadable: chunk.worldReadable,
      guestCanJoin: chunk.guestCanJoin,
      via: _spaceChildVia(parentSpace, chunk.roomId),
      parentSpaceId: parentSpace.identifier,
      parentSpaceName: parentSpace.displayName,
    );
  }

  Uri? _avatarUrlForKnownEntry(String roomId, Uri? fallback) {
    final localRoom = client.getRoom(roomId);
    if (localRoom is MatrixRoom) {
      return localRoom.matrixRoom.avatar ?? fallback;
    }
    final localSpace = client.getSpace(roomId);
    if (localSpace is MatrixSpace) {
      return localSpace.matrixRoom.avatar ?? fallback;
    }
    return fallback;
  }

  static String directoryEntryAddress(ServerDiscoveryEntry entry) {
    final alias = entry.canonicalAlias?.trim();
    if (alias != null && alias.isNotEmpty) {
      return alias;
    }
    return entry.roomId.trim();
  }

  static List<String>? directoryEntryVia(
    ServerDiscoveryEntry entry,
    ServerDiscoveryScope scope,
  ) {
    final uniqueServers = <String>[];
    for (final server in [
      ...entry.via,
      scope.homeserver,
      _serverNameFromMatrixIdentifier(entry.canonicalAlias),
      _serverNameFromMatrixIdentifier(entry.roomId),
    ]) {
      final normalized = server?.trim();
      if (normalized == null || normalized.isEmpty) {
        continue;
      }
      if (!uniqueServers.contains(normalized)) {
        uniqueServers.add(normalized);
      }
    }
    return uniqueServers.isEmpty ? null : uniqueServers;
  }

  static List<String> _spaceChildVia(MatrixSpace parentSpace, String roomId) {
    final viaContent = parentSpace.matrixRoom
        .getState(matrix.EventTypes.SpaceChild, roomId)
        ?.content['via'];
    if (viaContent is! List) {
      return const [];
    }
    return viaContent.whereType<String>().toList(growable: false);
  }

  static bool _matchesSupplementalSearch(
    ServerDiscoveryEntry entry,
    ServerDiscoveryRequest request,
  ) {
    final query = request.normalizedQuery.toLowerCase();
    if (query.isEmpty) {
      return true;
    }
    return [
      entry.name,
      entry.topic,
      entry.canonicalAlias,
    ].whereType<String>().any((value) => value.toLowerCase().contains(query));
  }

  static String _addressWithVia(String address, List<String>? via) {
    if (via == null || via.isEmpty) {
      return address;
    }
    return '$address?via=${via.join(",")}';
  }

  ServerDiscoveryJoinResult _joinResult(
    ServerDiscoveryEntry entry,
    ServerDiscoveryJoinOutcome outcome, {
    String? matrixErrorCode,
  }) {
    Log.i(
      ServerDiscoveryLogFormatter.joinOutcome(
        scope: scope,
        entry: entry,
        outcome: outcome,
        matrixErrorCode: matrixErrorCode,
      ),
      category: LogCategory.matrix,
      source: 'server-discovery',
    );
    return ServerDiscoveryJoinResult(
      outcome: outcome,
      matrixErrorCode: matrixErrorCode,
    );
  }

  void _logFetchFailure(
    ServerDiscoveryRequest request,
    String? matrixErrorCode,
  ) {
    Log.w(
      ServerDiscoveryLogFormatter.fetchFailure(
        scope: scope,
        request: request,
        matrixErrorCode: matrixErrorCode,
      ),
      category: LogCategory.matrix,
      source: 'server-discovery',
    );
  }

  void _logPublication(
    ServerDiscoveryPublicationTarget target,
    ServerDiscoveryPublicationResult result,
  ) {
    Log.i(
      ServerDiscoveryLogFormatter.publicationOutcome(
        scope: scope,
        target: target,
        outcome: result.outcome,
        matrixErrorCode: result.matrixErrorCode,
      ),
      category: LogCategory.matrix,
      source: 'server-discovery',
    );
  }

  static ServerDiscoveryScope _buildScope(MatrixClient client) {
    final mx = client.matrixClient;
    final userId = client.self?.identifier ?? mx.userID;
    final homeserver =
        _serverNameFromUserId(userId) ??
        _serverNameFromUri(mx.homeserver ?? mx.baseUri) ??
        'unknown';
    return ServerDiscoveryScope(
      accountId: userId ?? client.identifier,
      homeserver: homeserver,
      baseUrl: mx.baseUri,
    );
  }

  static String? directoryServerParameterForScope(ServerDiscoveryScope _) {
    // Discover is scoped to the authenticated account's own homeserver. Passing
    // that same server name back through the Matrix `server` parameter turns the
    // request into a remote-directory lookup, which can miss freshly published
    // local rooms on delegated homeservers.
    return null;
  }

  static String? _serverNameFromUserId(String? userId) {
    if (userId == null || !userId.startsWith('@')) {
      return null;
    }
    final separator = userId.indexOf(':');
    if (separator == -1 || separator + 1 >= userId.length) {
      return null;
    }
    return userId.substring(separator + 1);
  }

  static String? _serverNameFromUri(Uri? uri) {
    if (uri == null) {
      return null;
    }
    if (uri.host.isNotEmpty) {
      return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    }
    final text = uri.toString();
    return text.isEmpty ? null : text;
  }

  static String? _serverNameFromMatrixIdentifier(String? identifier) {
    final value = identifier?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    final separator = value.indexOf(':');
    if (separator == -1 || separator + 1 >= value.length) {
      return null;
    }
    return value.substring(separator + 1);
  }

  static ServerDiscoveryError _discoveryErrorFromMatrixException(
    matrix.MatrixException error,
  ) {
    return ServerDiscoveryError(
      kind: switch (error.error) {
        matrix.MatrixError.M_UNKNOWN_TOKEN =>
          ServerDiscoveryFailureKind.authenticationInvalid,
        matrix.MatrixError.M_FORBIDDEN =>
          ServerDiscoveryFailureKind.serverRefused,
        matrix.MatrixError.M_NOT_FOUND =>
          ServerDiscoveryFailureKind.unavailable,
        matrix.MatrixError.M_BAD_JSON ||
        matrix.MatrixError.M_NOT_JSON ||
        matrix.MatrixError.M_INVALID_PARAM =>
          ServerDiscoveryFailureKind.malformedResponse,
        _ => ServerDiscoveryFailureKind.unknown,
      },
      message: 'Could not load Discover results.',
      matrixErrorCode: error.errcode,
    );
  }

  static ServerDiscoveryJoinOutcome _joinOutcomeFromMatrixException(
    matrix.MatrixException error,
  ) {
    final message = error.errorMessage.toLowerCase();
    if (error.error == matrix.MatrixError.M_NOT_FOUND) {
      return ServerDiscoveryJoinOutcome.staleEntry;
    }
    if (error.error == matrix.MatrixError.M_FORBIDDEN &&
        message.contains('ban')) {
      return ServerDiscoveryJoinOutcome.bannedUser;
    }
    if (error.error == matrix.MatrixError.M_FORBIDDEN) {
      return ServerDiscoveryJoinOutcome.serverRefused;
    }
    return ServerDiscoveryJoinOutcome.failed;
  }

  static ServerDiscoveryFailureKind _publicationFailureFromMatrix(
    matrix.MatrixException error,
  ) {
    return switch (error.error) {
      matrix.MatrixError.M_FORBIDDEN =>
        ServerDiscoveryFailureKind.serverPolicyDenied,
      matrix.MatrixError.M_NOT_FOUND => ServerDiscoveryFailureKind.unavailable,
      matrix.MatrixError.M_UNKNOWN_TOKEN =>
        ServerDiscoveryFailureKind.authenticationInvalid,
      _ => ServerDiscoveryFailureKind.unknown,
    };
  }

  static ServerDiscoveryPublicationOutcome _publicationOutcomeFromMatrix(
    matrix.MatrixException error,
  ) {
    return switch (error.error) {
      matrix.MatrixError.M_FORBIDDEN =>
        ServerDiscoveryPublicationOutcome.serverPolicyDenied,
      matrix.MatrixError.M_NOT_FOUND =>
        ServerDiscoveryPublicationOutcome.unavailable,
      _ => ServerDiscoveryPublicationOutcome.failed,
    };
  }

  static ServerDiscoveryPublicationVisibility _publicationVisibilityFromMatrix(
    matrix.Visibility? visibility,
  ) {
    return switch (visibility) {
      matrix.Visibility.public => ServerDiscoveryPublicationVisibility.public,
      matrix.Visibility.private => ServerDiscoveryPublicationVisibility.private,
      null => ServerDiscoveryPublicationVisibility.unknown,
    };
  }
}
