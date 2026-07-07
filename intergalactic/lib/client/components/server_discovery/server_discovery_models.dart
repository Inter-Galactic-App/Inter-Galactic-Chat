const serverDiscoverySpaceRoomType = 'm.space';

const serverDiscoveryKnownRoomTypes = <String?>[
  null,
  'chat.commet.calendar',
  'chat.commet.photo_album',
  'chat.intergalactic.app.forum',
  'org.matrix.msc3417.call',
];

const Object _entryUnset = Object();

enum ServerDiscoveryFilter {
  all,
  rooms,
  spaces;

  List<String?>? get matrixRoomTypes {
    return switch (this) {
      ServerDiscoveryFilter.all => null,
      ServerDiscoveryFilter.rooms => serverDiscoveryKnownRoomTypes,
      ServerDiscoveryFilter.spaces => const [serverDiscoverySpaceRoomType],
    };
  }
}

enum ServerDiscoveryAccessFilter {
  all,
  unjoined,
}

enum ServerDiscoverySortMode {
  defaultOrder,
  alphabetical,
  space,
  joinedStatus,
}

enum ServerDiscoveryEntryType {
  room,
  space;
}

enum ServerDiscoveryEntrySource {
  directory,
  spaceChild;
}

enum ServerDiscoveryJoinRule {
  public,
  knock,
  invite,
  restricted,
  knockRestricted,
  private,
  unknown;

  static ServerDiscoveryJoinRule fromRaw(String? value) {
    return switch (value) {
      null || '' => ServerDiscoveryJoinRule.public,
      'public' => ServerDiscoveryJoinRule.public,
      'knock' => ServerDiscoveryJoinRule.knock,
      'invite' => ServerDiscoveryJoinRule.invite,
      'restricted' => ServerDiscoveryJoinRule.restricted,
      'knock_restricted' => ServerDiscoveryJoinRule.knockRestricted,
      'private' => ServerDiscoveryJoinRule.private,
      _ => ServerDiscoveryJoinRule.unknown,
    };
  }
}

enum ServerDiscoveryJoinRequirement {
  alreadyJoined,
  publicJoin,
  knockRequired,
  inviteRequired,
  restricted,
  unsupported,
  unavailable,
}

enum ServerDiscoveryJoinOutcome {
  alreadyJoined,
  joined,
  knockRequested,
  inviteRequired,
  restrictedRefused,
  serverRefused,
  bannedUser,
  unavailableRoom,
  unsupportedJoinRule,
  networkFailure,
  staleEntry,
  failed,
}

enum ServerDiscoveryFailureKind {
  unsupportedClient,
  authenticationInvalid,
  permissionDenied,
  serverPolicyDenied,
  serverRefused,
  unavailable,
  malformedResponse,
  networkFailure,
  unknown,
}

enum ServerDiscoveryPublicationOutcome {
  published,
  unpublished,
  alreadyPublished,
  alreadyUnpublished,
  permissionDenied,
  serverPolicyDenied,
  unavailable,
  networkFailure,
  unsupported,
  failed,
}

enum ServerDiscoveryPublicationVisibility {
  public,
  private,
  unknown,
}

class ServerDiscoveryScope {
  const ServerDiscoveryScope({
    required this.accountId,
    required this.homeserver,
    this.baseUrl,
  });

  final String accountId;
  final String homeserver;
  final Uri? baseUrl;

  String get cacheKey => '$accountId|$homeserver';

  @override
  bool operator ==(Object other) {
    return other is ServerDiscoveryScope &&
        other.accountId == accountId &&
        other.homeserver == homeserver &&
        other.baseUrl == baseUrl;
  }

  @override
  int get hashCode => Object.hash(accountId, homeserver, baseUrl);
}

class ServerDiscoveryRequest {
  static const Object _unset = Object();

  const ServerDiscoveryRequest({
    this.query = '',
    this.filter = ServerDiscoveryFilter.all,
    this.since,
    this.limit = 20,
  });

