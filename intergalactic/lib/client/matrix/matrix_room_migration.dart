import 'dart:async';

import 'package:collection/collection.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:matrix/matrix.dart' as matrix;

/// The Matrix successor recorded by an `m.room.tombstone` state event.
///
/// A room upgrade never changes a room in place. This value is deliberately
/// derived from the server state instead of a local migration journal so it
/// also recovers upgrades made by older versions of the app.
String? matrixRoomMigrationSuccessorId(MatrixRoom room) {
  final replacement = room.matrixRoom.extinctInformations?.replacementRoom;
  if (replacement == null || replacement.trim().isEmpty) {
    return null;
  }
  return replacement;
}

/// Network-backed recovery must not leave the settings page in a permanent
/// loading state when sync is offline or a homeserver request stalls.
const matrixRoomMigrationOperationTimeout = Duration(seconds: 30);

Future<T> _matrixRoomMigrationWithTimeout<T>(
  Future<T> operation,
  String description,
) {
  return operation.timeout(
    matrixRoomMigrationOperationTimeout,
    onTimeout: () => throw TimeoutException(
      '$description did not finish within '
      '${matrixRoomMigrationOperationTimeout.inSeconds} seconds. '
      'Check the homeserver connection and try recovery again.',
    ),
  );
}

/// Returns a safe, bounded failure label for migration diagnostics and UI.
/// Do not expose raw Matrix response bodies or room/member data here.
String matrixRoomMigrationFailureLabel(Object error) {
  if (error is matrix.MatrixException) return error.errcode;
  if (error is TimeoutException) return 'timeout';
  final type = error.runtimeType.toString();
  if (type.contains('SocketException') || type.contains('HttpException')) {
    return 'network';
  }
  return type;
}

/// Reads the predecessor room ID recorded in a successor's `m.room.create`.
///
/// Matrix clients must treat state content as untrusted. A malformed or absent
/// predecessor is therefore simply not a navigable history link.
String? matrixRoomMigrationPredecessorId(MatrixRoom room) {
  final create = room.matrixRoom.getState(matrix.EventTypes.RoomCreate);
  return matrixRoomMigrationPredecessorIdFromCreateContent(create?.content);
}

String? matrixRoomMigrationPredecessorIdFromCreateContent(
  Map<String, Object?>? content,
) {
  final predecessor = content?['predecessor'];
  if (predecessor is! Map) {
    return null;
  }
  final roomId = predecessor['room_id'];
  if (roomId is! String || roomId.trim().isEmpty) {
    return null;
  }
  return roomId;
}

/// Selects the source room creators that must be sent as additional creators
/// when the current user performs the upgrade.
List<String> matrixRoomMigrationAdditionalCreatorIds({
  required Iterable<String> sourceCreatorIds,
  required String? selfId,
}) {
  return sourceCreatorIds.where((id) => id != selfId).toSet().sorted();
}

/// Keeps the source room's shared permission rules while respecting the
/// immutable creator rules introduced by room version 12.
Map<String, Object?> matrixRoomMigrationPowerLevelsForSuccessor({
  required Map<String, Object?> sourcePowerLevels,
  required Iterable<String> successorCreatorIds,
  required String? successorRoomVersion,
  required String? selfId,
  required int sourceUserPowerLevel,
}) {
  final result = _matrixRoomMigrationCopyMap(sourcePowerLevels);
  if ((int.tryParse(successorRoomVersion ?? '') ?? 0) < 12) {
    return result;
  }

  final creators = successorCreatorIds.toSet();
  final users = result['users'];
  final sanitizedUsers = <String, Object?>{
    if (users is Map)
      for (final entry in users.entries)
        if (!creators.contains(entry.key)) entry.key.toString(): entry.value,
  };
  if (selfId != null &&
      !creators.contains(selfId) &&
      sourceUserPowerLevel > 0) {
    sanitizedUsers[selfId] = sourceUserPowerLevel;
  }
  if (users is Map || sanitizedUsers.isNotEmpty) {
    result['users'] = sanitizedUsers;
  }
  return result;
}

