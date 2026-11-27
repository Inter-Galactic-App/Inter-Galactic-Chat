import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_room_migration.dart';
import 'package:intergalactic/client/space.dart';
import 'package:matrix/matrix.dart' as matrix;

void main() {
  group('matrixRoomMigrationMissingMemberIds', () {
    test('invites only source members absent from the successor', () {
      expect(
        matrixRoomMigrationMissingMemberIds(
          sourceJoinedMemberIds: const [
            '@alice:example.org',
            '@bob:example.org',
            '@carol:example.org',
          ],
          successorJoinedOrInvitedMemberIds: const [
            '@alice:example.org',
            '@bob:example.org',
          ],
          selfId: '@alice:example.org',
        ),
        ['@carol:example.org'],
      );
    });

    test('is idempotent when a previous retry already invited a member', () {
      expect(
        matrixRoomMigrationMissingMemberIds(
          sourceJoinedMemberIds: const [
            '@alice:example.org',
            '@bob:example.org',
            '@carol:example.org',
            '@carol:example.org',
          ],
          successorJoinedOrInvitedMemberIds: const [
            '@bob:example.org',
            '@carol:example.org',
          ],
          selfId: '@alice:example.org',
        ),
        isEmpty,
      );
    });

    test('keeps a failed member eligible for a later recovery pass', () {
      expect(
        matrixRoomMigrationMissingMemberIds(
          sourceJoinedMemberIds: const [
            '@alice:example.org',
            '@bob:example.org',
            '@carol:example.org',
          ],
          successorJoinedOrInvitedMemberIds: const ['@bob:example.org'],
          selfId: '@alice:example.org',
        ),
        ['@carol:example.org'],
      );
    });
  });

  group('matrixRoomMigrationPredecessorIdFromCreateContent', () {
    test('returns the Matrix predecessor room ID', () {
      expect(
        matrixRoomMigrationPredecessorIdFromCreateContent({
          'predecessor': {
            'room_id': '!older:example.org',
            'event_id': r'$tombstone:example.org',
          },
        }),
        '!older:example.org',
      );
    });

    test('ignores malformed predecessor state', () {
      expect(
        matrixRoomMigrationPredecessorIdFromCreateContent({
          'predecessor': {'room_id': 3},
        }),
        isNull,
      );
    });
  });

  group('matrixRoomMigrationAdditionalCreatorIds', () {
    test('excludes the upgrading user and returns stable unique IDs', () {
      expect(
        matrixRoomMigrationAdditionalCreatorIds(
          sourceCreatorIds: const [
            '@zara:example.org',
            '@alice:example.org',
            '@zara:example.org',
          ],
          selfId: '@alice:example.org',
        ),
        ['@zara:example.org'],
      );
    });
  });

  group('matrixRoomMigrationPowerLevelsForSuccessor', () {
    test('removes immutable successor creators only for room version 12', () {
      final source = <String, Object?>{
        'users_default': 0,
        'users': <String, Object?>{
          '@alice:example.org': 100,
          '@moderator:example.org': 50,
        },
        'events': <String, Object?>{'m.room.name': 50},
      };

      expect(
        matrixRoomMigrationPowerLevelsForSuccessor(
          sourcePowerLevels: source,
          successorCreatorIds: const ['@alice:example.org'],
          successorRoomVersion: '12',
          selfId: '@alice:example.org',
          sourceUserPowerLevel: 100,
        ),
        {
          'users_default': 0,
          'users': {'@moderator:example.org': 50},
          'events': {'m.room.name': 50},
        },
      );
      expect(
        matrixRoomMigrationPowerLevelsForSuccessor(
          sourcePowerLevels: source,
          successorCreatorIds: const ['@alice:example.org'],
          successorRoomVersion: '11',
          selfId: '@alice:example.org',
          sourceUserPowerLevel: 100,
        )['users'],
        source['users'],
      );
      expect(source['users'], {
        '@alice:example.org': 100,
        '@moderator:example.org': 50,
      });
    });

    test(
      'restores an admin entry if the successor did not preserve creator',
      () {
        final result = matrixRoomMigrationPowerLevelsForSuccessor(
          sourcePowerLevels: <String, Object?>{
            'users': <String, Object?>{'@moderator:example.org': 50},
          },
          successorCreatorIds: const ['@other:example.org'],
          successorRoomVersion: '12',
          selfId: '@alice:example.org',
          sourceUserPowerLevel: 100,
        );

        expect((result['users'] as Map)['@alice:example.org'], 100);
      },
    );

    test('creates an admin entry when source power levels omit users', () {
      final result = matrixRoomMigrationPowerLevelsForSuccessor(
        sourcePowerLevels: <String, Object?>{'users_default': 0},
        successorCreatorIds: const ['@other:example.org'],
        successorRoomVersion: '12',
        selfId: '@alice:example.org',
        sourceUserPowerLevel: 100,
      );

      expect((result['users'] as Map)['@alice:example.org'], 100);
    });
  });

  group('matrixRoomMigrationShouldRestorePowerLevels', () {
    test('initial upgrade attempts the source permission restore', () {
      expect(
        matrixRoomMigrationShouldRestorePowerLevels(
          isRecovery: false,
          successorPowerLevels: {
            'users': {'@admin:example.org': 50},
          },
        ),
        isTrue,
      );
    });

    test('retry preserves an administrator edit on the successor', () {
      expect(
        matrixRoomMigrationShouldRestorePowerLevels(
          isRecovery: true,
          successorPowerLevels: {
            'users': {'@admin:example.org': 75},
          },
          failedInitialPowerLevels: {
            'users': {'@admin:example.org': 50},
          },
        ),
        isFalse,
      );
    });

    test('retry restores permissions when initial state never arrived', () {
      expect(
        matrixRoomMigrationShouldRestorePowerLevels(
          isRecovery: true,
          successorPowerLevels: null,
        ),
        isTrue,
      );
    });

    test('same-session retry uses unchanged failed initial state', () {
      expect(
        matrixRoomMigrationShouldRestorePowerLevels(
          isRecovery: true,
          successorPowerLevels: {
            'users': {'@admin:example.org': 50},
          },
          failedInitialPowerLevels: {
            'users': {'@admin:example.org': 50},
          },
        ),
        isTrue,
      );
    });
  });

  group('MatrixRoomMigration.recover permissions', () {
    test('keeps an administrator edit already in the successor', () async {
      final fixture = _RecoveryFixture({
        'users': {'@admin:example.org': 75},
      });

      final result = await MatrixRoomMigration(
        fixture.client,
      ).recover(source: fixture.source);

      expect(fixture.sdkClient.powerWrites, isEmpty);
      expect(result.successorPermissionsPreserved, isTrue);
      expect(result.permissionsRestored, isTrue);
    });

    test('restores source permissions if successor has no state', () async {
      final fixture = _RecoveryFixture(null);

      final result = await MatrixRoomMigration(
        fixture.client,
      ).recover(source: fixture.source);

      expect(fixture.sdkClient.powerWrites, hasLength(1));
      expect(result.successorPermissionsPreserved, isFalse);
      expect(result.permissionsRestored, isTrue);
    });
  });

  group('matrixRoomMigrationFailureLabel', () {
    test('preserves Matrix errcodes without exposing response bodies', () {
      expect(
        matrixRoomMigrationFailureLabel(
          matrix.MatrixException.fromJson({'errcode': 'M_FORBIDDEN'}),
        ),
        'M_FORBIDDEN',
      );
    });

    test('categorizes timeouts', () {
      expect(
        matrixRoomMigrationFailureLabel(TimeoutException('stalled')),
        'timeout',
      );
    });
  });
}