  final String query;
  final ServerDiscoveryFilter filter;
  final String? since;
  final int limit;

  String get normalizedQuery => query.trim();

  bool get hasSearch => normalizedQuery.isNotEmpty;

  ServerDiscoveryRequest copyWith({
    String? query,
    ServerDiscoveryFilter? filter,
    Object? since = _unset,
    int? limit,
  }) {
    return ServerDiscoveryRequest(
      query: query ?? this.query,
      filter: filter ?? this.filter,
      since: identical(since, _unset) ? this.since : since as String?,
      limit: limit ?? this.limit,
    );
  }
}

class ServerDiscoveryCacheKey {
  const ServerDiscoveryCacheKey({
    required this.scope,
    required this.request,
  });

  final ServerDiscoveryScope scope;
  final ServerDiscoveryRequest request;

  @override
  bool operator ==(Object other) {
    return other is ServerDiscoveryCacheKey &&
        other.scope == scope &&
        other.request.normalizedQuery == request.normalizedQuery &&
        other.request.filter == request.filter &&
        other.request.since == request.since &&
        other.request.limit == request.limit;
  }

  @override
  int get hashCode => Object.hash(
        scope,
        request.normalizedQuery,
        request.filter,
        request.since,
        request.limit,
      );
}

class ServerDiscoveryEntry {
  const ServerDiscoveryEntry({
    required this.roomId,
    required this.type,
    required this.name,
    required this.topic,
    required this.avatarUrl,
    required this.memberCount,
    required this.canonicalAlias,
    required this.rawRoomType,
    required this.rawJoinRule,
    required this.joinRule,
    required this.alreadyJoined,
    required this.sourceAccountId,
    required this.worldReadable,
    required this.guestCanJoin,
    this.source = ServerDiscoveryEntrySource.directory,
    this.via = const [],
    this.parentSpaceId,
    this.parentSpaceName,
    this.spaceGroupOrder,
  });

  factory ServerDiscoveryEntry.fromDirectory({
    required String roomId,
    required String? roomType,
    required String? name,
    required String? topic,
    required Uri? avatarUrl,
    required int memberCount,
    required String? canonicalAlias,
    required String? joinRule,
    required bool alreadyJoined,
    String? sourceAccountId,
    required bool worldReadable,
    required bool guestCanJoin,
    List<String> via = const [],
    String? parentSpaceId,
    String? parentSpaceName,
  }) {
    final type = roomType == serverDiscoverySpaceRoomType
        ? ServerDiscoveryEntryType.space
        : ServerDiscoveryEntryType.room;
    return ServerDiscoveryEntry(
      roomId: roomId,
      type: type,
      name: _trimOrNull(name),
      topic: _trimOrNull(topic),
      avatarUrl: avatarUrl,
      memberCount: memberCount,
      canonicalAlias: _trimOrNull(canonicalAlias),
      rawRoomType: roomType,
      rawJoinRule: joinRule,
      joinRule: ServerDiscoveryJoinRule.fromRaw(joinRule),
      alreadyJoined: alreadyJoined,
      sourceAccountId: _trimOrNull(sourceAccountId),
      worldReadable: worldReadable,
      guestCanJoin: guestCanJoin,
      via: _normalizedServerNames(via),
      parentSpaceId: _trimOrNull(parentSpaceId),
      parentSpaceName: _trimOrNull(parentSpaceName),
    );
  }