/// Computes source members who still need an invite to the successor.
///
/// Both joined and already-invited successor members are deliberately skipped:
/// rerunning a partial migration is safe and does not turn an invite retry into
/// a second server-side migration.
List<String> matrixRoomMigrationMissingMemberIds({
  required Iterable<String> sourceJoinedMemberIds,
  required Iterable<String> successorJoinedOrInvitedMemberIds,
  required String? selfId,
}) {
  final present = successorJoinedOrInvitedMemberIds.toSet();
  return sourceJoinedMemberIds
      .where((id) => id != selfId && !present.contains(id))
      .toSet()
      .sorted();
}

/// Recovery writes only when power-level state is absent or its content still
/// matches what this client observed before a failed initial restore. Changed
/// content is treated as another administrator's edit and never overwritten.
bool matrixRoomMigrationShouldRestorePowerLevels({
  required bool isRecovery,
  required Map<String, Object?>? successorPowerLevels,
  Map<String, Object?>? failedInitialPowerLevels,
}) =>
    !isRecovery ||
    successorPowerLevels == null ||
    (failedInitialPowerLevels != null &&
        const DeepCollectionEquality().equals(
          successorPowerLevels,
          failedInitialPowerLevels,
        ));

// A failed first write can be retried only while the successor's state content
// is unchanged. This per-client, in-memory evidence never authorizes a blind
// overwrite after a restart or another administrator's edit.
final Expando<Map<String, Map<String, Object?>>> _pendingPermissionRestores =
    Expando();

class MatrixRoomMigrationResult {
  const MatrixRoomMigrationResult({
    required this.sourceRoomId,
    required this.successorRoomId,
    required this.invitedMemberIds,
    required this.failedMemberIds,
    this.failedSpaceIds = const [],
    this.permissionsRestored = true,
    this.successorPermissionsPreserved = false,
    this.spaceFailure,
    this.permissionFailure,
  });

  final String sourceRoomId;
  final String successorRoomId;
  final List<String> invitedMemberIds;

  /// User IDs only: do not persist server error text or member data in logs.
  final List<String> failedMemberIds;

  /// Spaces whose child state could not be moved to the successor.
  final List<String> failedSpaceIds;

  /// A safe category or Matrix errcode for the first failed Space write.
  final String? spaceFailure;

  /// Whether the permission step succeeded or existing successor state was
  /// deliberately preserved. False means the attempted write failed.
  final bool permissionsRestored;

  /// Recovery left existing successor power levels untouched because their
  /// provenance could not be safely distinguished from later admin edits.
  final bool successorPermissionsPreserved;

  /// A safe category or Matrix errcode for the failed power-level write.
  final String? permissionFailure;

  bool get isComplete =>
      failedMemberIds.isEmpty && failedSpaceIds.isEmpty && permissionsRestored;
}

class _MatrixRoomMigrationSpaceSnapshot {
  const _MatrixRoomMigrationSpaceSnapshot({
    required this.space,
    required this.via,
    required this.order,
    required this.suggested,
  });

  final MatrixSpace space;
  final List<String> via;
  final String order;
  final bool? suggested;
}

/// Matrix room-upgrade orchestration.
///
/// The protocol creates and tombstones rooms atomically, but it does not move
/// members. This service treats the post-upgrade work as resumable: a failed
/// or interrupted invite pass can be rerun from the tombstoned source room.
class MatrixRoomMigration {
  const MatrixRoomMigration(this.client);

  final MatrixClient client;

  Future<MatrixRoomMigrationResult> upgrade({
    required MatrixRoom source,
    required String targetVersion,
  }) async {
    if (matrixRoomMigrationSuccessorId(source) != null) {
      return recover(source: source);
    }

    // Fetch before the irreversible endpoint. requestParticipants returns the
    // server's complete page sequence rather than trusting the sidebar cache.
    final sourceMembers = await _joinedMemberIds(source.matrixRoom);
    final sourceSpaces = _spacesContaining(source.identifier);
    final sourcePowerLevels = _copyPowerLevels(source.matrixRoom);
    final sourceUserPowerLevel = source.matrixRoom.getPowerLevelByUserId(
      client.getMatrixClient().userID!,
    );
    final additionalCreators = matrixRoomMigrationAdditionalCreatorIds(
      sourceCreatorIds: source.matrixRoom.creatorUserIds,
      selfId: client.getMatrixClient().userID,
    );
    final successorRoomId = await client.getMatrixClient().upgradeRoom(
      source.identifier,
      targetVersion,
      additionalCreators: additionalCreators,
    );
    return _inviteMissingMembers(
      source: source,
      successorRoomId: successorRoomId,
      sourceMemberIds: sourceMembers,
      sourceSpaces: sourceSpaces,
      sourcePowerLevels: sourcePowerLevels,
      sourceUserPowerLevel: sourceUserPowerLevel,
      isRecovery: false,
    );
  }