class _RecoveryFixture {
  _RecoveryFixture(Map<String, Object?>? successorPowerLevels) {
    sdkClient = _MigrationSdkClient();
    final sourceSdk = _MigrationSdkRoom(
      sdkClient,
      '!source:example.org',
      powerLevels: const {
        'users': {'@admin:example.org': 100},
      },
      successorId: '!successor:example.org',
    );
    sdkClient.testRooms['!successor:example.org'] = _MigrationSdkRoom(
      sdkClient,
      '!successor:example.org',
      powerLevels: successorPowerLevels,
    );
    client = _MigrationClient(sdkClient);
    source = _MigrationSourceRoom(client, sourceSdk);
  }

  late final _MigrationSdkClient sdkClient;
  late final _MigrationClient client;
  late final _MigrationSourceRoom source;
}

class _MigrationClient implements MatrixClient {
  _MigrationClient(this.sdk);
  final _MigrationSdkClient sdk;

  @override
  matrix.Client getMatrixClient() => sdk;

  @override
  List<Space> get spaces => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MigrationSourceRoom implements MatrixRoom {
  _MigrationSourceRoom(this.client, this.matrixRoom);

  @override
  final _MigrationClient client;

  @override
  final _MigrationSdkRoom matrixRoom;

  @override
  String get identifier => matrixRoom.id;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MigrationSdkClient implements matrix.Client {
  final testRooms = <String, _MigrationSdkRoom>{};
  final powerWrites = <Map<String, Object?>>[];

  @override
  String get userID => '@admin:example.org';

  @override
  matrix.Room? getRoomById(String id) => testRooms[id];

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    powerWrites.add(body);
    return r'$restored';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _MigrationSdkRoom implements matrix.Room {
  _MigrationSdkRoom(
    this.client,
    this.id, {
    required Map<String, Object?>? powerLevels,
    this.successorId,
  }) : _powerLevelContent = powerLevels;

  @override
  final _MigrationSdkClient client;

  @override
  final String id;

  final Map<String, Object?>? _powerLevelContent;
  final String? successorId;

  @override
  matrix.TombstoneContent? get extinctInformations => successorId == null
      ? null
      : matrix.TombstoneContent.fromJson({
          'body': 'Upgraded',
          'replacement_room': successorId,
        });

  @override
  matrix.StrippedStateEvent? getState(String type, [String stateKey = '']) {
    if (type != matrix.EventTypes.RoomPowerLevels ||
        _powerLevelContent == null) {
      return null;
    }
    return matrix.StrippedStateEvent(
      type: type,
      content: _powerLevelContent,
      senderId: '@admin:example.org',
      stateKey: stateKey,
    );
  }

  @override
  Future<List<matrix.User>> requestParticipants([
    List<matrix.Membership> membershipFilter = const [
      matrix.Membership.join,
      matrix.Membership.invite,
      matrix.Membership.knock,
    ],
    bool suppressWarning = false,
    bool? cache,
  ]) async => const [];

  @override
  int getPowerLevelByUserId(String userId) => 100;

  @override
  Set<String> get creatorUserIds => {'@admin:example.org'};

  @override
  String get roomVersion => '12';

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