  factory ServerDiscoveryEntry.fromSpaceChild({
    required String roomId,
    required String? roomType,
    required String? name,
    required String? topic,
    required Uri? avatarUrl,
    required int memberCount,
    required String? canonicalAlias,
    required String? joinRule,
    required bool alreadyJoined,
    required String sourceAccountId,
    required bool worldReadable,
    required bool guestCanJoin,
    List<String> via = const [],
    String? parentSpaceId,
    String? parentSpaceName,
  }) {
    return ServerDiscoveryEntry.fromDirectory(
      roomId: roomId,
      roomType: roomType,
      name: name,
      topic: topic,
      avatarUrl: avatarUrl,
      memberCount: memberCount,
      canonicalAlias: canonicalAlias,
      joinRule: joinRule,
      alreadyJoined: alreadyJoined,
      sourceAccountId: sourceAccountId,
      worldReadable: worldReadable,
      guestCanJoin: guestCanJoin,
      via: via,
      parentSpaceId: parentSpaceId,
      parentSpaceName: parentSpaceName,
    ).copyWith(
      source: ServerDiscoveryEntrySource.spaceChild,
    );
  }

  final String roomId;
  final ServerDiscoveryEntryType type;
  final String? name;
  final String? topic;
  final Uri? avatarUrl;
  final int memberCount;
  final String? canonicalAlias;
  final String? rawRoomType;
  final String? rawJoinRule;
  final ServerDiscoveryJoinRule joinRule;
  final bool alreadyJoined;
  final String? sourceAccountId;
  final bool worldReadable;
  final bool guestCanJoin;
  final ServerDiscoveryEntrySource source;
  final List<String> via;
  final String? parentSpaceId;
  final String? parentSpaceName;
  final int? spaceGroupOrder;

  String get displayName {
    final label = name ?? canonicalAlias;
    if (label != null && label.isNotEmpty) {
      return label;
    }
    return type == ServerDiscoveryEntryType.space
        ? 'Unnamed space'
        : 'Unnamed room';
  }

  ServerDiscoveryJoinRequirement get joinRequirement {
    if (roomId.trim().isEmpty) {
      return ServerDiscoveryJoinRequirement.unavailable;
    }
    if (alreadyJoined) {
      return ServerDiscoveryJoinRequirement.alreadyJoined;
    }
    return switch (joinRule) {
      ServerDiscoveryJoinRule.public =>
        ServerDiscoveryJoinRequirement.publicJoin,
      ServerDiscoveryJoinRule.restricted =>
        ServerDiscoveryJoinRequirement.restricted,
      ServerDiscoveryJoinRule.knock ||
      ServerDiscoveryJoinRule.knockRestricted =>
        ServerDiscoveryJoinRequirement.knockRequired,
      ServerDiscoveryJoinRule.invite ||
      ServerDiscoveryJoinRule.private =>
        ServerDiscoveryJoinRequirement.inviteRequired,
      ServerDiscoveryJoinRule.unknown =>
        ServerDiscoveryJoinRequirement.unsupported,
    };
  }

  bool matchesFilter(ServerDiscoveryFilter filter) {
    return switch (filter) {
      ServerDiscoveryFilter.all => true,
      ServerDiscoveryFilter.rooms => type == ServerDiscoveryEntryType.room,
      ServerDiscoveryFilter.spaces => type == ServerDiscoveryEntryType.space,
    };
  }

  bool belongsToScope(ServerDiscoveryScope scope) {
    final accountId = sourceAccountId;
    return accountId == null || accountId == scope.accountId;
  }

  ServerDiscoveryEntry copyWith({
    bool? alreadyJoined,
    Object? avatarUrl = _entryUnset,
    String? sourceAccountId,
    ServerDiscoveryEntrySource? source,
    List<String>? via,
    Object? parentSpaceId = _entryUnset,
    Object? parentSpaceName = _entryUnset,
    Object? spaceGroupOrder = _entryUnset,
  }) {
    return ServerDiscoveryEntry(
      roomId: roomId,
      type: type,
      name: name,
      topic: topic,
      avatarUrl: identical(avatarUrl, _entryUnset)
          ? this.avatarUrl
          : avatarUrl as Uri?,
      memberCount: memberCount,
      canonicalAlias: canonicalAlias,
      rawRoomType: rawRoomType,
      rawJoinRule: rawJoinRule,
      joinRule: joinRule,
      alreadyJoined: alreadyJoined ?? this.alreadyJoined,
      sourceAccountId: sourceAccountId ?? this.sourceAccountId,
      worldReadable: worldReadable,
      guestCanJoin: guestCanJoin,
      source: source ?? this.source,
      via: via == null ? this.via : _normalizedServerNames(via),
      parentSpaceId: identical(parentSpaceId, _entryUnset)
          ? this.parentSpaceId
          : _trimOrNull(parentSpaceId as String?),
      parentSpaceName: identical(parentSpaceName, _entryUnset)
          ? this.parentSpaceName
          : _trimOrNull(parentSpaceName as String?),
      spaceGroupOrder: identical(spaceGroupOrder, _entryUnset)
          ? this.spaceGroupOrder
          : spaceGroupOrder as int?,
    );
  }
}