  Future<MatrixRoomMigrationResult> recover({
    required MatrixRoom source,
  }) async {
    final successorRoomId = matrixRoomMigrationSuccessorId(source);
    if (successorRoomId == null) {
      throw StateError('This room has no Matrix upgrade successor.');
    }
    final sourceMembers = await _joinedMemberIds(source.matrixRoom);
    return _inviteMissingMembers(
      source: source,
      successorRoomId: successorRoomId,
      sourceMemberIds: sourceMembers,
      sourceSpaces: _spacesContaining(source.identifier),
      sourcePowerLevels: _copyPowerLevels(source.matrixRoom),
      sourceUserPowerLevel: source.matrixRoom.getPowerLevelByUserId(
        client.getMatrixClient().userID!,
      ),
      isRecovery: true,
    );
  }

  Future<MatrixRoomMigrationResult> _inviteMissingMembers({
    required MatrixRoom source,
    required String successorRoomId,
    required List<String> sourceMemberIds,
    required List<_MatrixRoomMigrationSpaceSnapshot> sourceSpaces,
    required Map<String, Object?>? sourcePowerLevels,
    required int sourceUserPowerLevel,
    required bool isRecovery,
  }) async {
    final matrixClient = client.getMatrixClient();
    var successor = matrixClient.getRoomById(successorRoomId);
    if (successor == null) {
      await _matrixRoomMigrationWithTimeout(
        matrixClient.waitForRoomInSync(successorRoomId),
        'Waiting for the successor room to sync',
      );
      successor = matrixClient.getRoomById(successorRoomId);
    }
    if (successor == null) {
      throw StateError('The Matrix successor room did not arrive in sync.');
    }

    final successorMembers = await _matrixRoomMigrationWithTimeout(
      successor.requestParticipants(
        const [matrix.Membership.join, matrix.Membership.invite],
        true,
        true,
      ),
      'Reading successor room members',
    );
    final missing = matrixRoomMigrationMissingMemberIds(
      sourceJoinedMemberIds: sourceMemberIds,
      successorJoinedOrInvitedMemberIds: successorMembers.map(
        (user) => user.id,
      ),
      selfId: matrixClient.userID,
    );
    final invited = <String>[];
    final failed = <String>[];
    for (final userId in missing) {
      try {
        await _matrixRoomMigrationWithTimeout(
          successor.invite(userId),
          'Inviting a missing room member',
        );
        invited.add(userId);
      } catch (_) {
        failed.add(userId);
      }
    }

    final failedSpaceIds = <String>[];
    String? spaceFailure;
    for (final snapshot in sourceSpaces) {
      try {
        if (!snapshot.space.matrixRoom.canChangeStateEvent(
          matrix.EventTypes.SpaceChild,
        )) {
          failedSpaceIds.add(snapshot.space.identifier);
          spaceFailure ??= 'M_FORBIDDEN';
          continue;
        }
        await _matrixRoomMigrationWithTimeout(
          snapshot.space.matrixRoom.setSpaceChild(
            successorRoomId,
            via: snapshot.via.isEmpty ? null : snapshot.via,
            order: snapshot.order.isEmpty ? null : snapshot.order,
            suggested: snapshot.suggested,
          ),
          'Adding the successor room to a Space',
        );
        await _matrixRoomMigrationWithTimeout(
          snapshot.space.matrixRoom.removeSpaceChild(source.identifier),
          'Removing the predecessor room from a Space',
        );
      } catch (error) {
        failedSpaceIds.add(snapshot.space.identifier);
        spaceFailure ??= matrixRoomMigrationFailureLabel(error);
      }
    }

    var permissionsRestored = true;
    var successorPermissionsPreserved = false;
    String? permissionFailure;
    final pendingPermissionRestores =
        _pendingPermissionRestores[matrixClient] ??
        <String, Map<String, Object?>>{};
    _pendingPermissionRestores[matrixClient] = pendingPermissionRestores;
    final successorPowerLevels = successor
        .getState(matrix.EventTypes.RoomPowerLevels)
        ?.content;
    if (sourcePowerLevels != null &&
        matrixRoomMigrationShouldRestorePowerLevels(
          isRecovery: isRecovery,
          successorPowerLevels: successorPowerLevels,
          failedInitialPowerLevels: pendingPermissionRestores[successorRoomId],
        )) {
      try {
        final powerLevels = matrixRoomMigrationPowerLevelsForSuccessor(
          sourcePowerLevels: sourcePowerLevels,
          successorCreatorIds: successor.creatorUserIds,
          successorRoomVersion: successor.roomVersion,
          selfId: matrixClient.userID,
          sourceUserPowerLevel: sourceUserPowerLevel,
        );
        await _matrixRoomMigrationWithTimeout(
          matrixClient.setRoomStateWithKey(
            successorRoomId,
            matrix.EventTypes.RoomPowerLevels,
            '',
            powerLevels,
          ),
          'Restoring successor room permissions',
        );
        pendingPermissionRestores.remove(successorRoomId);
      } catch (error) {
        if (!isRecovery && successorPowerLevels != null) {
          pendingPermissionRestores[successorRoomId] =
              _matrixRoomMigrationCopyMap(successorPowerLevels);
        }
        permissionsRestored = false;
        permissionFailure = matrixRoomMigrationFailureLabel(error);
      }
    } else if (isRecovery) {
      successorPermissionsPreserved =
          sourcePowerLevels != null && successorPowerLevels != null;
      pendingPermissionRestores.remove(successorRoomId);
    }

    Log.i(
      'Matrix room migration recovery completed '
      'invited=${invited.length} failedMembers=${failed.length} '
      'failedSpaces=${failedSpaceIds.length} '
      'spaceFailure=${spaceFailure ?? 'none'} '
      'permissionFailure=${permissionFailure ?? 'none'}',
    );

    return MatrixRoomMigrationResult(
      sourceRoomId: source.identifier,
      successorRoomId: successorRoomId,
      invitedMemberIds: invited,
      failedMemberIds: failed,
      failedSpaceIds: failedSpaceIds,
      permissionsRestored: permissionsRestored,
      successorPermissionsPreserved: successorPermissionsPreserved,
      spaceFailure: spaceFailure,
      permissionFailure: permissionFailure,
    );
  }

  List<_MatrixRoomMigrationSpaceSnapshot> _spacesContaining(String roomId) {
    return client.spaces
        .whereType<MatrixSpace>()
        .map((space) {
          final child = space.matrixRoom.spaceChildren.firstWhereOrNull(
            (candidate) => candidate.roomId == roomId,
          );
          if (child == null) return null;
          return _MatrixRoomMigrationSpaceSnapshot(
            space: space,
            via: List<String>.from(child.via),
            order: child.order,
            suggested: child.suggested,
          );
        })
        .nonNulls
        .toList(growable: false);
  }

  Map<String, Object?>? _copyPowerLevels(matrix.Room source) {
    final content = source.getState(matrix.EventTypes.RoomPowerLevels)?.content;
    return content == null ? null : _matrixRoomMigrationCopyMap(content);
  }

  Future<List<String>> _joinedMemberIds(matrix.Room room) async {
    final members = await _matrixRoomMigrationWithTimeout(
      room.requestParticipants(const [matrix.Membership.join], true, true),
      'Reading source room members',
    );
    return members.map((user) => user.id).toSet().sorted();
  }
}

Map<String, Object?> _matrixRoomMigrationCopyMap(
  Map<dynamic, dynamic> content,
) {
  return content.map(
    (key, value) =>
        MapEntry(key.toString(), _matrixRoomMigrationCopyValue(value)),
  );
}

Object? _matrixRoomMigrationCopyValue(Object? value) {
  if (value is Map) return _matrixRoomMigrationCopyMap(value);
  if (value is List) {
    return value.map(_matrixRoomMigrationCopyValue).toList(growable: false);
  }
  return value;
}