class ServerDiscoveryPage {
  const ServerDiscoveryPage({
    required this.scope,
    required this.request,
    required this.entries,
    this.nextBatch,
    this.prevBatch,
    this.totalEstimate,
  });

  final ServerDiscoveryScope scope;
  final ServerDiscoveryRequest request;
  final List<ServerDiscoveryEntry> entries;
  final String? nextBatch;
  final String? prevBatch;
  final int? totalEstimate;

  bool get hasMore => nextBatch != null && nextBatch!.isNotEmpty;
}

class ServerDiscoveryError implements Exception {
  const ServerDiscoveryError({
    required this.kind,
    required this.message,
    this.matrixErrorCode,
  });

  final ServerDiscoveryFailureKind kind;
  final String message;
  final String? matrixErrorCode;

  @override
  String toString() => message;
}

class ServerDiscoveryJoinResult {
  const ServerDiscoveryJoinResult({
    required this.outcome,
    this.matrixErrorCode,
  });

  final ServerDiscoveryJoinOutcome outcome;
  final String? matrixErrorCode;

  bool get success =>
      outcome == ServerDiscoveryJoinOutcome.joined ||
      outcome == ServerDiscoveryJoinOutcome.knockRequested ||
      outcome == ServerDiscoveryJoinOutcome.alreadyJoined;
}

class ServerDiscoveryPublicationTarget {
  const ServerDiscoveryPublicationTarget({
    required this.identifier,
    required this.type,
    required this.canManage,
  });

  final String identifier;
  final ServerDiscoveryEntryType type;
  final bool canManage;
}

class ServerDiscoveryPublicationState {
  const ServerDiscoveryPublicationState({
    required this.target,
    required this.visibility,
    required this.canManage,
    this.failureKind,
    this.matrixErrorCode,
  });

  final ServerDiscoveryPublicationTarget target;
  final ServerDiscoveryPublicationVisibility visibility;
  final bool canManage;
  final ServerDiscoveryFailureKind? failureKind;
  final String? matrixErrorCode;

  bool get isPublished =>
      visibility == ServerDiscoveryPublicationVisibility.public;

  bool get permissionDenied =>
      failureKind == ServerDiscoveryFailureKind.permissionDenied;

  bool get serverPolicyDenied =>
      failureKind == ServerDiscoveryFailureKind.serverPolicyDenied;
}

class ServerDiscoveryPublicationResult {
  const ServerDiscoveryPublicationResult({
    required this.outcome,
    this.state,
    this.matrixErrorCode,
  });

  final ServerDiscoveryPublicationOutcome outcome;
  final ServerDiscoveryPublicationState? state;
  final String? matrixErrorCode;

  bool get success =>
      outcome == ServerDiscoveryPublicationOutcome.published ||
      outcome == ServerDiscoveryPublicationOutcome.unpublished ||
      outcome == ServerDiscoveryPublicationOutcome.alreadyPublished ||
      outcome == ServerDiscoveryPublicationOutcome.alreadyUnpublished;
}

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

List<String> _normalizedServerNames(Iterable<String> values) {
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || result.contains(trimmed)) {
      continue;
    }
    result.add(trimmed);
  }
  return List.unmodifiable(result);
}
