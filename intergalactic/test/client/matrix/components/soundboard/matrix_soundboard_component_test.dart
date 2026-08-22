import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_authority_contract.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_signing.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_verifier.dart';
import 'package:intergalactic/client/matrix/components/soundboard/matrix_soundboard_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/src/utils/cached_stream_controller.dart';

const _alice = '@alice:example.org';
const _bob = '@bob:example.org';
const _spaceId = '!space:example.org';

void main() {
  late _FakeSdkRoom sdkRoom;
  late _FakeSdkClient sdkClient;
  late MatrixSoundboardComponent component;

  MatrixSoundboardComponent buildComponent({
    SoundboardAuthorityClient? authority,
    String userId = _alice,
  }) {
    sdkRoom = _FakeSdkRoom();
    sdkClient = _FakeSdkClient(sdkRoom, userId: userId);
    final built = MatrixSoundboardComponent(
      _FakeMatrixClient(sdkClient),
      _FakeMatrixSpace(sdkRoom),
      authorityClient: authority,
    );
    // Every component holds onRoomState/onSync subscriptions and an open
    // StreamController. Registered here rather than at each call site because
    // several tests build extra components inline; without this they stay
    // listening and can react to writes made by later tests in this file.
    // dispose() is idempotent, so the tearDown on the field-held `component`
    // is harmless overlap.
    addTearDown(built.dispose);
    return built;
  }

  /// Opts the space into enhanced protection: the service config event exists
  /// and the two soundboard event types are locked above members.
  void makeProtected({int memberUploadLevel = 0}) {
    sdkRoom.applyState(
      SoundboardEventTypes.authorityConfig,
      '',
      {'schema_version': 1, 'member_upload_level': memberUploadLevel},
      senderId: '@soundboard-authority:example.org',
    );
    sdkRoom.allowedStateEvents.remove(SoundboardEventTypes.packState);
    sdkRoom.allowedStateEvents.remove(SoundboardEventTypes.soundState);
  }

  void seedSound(
    String id, {
    required String uploadedBy,
    String? packId,
    DateTime? createdAt,
  }) {
    sdkRoom.applyState(
      SoundboardEventTypes.soundState,
      id,
      SoundboardSound(
        id: id,
        name: id,
        emoji: '🔊',
        mxcUri: Uri.parse('mxc://example.org/$id'),
        mimeType: 'audio/ogg',
        uploadedBy: uploadedBy,
        createdAt: createdAt ?? DateTime.utc(2026, 7, 1),
        sizeBytes: 1000,
        packId: packId,
      ).toStateContent(),
      senderId: uploadedBy,
    );
  }

  void seedPack(SoundboardPack pack) {
    sdkRoom.applyState(
      SoundboardEventTypes.packState,
      pack.id,
      pack.toStateContent(),
      senderId: pack.createdBy,
    );
  }

  SoundboardPack explicitPack(
    String id, {
    String name = 'Pack',
    String createdBy = _bob,
    bool enabled = true,
    bool deleted = false,
  }) {
    final createdAt = DateTime.utc(2026, 7, 1);
    return SoundboardPack(
      id: id,
      name: name,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: createdAt,
      enabled: enabled,
      deleted: deleted,
    );
  }

  /// Seeds service-written pack state carrying a revision (the service owns it;
  /// client-managed writes never serialize it).
  void seedServicePack(
    String id, {
    String createdBy = _alice,
    required int revision,
  }) {
    final content = explicitPack(id, createdBy: createdBy).toStateContent()
      ..['revision'] = revision;
    sdkRoom.applyState(
      SoundboardEventTypes.packState,
      id,
      content,
      senderId: createdBy,
    );
  }

  void seedServiceSound(
    String id, {
    String uploadedBy = _alice,
    String? packId,
    required int revision,
  }) {
    seedSound(id, uploadedBy: uploadedBy, packId: packId);
    sdkRoom.states[SoundboardEventTypes.soundState]![id]!.content['revision'] =
        revision;
  }

  setUp(() {
    component = buildComponent();
  });

  tearDown(() async {
    await component.dispose();
  });

  group('packs and legacy derivation', () {
    test('derives one legacy pack per uploader of loose sounds', () {
      seedSound('a1', uploadedBy: _alice);
      seedSound('a2', uploadedBy: _alice);
      seedSound('b1', uploadedBy: _bob);

      final packs = component.packs;
      expect(packs, hasLength(2));
      expect(packs.every((pack) => pack.isLegacy), isTrue);
      expect(packs.map((pack) => pack.id).toSet(), {
        SoundboardPack.legacyIdForUploader(_alice),
        SoundboardPack.legacyIdForUploader(_bob),
      });
    });

    test('a materialized legacy pack is not duplicated by derivation', () {
      seedSound('a1', uploadedBy: _alice);
      seedPack(
        explicitPack(
          SoundboardPack.legacyIdForUploader(_alice),
          name: 'Alice classics',
          createdBy: _alice,
        ),
      );

      final packs = component.packs;
      expect(packs, hasLength(1));
      expect(packs.single.name, 'Alice classics');
    });

    test('sounds referencing a missing pack are quarantined', () {
      seedSound('loose', uploadedBy: _alice);
      seedSound('orphan', uploadedBy: _alice, packId: 'missing-pack');

      expect(component.sounds.map((sound) => sound.id), ['loose']);
      // The quarantined sound still counts for management surfaces.
      expect(component.soundsInPack('missing-pack'), hasLength(1));
    });

    test(
      'sounds in a source-disabled pack do not play but stay manageable',
      () {
        seedPack(explicitPack('pack-1', enabled: false));
        seedSound('s1', uploadedBy: _bob, packId: 'pack-1');

        expect(component.sounds, isEmpty);
        expect(component.soundsInPack('pack-1'), hasLength(1));
        expect(component.packs.single.isAvailable, isFalse);
      },
    );
  });

  group('personal activation (R7/R8)', () {
    test('own packs default active; other packs default inactive', () {
      seedSound('mine', uploadedBy: _alice);
      seedSound('theirs', uploadedBy: _bob);
      seedPack(explicitPack('bob-pack', createdBy: _bob));

      final active = component.activePackIds;
      expect(active, contains(SoundboardPack.legacyIdForUploader(_alice)));
      expect(active, isNot(contains(SoundboardPack.legacyIdForUploader(_bob))));
      expect(active, isNot(contains('bob-pack')));

      expect(component.activeSounds.map((sound) => sound.id), ['mine']);
    });

    test(
      'activation override stores only the deviation from the default',
      () async {
        seedSound('theirs', uploadedBy: _bob);
        seedPack(explicitPack('bob-pack', createdBy: _bob));
        seedSound('packed', uploadedBy: _bob, packId: 'bob-pack');

        final bobPack = component.packById('bob-pack')!;
        await component.setPackActive(bobPack, true);

        expect(sdkClient.accountDataWrites, hasLength(1));
        expect(sdkClient.accountDataWrites.single['active_overrides'], {
          'bob-pack': true,
        });
        expect(component.activePackIds, contains('bob-pack'));
        expect(
          component.activeSounds.map((sound) => sound.id),
          contains('packed'),
        );

        // Returning to the derived default removes the override entirely.
        await component.setPackActive(bobPack, false);
        expect(sdkClient.accountDataWrites.last['active_overrides'], isEmpty);
        expect(component.activePackIds, isNot(contains('bob-pack')));
      },
    );

    test('seeded account-data override is honored before any local write', () {
      seedSound('theirs', uploadedBy: _bob);
      sdkRoom.roomAccountData[SoundboardEventTypes
          .localPackSettings] = matrix.BasicEvent(
        type: SoundboardEventTypes.localPackSettings,
        content: {
          'active_overrides': {SoundboardPack.legacyIdForUploader(_bob): true},
        },
      );

      expect(
        component.activePackIds,
        contains(SoundboardPack.legacyIdForUploader(_bob)),
      );
    });
  });

  group('pack management authorization (R1/R2)', () {
    test('creating a pack requires the pack state permission', () async {
      sdkRoom.allowedStateEvents.remove(SoundboardEventTypes.packState);

      expect(component.canCreatePack, isFalse);
      await expectLater(component.createPack('New pack'), throwsException);

      sdkRoom.allowedStateEvents.add(SoundboardEventTypes.packState);
      final pack = await component.createPack('  New pack  ');
      expect(pack.name, 'New pack');
      expect(pack.createdBy, _alice);
      expect(sdkClient.stateWrites.single.type, SoundboardEventTypes.packState);
      expect(component.packById(pack.id), isNotNull);
    });

    test('a creator manages their own pack; an admin manages every pack', () {
      final bobPack = explicitPack('bob-pack', createdBy: _bob);

      // Alice is not an admin here.
      sdkRoom.allowedStateEvents.remove(matrix.EventTypes.RoomPowerLevels);
      expect(component.canManagePack(bobPack, _alice), isFalse);
      expect(component.canManagePack(bobPack, _bob), isTrue);

      // With power-level authority Alice manages every pack.
      sdkRoom.allowedStateEvents.add(matrix.EventTypes.RoomPowerLevels);
      expect(component.canManagePack(bobPack, _alice), isTrue);
    });

    test(
      'renaming a derived legacy pack materializes explicit state',
      () async {
        seedSound('mine', uploadedBy: _alice);
        final legacyId = SoundboardPack.legacyIdForUploader(_alice);
        final legacy = component.packById(legacyId)!;
        expect(legacy.isLegacy, isTrue);

        await component.renamePack(legacy, 'My classics');

        final write = sdkClient.stateWrites.single;
        expect(write.type, SoundboardEventTypes.packState);
        expect(write.stateKey, legacyId);
        expect(write.content['name'], 'My classics');
        expect(write.content['legacy'], isTrue);
        expect(component.packById(legacyId)!.name, 'My classics');
      },
    );

    test('setPackEmoji writes the icon and clears it', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));
      final pack = component.packById('alice-pack')!;

      await component.setPackEmoji(pack, ':star:');
      var write = sdkClient.stateWrites.single;
      expect(write.type, SoundboardEventTypes.packState);
      expect(write.stateKey, 'alice-pack');
      expect(write.content['emoji'], ':star:');
      expect(component.packById('alice-pack')!.emoji, ':star:');

      sdkClient.stateWrites.clear();
      await component.setPackEmoji(component.packById('alice-pack')!, null);
      write = sdkClient.stateWrites.single;
      expect(write.content.containsKey('emoji'), isFalse);
      expect(component.packById('alice-pack')!.emoji, isNull);
    });

    test('setting an icon on a legacy pack materializes it', () async {
      seedSound('mine', uploadedBy: _alice);
      final legacyId = SoundboardPack.legacyIdForUploader(_alice);

      await component.setPackEmoji(component.packById(legacyId)!, ':fire:');

      final write = sdkClient.stateWrites.single;
      expect(write.stateKey, legacyId);
      expect(write.content['emoji'], ':fire:');
      expect(write.content['legacy'], isTrue);
    });

    test('a member cannot set an icon on an unmanaged pack', () async {
      sdkRoom.allowedStateEvents.remove(matrix.EventTypes.RoomPowerLevels);
      seedPack(explicitPack('bob-pack', createdBy: _bob));

      await expectLater(
        component.setPackEmoji(component.packById('bob-pack')!, ':star:'),
        throwsException,
      );
      expect(sdkClient.stateWrites, isEmpty);
    });
  });

  group('move and upload destinations (R3)', () {
    test('moving a sound rewrites its single pack reference', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));
      seedSound('mine', uploadedBy: _alice);

      final sound = component.sounds.singleWhere(
        (candidate) => candidate.id == 'mine',
      );
      await component.moveSoundToPack(sound, 'alice-pack');

      final write = sdkClient.stateWrites.single;
      expect(write.type, SoundboardEventTypes.soundState);
      expect(write.content['pack_id'], 'alice-pack');
    });

    test('moving back to the own legacy pack clears the reference', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));
      seedSound('mine', uploadedBy: _alice, packId: 'alice-pack');

      final sound = component.sounds.single;
      await component.moveSoundToPack(
        sound,
        SoundboardPack.legacyIdForUploader(_alice),
      );

      final write = sdkClient.stateWrites.single;
      expect(write.content.containsKey('pack_id'), isFalse);
    });

    test('a member cannot move a sound into an unmanaged pack', () async {
      sdkRoom.allowedStateEvents.remove(matrix.EventTypes.RoomPowerLevels);
      seedPack(explicitPack('bob-pack', createdBy: _bob));
      seedSound('mine', uploadedBy: _alice);

      final sound = component.sounds.single;
      await expectLater(
        component.moveSoundToPack(sound, 'bob-pack'),
        throwsException,
      );
      expect(sdkClient.stateWrites, isEmpty);
    });

    test('uploading into a chosen pack records the reference once', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));

      final sound = await component.uploadSound(
        name: 'Boom',
        emoji: '💥',
        bytes: Uint8List.fromList(List.filled(10, 1)),
        mimeType: 'audio/ogg',
        packId: 'alice-pack',
      );

      expect(sound.packId, 'alice-pack');
      final write = sdkClient.stateWrites.singleWhere(
        (w) => w.type == SoundboardEventTypes.soundState,
      );
      expect(write.content['pack_id'], 'alice-pack');
    });

    test('a transient upload failure retries and writes state once', () async {
      // Two flaky-connection blips then success: the third attempt uploads and
      // the sound state is written exactly once (no duplicate media/state).
      sdkClient.uploadTransientFailures = 2;

      final sound = await component.uploadSound(
        name: 'Boom',
        emoji: '💥',
        bytes: Uint8List.fromList(List.filled(10, 1)),
        mimeType: 'audio/ogg',
      );

      expect(sdkClient.uploadAttempts, 3);
      final soundWrites = sdkClient.stateWrites.where(
        (w) => w.type == SoundboardEventTypes.soundState,
      );
      expect(soundWrites.length, 1);
      expect(soundWrites.single.stateKey, sound.id);
    });

    test('gives up after the bounded attempts and rethrows', () async {
      // Persistent transient failure must not retry forever, and must surface
      // the error rather than silently succeeding or writing state.
      sdkClient.uploadTransientFailures = 99;

      await expectLater(
        component.uploadSound(
          name: 'Boom',
          emoji: '💥',
          bytes: Uint8List.fromList(List.filled(10, 1)),
          mimeType: 'audio/ogg',
        ),
        throwsA(isA<SocketException>()),
      );

      expect(sdkClient.uploadAttempts, 3);
      expect(
        sdkClient.stateWrites.where(
          (w) => w.type == SoundboardEventTypes.soundState,
        ),
        isEmpty,
      );
    });
  });

  group('destructive deletion (R18/KTD7)', () {
    test('tombstones the pack first, then every contained sound', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));
      seedSound('s1', uploadedBy: _alice, packId: 'alice-pack');
      seedSound('s2', uploadedBy: _alice, packId: 'alice-pack');
      seedSound('other', uploadedBy: _alice);

      final pack = component.packById('alice-pack')!;
      await component.deletePack(pack);

      expect(sdkClient.stateWrites.first.type, SoundboardEventTypes.packState);
      expect(sdkClient.stateWrites.first.content['deleted'], isTrue);
      final soundWrites = sdkClient.stateWrites
          .where((w) => w.type == SoundboardEventTypes.soundState)
          .toList();
      expect(soundWrites, hasLength(2));
      expect(soundWrites.every((w) => w.content['deleted'] == true), isTrue);
      // The unrelated loose sound survives.
      expect(component.sounds.map((sound) => sound.id), ['other']);
    });

    test('partial sound cleanup failure keeps the pack unavailable and '
        'retries only the remainder', () async {
      seedPack(explicitPack('alice-pack', createdBy: _alice));
      seedSound('s1', uploadedBy: _alice, packId: 'alice-pack');
      seedSound('s2', uploadedBy: _alice, packId: 'alice-pack');

      sdkClient.failSoundStateKeysOnce.add('s2');
      final pack = component.packById('alice-pack')!;
      await expectLater(component.deletePack(pack), throwsException);

      // Pack tombstone landed before the failure.
      expect(component.packById('alice-pack'), isNull);
      expect(component.sounds, isEmpty);

      // Retry completes only the remaining tombstone; the pack write is not
      // repeated.
      final writesBeforeRetry = sdkClient.stateWrites.length;
      await component.deletePack(pack);
      final retryWrites = sdkClient.stateWrites.skip(writesBeforeRetry);
      expect(
        retryWrites.every((w) => w.type == SoundboardEventTypes.soundState),
        isTrue,
      );
      expect(component.soundsInPack('alice-pack'), isEmpty);
    });
  });

  group('permission alignment (KTD8)', () {
    test('enableMemberUploads opens sound and pack state together', () async {
      await component.enableMemberUploads();

      final write = sdkClient.stateWrites.single;
      expect(write.type, matrix.EventTypes.RoomPowerLevels);
      final events = write.content['events'] as Map;
      expect(events[SoundboardEventTypes.soundState], 0);
      expect(events[SoundboardEventTypes.packState], 0);
    });

    test('alignPackCreationPermission matches the sound threshold', () async {
      sdkRoom.applyState(matrix.EventTypes.RoomPowerLevels, '', {
        'state_default': 50,
        'users_default': 0,
        'events': {SoundboardEventTypes.soundState: 25},
      }, senderId: _alice);
      expect(component.packCreationPowerLevel, 50);

      await component.alignPackCreationPermission();

      final write = sdkClient.stateWrites.last;
      final events = write.content['events'] as Map;
      expect(events[SoundboardEventTypes.packState], 25);
      expect(component.packCreationPowerLevel, 25);
    });
  });

  group('account-data cache invalidation (PR #77)', () {
    test('a synced cross-device override change replaces the locally seeded '
        'pack settings cache', () async {
      seedSound('theirs', uploadedBy: _bob);
      seedPack(explicitPack('bob-pack', createdBy: _bob));

      // Local write seeds the write-through cache.
      final bobPack = component.packById('bob-pack')!;
      await component.setPackActive(bobPack, true);
      expect(component.activePackIds, contains('bob-pack'));

      // Another device removes the override; the change arrives via sync.
      await sdkClient.syncRoomAccountData(
        _spaceId,
        SoundboardEventTypes.localPackSettings,
        {'active_overrides': <String, bool>{}},
      );

      expect(component.activePackIds, isNot(contains('bob-pack')));

      // And a synced override in the other direction is honored too.
      await sdkClient.syncRoomAccountData(
        _spaceId,
        SoundboardEventTypes.localPackSettings,
        {
          'active_overrides': {'bob-pack': true},
        },
      );
      expect(component.activePackIds, contains('bob-pack'));
    });

    test('a sync for another room does not clear the cache', () async {
      seedSound('theirs', uploadedBy: _bob);
      seedPack(explicitPack('bob-pack', createdBy: _bob));

      final bobPack = component.packById('bob-pack')!;
      await component.setPackActive(bobPack, true);

      // Same account-data type, different room: cache must survive. Emit the
      // sync without touching this room's account data.
      sdkClient.onSync.add(
        matrix.SyncUpdate(
          nextBatch: 'other-room-sync',
          rooms: matrix.RoomsUpdate(
            join: {
              '!other:example.org': matrix.JoinedRoomUpdate(
                accountData: [
                  matrix.BasicEvent(
                    type: SoundboardEventTypes.localPackSettings,
                    content: {'active_overrides': <String, bool>{}},
                  ),
                ],
              ),
            },
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(component.activePackIds, contains('bob-pack'));
    });

    test(
      'a synced join-sound change drops the local join-sound cache',
      () async {
        seedSound('mine', uploadedBy: _alice);

        await component.setJoinSoundForUser(_alice, 'mine');
        expect(component.getJoinSoundId(_alice), 'mine');

        // Another device clears the join sound.
        await sdkClient.syncRoomAccountData(
          _spaceId,
          SoundboardEventTypes.userState,
          SoundboardUserSettings(joinSoundId: null).toStateContent(),
        );

        expect(component.getJoinSoundId(_alice), isNull);
      },
    );

    test('a first-time remote pack override with no prior local write notifies '
        'listeners so the UI rebuilds', () async {
      seedSound('theirs', uploadedBy: _bob);
      seedPack(explicitPack('bob-pack', createdBy: _bob));

      // No setPackActive and no prior read: the write-through cache is
      // unseeded, so this exercises the first-time-remote-override path where
      // activePackIds already reads through live but the UI must still be
      // told to rebuild.
      var notifications = 0;
      final subscription = component.onChanged.listen((_) => notifications++);

      await sdkClient.syncRoomAccountData(
        _spaceId,
        SoundboardEventTypes.localPackSettings,
        {
          'active_overrides': {'bob-pack': true},
        },
      );

      expect(notifications, greaterThan(0));
      expect(component.activePackIds, contains('bob-pack'));

      await subscription.cancel();
    });

    test('a first-time remote join-sound change with no prior local write '
        'notifies listeners', () async {
      seedSound('mine', uploadedBy: _alice);

      var notifications = 0;
      final subscription = component.onChanged.listen((_) => notifications++);

      // Remote join-sound assignment with no preceding setJoinSoundForUser.
      await sdkClient.syncRoomAccountData(
        _spaceId,
        SoundboardEventTypes.userState,
        SoundboardUserSettings(joinSoundId: 'mine').toStateContent(),
      );

      expect(notifications, greaterThan(0));
      expect(component.getJoinSoundId(_alice), 'mine');

      await subscription.cancel();
    });
  });

  group('dual-path routing (per-space opt-in protection)', () {
    late _FakeAuthorityClient authority;

    setUp(() {
      authority = _FakeAuthorityClient();
      component = buildComponent(authority: authority);
    });

    test('isProtected reflects the service config event', () {
      expect(component.isProtected, isFalse);
      makeProtected();
      expect(component.isProtected, isTrue);
    });

    test(
      'unprotected space writes directly, not through the service',
      () async {
        await component.createPack('Direct pack');
        expect(authority.calls, isEmpty);
        expect(
          sdkClient.stateWrites.where(
            (w) => w.type == SoundboardEventTypes.packState,
          ),
          isNotEmpty,
        );
      },
    );

    test(
      'protected: createPack routes to the service, no direct write',
      () async {
        makeProtected();
        await component.createPack('Routed pack');
        expect(
          authority.calls.where((c) => c.startsWith('createPack:')),
          hasLength(1),
        );
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test(
      'protected: a retryable mutation replays the exact same request once',
      () async {
        makeProtected();
        authority.failOnceWith = const SoundboardAuthorityError(
          code: SoundboardAuthorityErrorCode.upstreamUnavailable,
          message: 'Try again shortly.',
          retryable: true,
        );

        await component.createPack('Routed pack');

        expect(authority.createPackRequests, hasLength(2));
        expect(
          authority.createPackRequests[1]['request_id'],
          authority.createPackRequests.first['request_id'],
        );
        expect(
          authority.createPackRequests[1]['source_space_id'],
          authority.createPackRequests.first['source_space_id'],
        );
        expect(
          authority.createPackRequests[1]['pack'],
          equals(authority.createPackRequests.first['pack']),
        );
        expect(
          authority.createPackRequests[1]['auth'],
          equals(authority.createPackRequests.first['auth']),
          reason:
              'an uncertain first response must replay the same id and '
              'immutable payload, not create a second user action',
        );
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test(
      'protected: non-retryable and distinct mutations do not replay',
      () async {
        makeProtected();
        authority.failWith = const SoundboardAuthorityError(
          code: SoundboardAuthorityErrorCode.forbidden,
          message: 'Not allowed.',
          retryable: false,
        );

        await expectLater(component.createPack('Nope'), throwsException);
        expect(authority.createPackRequests, hasLength(1));

        authority.failWith = null;
        await component.createPack('First');
        await component.createPack('Second');
        expect(authority.createPackRequests, hasLength(3));
        expect(
          authority.createPackRequests[2]['request_id'],
          isNot(authority.createPackRequests[1]['request_id']),
          reason: 'separate user actions must retain separate request IDs',
        );
      },
    );

    test(
      'protected: writable state events still route through the service',
      () async {
        makeProtected();
        sdkRoom.allowedStateEvents.add(SoundboardEventTypes.packState);
        await component.createPack('Routed pack');
        expect(
          authority.calls.where((c) => c.startsWith('createPack:')),
          hasLength(1),
        );
        expect(
          sdkClient.stateWrites.where(
            (w) => w.type == SoundboardEventTypes.packState,
          ),
          isEmpty,
        );
      },
    );

    test(
      'protected: renamePack routes to updatePack with expected_revision',
      () async {
        seedServicePack('p1', createdBy: _alice, revision: 3);
        makeProtected();
        await component.renamePack(component.packById('p1')!, 'Renamed');
        expect(
          authority.calls,
          contains('updatePack:p1:rev3:name=Renamed:emoji=null:disabled=null'),
        );
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test(
      'protected: setPackEmoji routes to updatePack with expected_revision',
      () async {
        seedServicePack('p1', createdBy: _alice, revision: 3);
        makeProtected();
        await component.setPackEmoji(component.packById('p1')!, ':star:');
        expect(
          authority.calls,
          contains('updatePack:p1:rev3:name=null:emoji=:star::disabled=null'),
        );
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test(
      'protected: clearing pack emoji resets through the service default',
      () async {
        seedServicePack('p1', createdBy: _alice, revision: 3);
        makeProtected();
        await component.setPackEmoji(component.packById('p1')!, null);
        expect(
          authority.calls,
          contains('updatePack:p1:rev3:name=null:emoji=🔊:disabled=null'),
        );
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test(
      'protected: uploadSound routes to createSound with the media payload',
      () async {
        seedServicePack('p1', createdBy: _alice, revision: 1);
        makeProtected();
        final sound = await component.uploadSound(
          name: 'Boom',
          emoji: '💥',
          bytes: Uint8List.fromList(List.filled(10, 1)),
          mimeType: 'audio/ogg',
          packId: 'p1',
        );
        expect(authority.calls, contains('createSound:${sound.id}'));
        final payload = authority.soundCreates.single;
        expect(payload['pack_id'], 'p1');
        expect(payload['name'], 'Boom');
        expect(payload['url'], startsWith('mxc://'));
        expect(payload['mimetype'], 'audio/ogg');
        // The state write is the service's job; the client made none.
        expect(
          sdkClient.stateWrites.where(
            (w) => w.type == SoundboardEventTypes.soundState,
          ),
          isEmpty,
        );
      },
    );

    test(
      'protected: deletePack routes the pack and each contained sound',
      () async {
        seedServicePack('p1', createdBy: _alice, revision: 2);
        seedServiceSound('s1', uploadedBy: _alice, packId: 'p1', revision: 1);
        seedServiceSound('s2', uploadedBy: _alice, packId: 'p1', revision: 1);
        makeProtected();
        await component.deletePack(component.packById('p1')!);
        expect(authority.deletedPacks, ['p1']);
        expect(authority.deletedSounds..sort(), ['s1', 's2']);
        expect(sdkClient.stateWrites, isEmpty);
      },
    );

    test('protected: a service failure surfaces as an exception', () async {
      makeProtected();
      authority.failWith = const SoundboardAuthorityError(
        code: SoundboardAuthorityErrorCode.forbidden,
        message: 'Not allowed.',
        retryable: false,
      );
      await expectLater(component.createPack('Nope'), throwsException);
      expect(sdkClient.stateWrites, isEmpty);
    });

    test(
      'protected: personal activation still writes account data, not routed',
      () async {
        seedPack(explicitPack('p1', createdBy: _bob).copyWith(revision: 1));
        makeProtected();
        await component.setPackActive(component.packById('p1')!, true);
        // Activation is room account data (never locked), so it is a direct write.
        expect(authority.calls, isEmpty);
        expect(sdkClient.accountDataWrites, isNotEmpty);
      },
    );

    test('protected: a service mutation converges local state from the server, '
        'parsing the service pack schema', () async {
      makeProtected();
      // The service wrote a pack server-side in its own schema
      // (creator_user_id/disabled, service-owned revision). It is not in the
      // local DB yet, so the post-mutation refresh must fetch it from the
      // server and it must parse - otherwise the pack "does not appear" and a
      // stale revision would 409 the next update.
      sdkClient.serverStateOverride = [
        matrix.MatrixEvent(
          type: SoundboardEventTypes.packState,
          stateKey: 'svc-pack',
          senderId: '@soundboard-authority:example.org',
          eventId: 'e-svc',
          originServerTs: DateTime.utc(2026, 7, 19),
          content: {
            'schema_version': 1,
            'pack_id': 'svc-pack',
            'name': 'Service Pack',
            'emoji': '🔊',
            'creator_user_id': _alice,
            'created_at': '2026-07-19T00:00:00Z',
            'updated_at': '2026-07-19T00:00:00Z',
            'updated_by': _alice,
            'revision': 4,
            'disabled': false,
            'deleted': false,
          },
        ),
      ];
      await component.createPack('Trigger refresh');
      final pack = component.packById('svc-pack');
      expect(pack, isNotNull);
      expect(pack!.name, 'Service Pack');
      expect(pack.createdBy, _alice); // parsed from creator_user_id
      expect(pack.revision, 4); // service-owned revision captured
    });
  });

  group('protection activation (admin toggle)', () {
    late _FakeAuthorityClient authority;

    setUp(() {
      authority = _FakeAuthorityClient();
      component = buildComponent(authority: authority);
    });

    test('the live Matrix component supports protection', () {
      expect(component.supportsProtection, isTrue);
    });

    test('enableProtection routes to spaces/enable', () async {
      await component.enableProtection();
      expect(authority.calls, contains('enableProtection:level=null'));
      // No direct state write — the service owns the config + power-level lock.
      expect(sdkClient.stateWrites, isEmpty);
    });

    test('enableProtection forwards the member upload level', () async {
      await component.enableProtection(memberUploadLevel: 50);
      expect(authority.calls, contains('enableProtection:level=50'));
    });

    test('disableProtection routes to spaces/disable', () async {
      makeProtected();
      await component.disableProtection();
      expect(authority.calls, contains('disableProtection'));
      expect(sdkClient.stateWrites, isEmpty);
    });

    test('a failed enable surfaces the actionable service message', () async {
      authority.failWith = const SoundboardAuthorityError(
        code: SoundboardAuthorityErrorCode.forbidden,
        message: 'Invite the service user to this space first.',
        retryable: false,
      );
      await expectLater(
        component.enableProtection(),
        throwsA(
          predicate(
            (error) => error.toString().contains('Invite the service user'),
          ),
        ),
      );
    });

    test('isProtected honors the enabled flag over mere presence', () {
      // A lingering disabled config (enabled:false) is NOT protected even though
      // the state event still exists (Matrix state cannot be deleted).
      sdkRoom.applyState(
        SoundboardEventTypes.authorityConfig,
        '',
        {'schema_version': 1, 'member_upload_level': 0, 'enabled': false},
        senderId: '@soundboard-authority:example.org',
      );
      expect(component.isProtected, isFalse);

      // enabled:true is protected.
      sdkRoom.applyState(
        SoundboardEventTypes.authorityConfig,
        '',
        {'schema_version': 1, 'member_upload_level': 0, 'enabled': true},
        senderId: '@soundboard-authority:example.org',
      );
      expect(component.isProtected, isTrue);
    });

    test('a pre-flag config (no enabled field) reads as protected', () {
      // makeProtected writes a config without the enabled field.
      makeProtected();
      expect(component.isProtected, isTrue);
    });

    test('canManageProtection needs power over power levels and the config', () {
      // Admin: can change both power levels and the authority config type.
      sdkRoom.allowedStateEvents.add(SoundboardEventTypes.authorityConfig);
      expect(component.canManageProtection, isTrue);

      // Losing power over the config type (or power levels) hides the control.
      sdkRoom.allowedStateEvents.remove(SoundboardEventTypes.authorityConfig);
      expect(component.canManageProtection, isFalse);
      sdkRoom.allowedStateEvents
        ..add(SoundboardEventTypes.authorityConfig)
        ..remove(matrix.EventTypes.RoomPowerLevels);
      expect(component.canManageProtection, isFalse);
    });
  });

  // U6: the destination space's policy on packs owned by other spaces.
  group('destination external-pack policy', () {
    test('a space with no policy event allows external packs', () {
      expect(component.destinationPolicy.allowExternalPacks, isTrue);
    });

    test('an admin can block and re-allow', () async {
      sdkRoom.allowedStateEvents.add(
        SoundboardEventTypes.destinationPolicyState,
      );
      expect(component.canManageDestinationPolicy, isTrue);

      await component.setAllowExternalPacks(false);
      expect(component.destinationPolicy.allowExternalPacks, isFalse);

      await component.setAllowExternalPacks(true);
      expect(component.destinationPolicy.allowExternalPacks, isTrue);
      // Re-allowing is written explicitly rather than deleted - Matrix state
      // cannot be removed, so the event must carry the new value.
      expect(
        sdkClient.stateWrites
            .where((w) => w.type == SoundboardEventTypes.destinationPolicyState)
            .map((w) => w.content['allow_external_packs']),
        [false, true],
      );
    });

    test('blocking external packs leaves local packs untouched', () async {
      sdkRoom.allowedStateEvents.add(
        SoundboardEventTypes.destinationPolicyState,
      );
      seedPack(explicitPack('p1', createdBy: _alice));
      final before = component.packs.map((p) => p.id).toList();

      await component.setAllowExternalPacks(false);

      expect(component.packs.map((p) => p.id), before);
      expect(component.canCreatePack, isTrue);
    });

    test('an ordinary member cannot change the policy', () async {
      sdkRoom.allowedStateEvents.remove(
        SoundboardEventTypes.destinationPolicyState,
      );

      expect(component.canManageDestinationPolicy, isFalse);
      await expectLater(
        component.setAllowExternalPacks(false),
        throwsException,
      );
      expect(
        sdkClient.stateWrites.where(
          (w) => w.type == SoundboardEventTypes.destinationPolicyState,
        ),
        isEmpty,
      );
    });

    test('a policy change arriving by state event is picked up', () {
      sdkRoom.applyState(SoundboardEventTypes.destinationPolicyState, '', {
        'schema_version': 1,
        'allow_external_packs': false,
      }, senderId: _alice);

      expect(component.destinationPolicy.allowExternalPacks, isFalse);
    });
  });

  // U7: cross-space playback verification performed by the DESTINATION space's
  // component, which owns the account-scoped authority client and this space's
  // policy.
  group('cross-space playback verification', () {
    late _FakeAuthorityClient authority;

    setUp(() async {
      // Replace the default component with one over a recording authority, so
      // the tests can assert WHETHER a key fetch happened, not just its result.
      await component.dispose();
      authority = _FakeAuthorityClient();
      component = buildComponent(authority: authority);
    });

    SoundboardPlaybackAuthorization authorization({
      String destinationRoomId = _spaceId,
      String callSessionId = 'session-1',
      String authorizedUserId = _alice,
      String soundId = 'sound-1',
      String packId = 'pack-1',
    }) => SoundboardPlaybackAuthorization(
      schemaVersion: 1,
      authorizedUserId: authorizedUserId,
      sourceSpaceId: '!other:example.org',
      destinationRoomId: destinationRoomId,
      callSessionId: callSessionId,
      packId: packId,
      soundId: soundId,
      media: SoundboardAuthorityMediaDescriptor(
        mxcUri: Uri.parse('mxc://example.org/media'),
        mimeType: 'audio/ogg',
        sizeBytes: 1000,
        durationMs: 900,
      ),
      nonce: 'nonce-crossspace',
      expiresAt: DateTime.utc(2026, 7, 28, 0, 1),
      expiresAtRaw: '2026-07-28T00:01:00.000Z',
      kid: 'sb-2026-07',
      signature: 'SIGNATURE',
    );

    Future<SoundboardAuthorizationVerdict> verify({
      SoundboardPlaybackAuthorization? auth,
      String? callSessionId = 'session-1',
      String senderId = _alice,
      String soundId = 'sound-1',
      String packId = 'pack-1',
    }) => component.verifyCrossSpacePlayback(
      auth ?? authorization(),
      destinationRoomId: _spaceId,
      callSessionId: callSessionId,
      senderId: senderId,
      soundId: soundId,
      packId: packId,
      now: DateTime.utc(2026, 7, 28),
    );

    test('a play for another room is refused without fetching keys', () async {
      final verdict = await verify(
        auth: authorization(destinationRoomId: '!elsewhere:example.org'),
      );

      expect(verdict.isAllowed, isFalse);
      expect(
        verdict.failure,
        SoundboardAuthorizationFailure.destinationMismatch,
      );
      // Cheap rejections must not cost a network round trip.
      expect(authority.calls, isEmpty);
    });

    test(
      'a differing call session is not refused (call is room-scoped)',
      () async {
        // Session ids are per-participant and the RTC call is the room (call_id
        // ""), so the sender's session id never equals the receiver's. Gating on
        // it refused every real cross-space play; the room binding is the scope.
        final verdict = await verify(
          auth: authorization(callSessionId: 'sender-session'),
        );

        // The session mismatch no longer short-circuits: verification proceeds
        // past the context checks (to signature verification, which this fixture
        // does not set up to pass) rather than refusing on the session.
        expect(
          verdict.failure,
          isNot(SoundboardAuthorizationFailure.sessionMismatch),
        );
      },
    );

    test('an event pointing at a different sound is refused', () async {
      final verdict = await verify(soundId: 'different-sound');

      expect(verdict.failure, SoundboardAuthorizationFailure.soundMismatch);
      expect(authority.calls, isEmpty);
    });

    test('a play sent by someone the authorization was not issued to is '
        'refused without fetching keys', () async {
      // Bob relaying an authorization issued to Alice. The signature would
      // verify fine - it is a genuine authorization - so this refusal has to
      // come from the sender binding, and it should cost nothing.
      final verdict = await verify(senderId: _bob);

      expect(verdict.failure, SoundboardAuthorizationFailure.senderMismatch);
      expect(authority.calls, isEmpty);
    });

    test('a blocked destination refuses even a signed play', () async {
      sdkRoom.applyState(SoundboardEventTypes.destinationPolicyState, '', {
        'schema_version': 1,
        'allow_external_packs': false,
      }, senderId: _alice);

      final verdict = await verify();

      expect(
        verdict.failure,
        SoundboardAuthorizationFailure.destinationMismatch,
      );
      // The administrator's block is decided locally; no key fetch needed.
      expect(authority.calls, isEmpty);
    });

    test('a verifiable-looking play still fails closed with no keys', () async {
      // The fake authority publishes no keys, so nothing can be verified and
      // the play is refused rather than allowed.
      final verdict = await verify();

      expect(verdict.isAllowed, isFalse);
      expect(verdict.failure, SoundboardAuthorizationFailure.unknownKid);
      expect(authority.calls, contains('fetchVerificationKeys'));
    });

    test('keys are fetched once and reused across plays', () async {
      await verify();
      await verify();

      expect(
        authority.calls.where((c) => c == 'fetchVerificationKeys'),
        hasLength(1),
      );
    });
  });

  // Multi-account attribution (integration-queue 2026-07-28). A space joined by
  // two signed-in accounts produces two MatrixSpace objects — one per client —
  // and therefore two soundboard components. Each must act strictly as its own
  // account: the component never reaches for an ambient "primary" or
  // highest-power session, so having an admin signed in elsewhere cannot
  // silently claim a member's pack.
  group('multi-account identity', () {
    test('each component acts as its own client, in both write paths', () async {
      // Member's copy of the space, protected -> mutations route to the service.
      final memberAuthority = _FakeAuthorityClient();
      final memberComponent = buildComponent(
        authority: memberAuthority,
        userId: _bob,
      );
      makeProtected();
      final memberPack = await memberComponent.createPack('Member pack');

      // An admin is signed in too, holding its own component for the same space.
      // (buildComponent rebinds sdkRoom/sdkClient, so protect this copy too.)
      final adminAuthority = _FakeAuthorityClient();
      final adminComponent = buildComponent(
        authority: adminAuthority,
        userId: _alice,
      );
      makeProtected();
      final adminPack = await adminComponent.createPack('Admin pack');

      expect(memberPack.createdBy, _bob);
      expect(adminPack.createdBy, _alice);
      // Each mutation travelled through its own account's authority client.
      expect(
        memberAuthority.calls.where((c) => c.startsWith('createPack:')),
        hasLength(1),
      );
      expect(
        adminAuthority.calls.where((c) => c.startsWith('createPack:')),
        hasLength(1),
      );

      // Unprotected (direct-write) path attributes the same way.
      final directComponent = buildComponent(userId: _bob);
      final directPack = await directComponent.createPack('Direct pack');
      expect(directPack.createdBy, _bob);
      final write = sdkClient.stateWrites.singleWhere(
        (w) => w.type == SoundboardEventTypes.packState,
      );
      expect(write.content['created_by'], _bob);
    });
  });

  group('playSound refusal contract', () {
    const destSpaceId = '!dest:example.org';
    const callRoomId = '!call:example.org';

    // Builds a component whose OWN space (_spaceId) is the sound's source, with
    // the call living in a different destination space so the play classifies
    // as cross-space.
    ({MatrixSoundboardComponent component, _FakeCallRoom callRoom}) crossSpace({
      bool blockExternalPacks = false,
      bool blockingParentListedFirst = false,
      SoundboardAuthorityError? authorityFailure,
    }) {
      final sdk = _FakeSdkClient(_FakeSdkRoom(), userId: _alice);
      final callRoom = _FakeCallRoom(callRoomId);
      final client = _FakeMatrixClient(sdk)
        ..spaceList = [
          // A call room can be a child of more than one space. When it is,
          // _destinationSpaceIdFor returns the FIRST match in client.spaces, so
          // this leading entry is the one that must win. Its blocking policy is
          // what makes the choice observable: if resolution ever stopped
          // honouring order, the play would be allowed instead of refused.
          if (blockingParentListedFirst)
            _FakeDestinationSpace(
              '!first-parent:example.org',
              [callRoom],
              soundboard: _BlockingSoundboardComponent(),
            ),
          _FakeDestinationSpace(
            destSpaceId,
            [callRoom],
            soundboard: blockExternalPacks
                ? _BlockingSoundboardComponent()
                : null,
          ),
        ];
      final comp = MatrixSoundboardComponent(
        client,
        _FakeMatrixSpace(sdk.room),
        authorityClient: _FakeAuthorityClient()..failWith = authorityFailure,
      );
      // Same reason buildComponent registers one: this holds onRoomState and
      // onSync subscriptions plus an open StreamController, and an undisposed
      // component keeps reacting to writes made by later tests in this file.
      addTearDown(comp.dispose);
      return (component: comp, callRoom: callRoom);
    }

    final sound = SoundboardSound(
      id: 'sound-1',
      name: 'Horn',
      emoji: '🔊',
      mxcUri: Uri.parse('mxc://example.org/sound-1'),
      mimeType: 'audio/ogg',
      uploadedBy: _alice,
      createdAt: DateTime.utc(2026, 7, 1),
      sizeBytes: 1000,
    );

    test(
      'a call room parented to two spaces resolves to the first listed',
      () async {
        // Coverage gap: every other cross-space case seeds exactly one
        // candidate space, so _destinationSpaceIdFor's loop never actually
        // iterates and its first-match rule was asserted nowhere. This is the
        // sender-side mirror of what soundboard_playback_service_test pins for
        // the receiver ("the destination is the space the event names, not the
        // first parent") - and the two sides do NOT agree, because the sender
        // has only spaceList order to go on.
        //
        // Pinned as-is rather than changed: which parent *should* own the
        // destination is a product question, and picking one here would bake a
        // guess into a regression test. It is routed to FEATURES. If the answer
        // turns out to be "the space the pack came from", this test should fail
        // and be rewritten - that is the point of having it.
        // Only the FIRST space blocks; the second is permissive. So
        // `started: false` alone proves nothing here - every cross-space case
        // in this group refuses for one reason or another. The policy message
        // is the discriminator: it can only appear if the blocking parent is
        // the one that got resolved.
        final s = crossSpace(blockingParentListedFirst: true);

        final outcome = await s.component.playSound(
          sound,
          s.callRoom,
          callSessionId: 'session-1',
        );

        expect(outcome.started, isFalse);
        expect(outcome.reason, SoundboardPlayRefusal.authorizationRefused);
        expect(
          outcome.message,
          contains('other spaces'),
          reason:
              'the leading parent space owns the destination policy; a '
              'different refusal message means resolution stopped honouring '
              'spaceList order',
        );
      },
    );

    test(
      'a cross-space play with no call session refuses, not silently',
      () async {
        // Regression for the inconsistent-refusal report: this path used to
        // return null, and playSound then reported success, so the member got no
        // feedback and the sound simply did not play. It must now surface a
        // refusal with a message the caller can render.
        final s = crossSpace();

        final outcome = await s.component.playSound(
          sound,
          s.callRoom,
          callSessionId: null,
        );

        expect(outcome.started, isFalse);
        // Assert the structured code, not the copy: the refusal type is what
        // matters, and the message is free to be reworded.
        expect(outcome.reason, SoundboardPlayRefusal.noCallSession);
        expect(outcome.message, isNotNull);
      },
    );

    test('a play while signed out reports notSignedIn', () async {
      // SoundboardPlayRefusal exists so callers can branch on the reason rather
      // than parse the message, which makes an unmapped or mis-mapped reason a
      // silent behaviour change. This is the first of the mappings that had no
      // coverage: every existing case reached one of three reasons, so the
      // other three could have been swapped for each other undetected.
      final sdk = _FakeSdkClient(_FakeSdkRoom(), userId: null);
      final client = _FakeMatrixClient(sdk);
      final comp = MatrixSoundboardComponent(
        client,
        _FakeMatrixSpace(sdk.room),
        authorityClient: _FakeAuthorityClient(),
      );
      addTearDown(comp.dispose);

      final outcome = await comp.playSound(sound, _FakeCallRoom(callRoomId));

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.notSignedIn);
      expect(outcome.message, isNotNull);
    });

    test('a send the homeserver does not accept reports emissionFailed', () async {
      // The last of the six mappings. This one is NOT a clean refusal: local
      // playback already ran, so the sender heard the sound and only the call
      // missed it. It is reported through the same outcome channel rather than
      // thrown so callers have one contract to handle, which is exactly why the
      // reason code needs pinning - the message alone cannot distinguish it
      // from a refusal that never played anything.
      final sdk = _FakeSdkClient(_FakeSdkRoom());
      final client = _FakeMatrixClient(sdk);
      final comp = MatrixSoundboardComponent(
        client,
        _FakeMatrixSpace(sdk.room),
        authorityClient: _FakeAuthorityClient(),
      );
      addTearDown(comp.dispose);

      final sdkRoom = _NonAcceptingSdkRoom();
      final outcome = await comp.playSound(
        sound,
        _FakeOwnedRoomWithFailingSend(sdkRoom),
      );

      expect(
        sdkRoom.sendEventCalls,
        1,
        reason:
            'The send must actually be attempted - a refusal raised before the '
            'send would reach this reason code for the wrong cause.',
      );
      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.emissionFailed);
      expect(outcome.message, isNotNull);
    });

    test('a call room with no resolvable parent space reports '
        'destinationUnresolved', () async {
      // An empty spaceList is the "not synced yet, a DM, or no parent at all"
      // case: the room is not owned by this component's space, so the play is
      // cross-space, but no destination can be resolved to authorize against.
      // It must refuse rather than fall through to a same-space event, which
      // would emit an UNAUTHORIZED cross-space play - so this test is guarding
      // an authorization bypass, not just a message.
      final sdk = _FakeSdkClient(_FakeSdkRoom());
      final client = _FakeMatrixClient(sdk)..spaceList = const [];
      final comp = MatrixSoundboardComponent(
        client,
        _FakeMatrixSpace(sdk.room),
        authorityClient: _FakeAuthorityClient(),
      );
      addTearDown(comp.dispose);

      final outcome = await comp.playSound(
        sound,
        _FakeCallRoom(callRoomId),
        callSessionId: 'session-1',
      );

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.destinationUnresolved);
      expect(outcome.message, isNotNull);
    });

    test(
      'a blocked destination policy refuses with the policy reason',
      () async {
        // The path most likely to regress: this one throws inside
        // _authorizeCrossSpacePlay and relies on playSound's try/catch to turn
        // it into an outcome. Without a case here that conversion is untested,
        // and a regression would surface as an exception escaping into the
        // picker rather than a rendered refusal.
        final s = crossSpace(blockExternalPacks: true);

        final outcome = await s.component.playSound(
          sound,
          s.callRoom,
          callSessionId: 'session-1',
        );

        expect(outcome.started, isFalse);
        expect(outcome.reason, SoundboardPlayRefusal.authorizationRefused);
        expect(outcome.message, isNotNull);
        expect(
          outcome.message,
          contains('other spaces'),
          reason:
              'the policy reason must reach the caller, not a generic '
              'fallback message',
        );
      },
    );

    test(
      'a play into a non-Matrix room refuses rather than returning void',
      () async {
        final s = crossSpace();

        final outcome = await s.component.playSound(sound, _NotAMatrixRoom());

        expect(outcome.started, isFalse);
        expect(outcome.reason, SoundboardPlayRefusal.unsupportedRoom);
        expect(outcome.message, isNotNull);
      },
    );

    // The authority service's playback handler raises `forbidden` for FOUR
    // conditions and none of them is "the service is not in the source space".
    // Each gets its own test with the message the service actually sends,
    // because an earlier revision classified every `forbidden` as the
    // source-space case and then DISCARDED that message — so a member whose
    // sound had simply been deleted was told to go enable sound protection.
    // These are the regression guards for that.
    Future<SoundboardPlayOutcome> refuseWith(
      SoundboardAuthorityErrorCode code,
      String message,
    ) async {
      final s = crossSpace(
        authorityFailure: SoundboardAuthorityError(
          code: code,
          message: message,
          retryable: false,
        ),
      );
      return s.component.playSound(
        sound,
        s.callRoom,
        callSessionId: 'session-1',
      );
    }

    test('a deleted source sound keeps its message, no hint', () async {
      final outcome = await refuseWith(
        SoundboardAuthorityErrorCode.forbidden,
        'Source sound is unavailable.',
      );

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.authorizationRefused);
      expect(outcome.message, 'Source sound is unavailable.');
    });

    test('a deleted or unshared pack keeps its message, no hint', () async {
      final outcome = await refuseWith(
        SoundboardAuthorityErrorCode.forbidden,
        'Source pack is unavailable.',
      );

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.authorizationRefused);
      expect(outcome.message, 'Source pack is unavailable.');
    });

    test('a caller-permission failure keeps its message, no hint', () async {
      // A permission failure belonging to the CALLER, not to the service.
      // Enrolling the space would not change it.
      final outcome = await refuseWith(
        SoundboardAuthorityErrorCode.forbidden,
        'Caller cannot access the source space.',
      );

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.authorizationRefused);
      expect(outcome.message, 'Caller cannot access the source space.');
    });

    test('a not_found refusal hints but keeps the service message', () async {
      // `not_found` is raised on the playback path only by the source-space
      // auth-state read, so it is the one code CONSISTENT with the service not
      // being in the source space. It still is not proof, so the service
      // message survives and the UI adds the hint as a possibility.
      final outcome = await refuseWith(
        SoundboardAuthorityErrorCode.notFound,
        'Source space is not available to the service.',
      );

      expect(outcome.started, isFalse);
      expect(outcome.reason, SoundboardPlayRefusal.sourceSpaceUnavailable);
      expect(outcome.message, 'Source space is not available to the service.');
    });

    test('a transient authority failure stays authorizationRefused', () async {
      // A rate limit or an upstream outage is NOT fixed by enrolling the
      // source space, so it must not borrow the sourceSpaceUnavailable hint.
      for (final code in const [
        SoundboardAuthorityErrorCode.rateLimited,
        SoundboardAuthorityErrorCode.upstreamUnavailable,
      ]) {
        final s = crossSpace(
          authorityFailure: SoundboardAuthorityError(
            code: code,
            message: 'Try again shortly.',
            retryable: true,
          ),
        );

        final outcome = await s.component.playSound(
          sound,
          s.callRoom,
          callSessionId: 'session-1',
        );

        expect(outcome.started, isFalse);
        expect(
          outcome.reason,
          SoundboardPlayRefusal.authorizationRefused,
          reason: '$code is transient, not a source-space setup problem',
        );
        // The reason alone does not pin this: `authorizationRefused` is also
        // produced by the destination-policy branch and by other
        // pre-authorization failures, so without the message this passed
        // whether or not `createPlaybackAuthorization` ever ran. The three
        // `forbidden` tests above assert the exact service message for the
        // same reason.
        expect(
          outcome.message,
          'Try again shortly.',
          reason:
              'the refusal must carry the authority failure, proving the '
              'authority call is what refused',
        );
      }
    });
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeSdkRoom implements matrix.Room {
  @override
  Map<String, Map<String, matrix.StrippedStateEvent>> states = {};

  @override
  Map<String, matrix.BasicEvent> roomAccountData = {};

  final Set<String> allowedStateEvents = {
    SoundboardEventTypes.soundState,
    SoundboardEventTypes.packState,
    SoundboardEventTypes.userState,
    matrix.EventTypes.RoomPowerLevels,
  };

  void applyState(
    String type,
    String stateKey,
    Map<String, dynamic> content, {
    required String senderId,
  }) {
    states.putIfAbsent(type, () => {})[stateKey] = matrix.StrippedStateEvent(
      type: type,
      content: content,
      senderId: senderId,
      stateKey: stateKey,
    );
  }

  @override
  bool canChangeStateEvent(String action) =>
      allowedStateEvents.contains(action);

  @override
  matrix.StrippedStateEvent? getState(String typeKey, [String stateKey = '']) =>
      states[typeKey]?[stateKey];

  @override
  Future<void> postLoad() async {}

  @override
  Future<matrix.SyncUpdate> waitForRoomInSync() async =>
      matrix.SyncUpdate(nextBatch: '');

  @override
  Future<matrix.Event?> getEventById(String eventID) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records routed authority calls and returns configurable results, so
/// dual-path tests assert what the component sends without a live service.
class _FakeAuthorityClient implements SoundboardAuthorityClient {
  @override
  Future<SoundboardAuthorityResult<List<SoundboardVerificationKey>>>
  fetchVerificationKeys() async {
    calls.add('fetchVerificationKeys');
    return _result(const <SoundboardVerificationKey>[]);
  }

  final List<String> calls = [];
  final List<Map<String, Object?>> soundCreates = [];
  final List<Map<String, dynamic>> createPackRequests = [];
  final List<String> deletedPacks = [];
  final List<String> deletedSounds = [];
  SoundboardAuthorityError? failWith;
  SoundboardAuthorityError? failOnceWith;

  SoundboardAuthorityResult<T> _result<T>(T value) {
    final error = failOnceWith ?? failWith;
    failOnceWith = null;
    return error != null
        ? SoundboardAuthorityFailure<T>(error)
        : SoundboardAuthoritySuccess<T>(value);
  }

  SoundboardAuthorityPackState _pack(String id) => SoundboardAuthorityPackState(
    schemaVersion: 1,
    packId: id,
    name: 'x',
    emoji: '🔊',
    creatorUserId: _alice,
    createdAt: DateTime.utc(2026, 7, 18),
    updatedAt: DateTime.utc(2026, 7, 18),
    updatedBy: _alice,
    revision: 1,
    disabled: false,
    deleted: false,
  );

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  enableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    int? memberUploadLevel,
  }) async {
    calls.add('enableProtection:level=$memberUploadLevel');
    return _result(
      SoundboardAuthoritySpaceProtection(
        sourceSpaceId: sourceSpaceId,
        protectedState: true,
        lockedLevel: 100,
        memberUploadLevel: memberUploadLevel ?? 0,
      ),
    );
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthoritySpaceProtection>>
  disableSpaceProtection({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
  }) async {
    calls.add('disableProtection');
    return _result(
      SoundboardAuthoritySpaceProtection(
        sourceSpaceId: sourceSpaceId,
        protectedState: false,
      ),
    );
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> createPack(
    SoundboardAuthorityCreatePackRequest request,
  ) async {
    calls.add('createPack:${request.packId}');
    createPackRequests.add(request.toJson());
    return _result(_pack(request.packId));
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> updatePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
    String? name,
    String? emoji,
    bool? disabled,
  }) async {
    calls.add(
      'updatePack:$packId:rev$expectedRevision:name=$name:emoji=$emoji:disabled=$disabled',
    );
    return _result(_pack(packId));
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardAuthorityPackState>> deletePack({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String packId,
    required int expectedRevision,
  }) async {
    calls.add('deletePack:$packId');
    deletedPacks.add(packId);
    return _result(_pack(packId));
  }

  @override
  Future<SoundboardAuthorityResult<void>> createSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required SoundboardAuthoritySoundContent content,
  }) async {
    calls.add('createSound:$soundId');
    soundCreates.add({
      'sound_id': soundId,
      'pack_id': packId,
      ...content.toJson(),
    });
    return _result(null);
  }

  @override
  Future<SoundboardAuthorityResult<void>> updateSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
    int? volume,
  }) async {
    calls.add('updateSound:$soundId:vol$volume:rev$expectedRevision');
    return _result(null);
  }

  @override
  Future<SoundboardAuthorityResult<void>> moveSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required String packId,
    required int expectedRevision,
  }) async {
    calls.add('moveSound:$soundId->$packId');
    return _result(null);
  }

  @override
  Future<SoundboardAuthorityResult<void>> deleteSound({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String soundId,
    required int expectedRevision,
  }) async {
    calls.add('deleteSound:$soundId');
    deletedSounds.add(soundId);
    return _result(null);
  }

  @override
  Future<SoundboardAuthorityResult<SoundboardPlaybackAuthorization>>
  createPlaybackAuthorization({
    required String requestId,
    required SoundboardAuthorityOpenIdProof auth,
    required String sourceSpaceId,
    required String destinationRoomId,
    required String callSessionId,
    required String packId,
    required String soundId,
  }) async {
    calls.add('createPlaybackAuthorization:$sourceSpaceId:$packId:$soundId');
    final error = failWith;
    if (error != null) {
      return SoundboardAuthorityFailure<SoundboardPlaybackAuthorization>(error);
    }
    // No test needs a successful cross-space authorization value yet; the
    // refusal-classification cases all drive this through failWith.
    //
    // Recorded, not only thrown. `playSound` catches around this call and
    // converts anything thrown into `SoundboardPlayRefusal.authorizationRefused`
    // - so a future test that reaches here without setting `failWith` would get
    // a plausible refusal instead of a fixture failure, and would pass for
    // entirely the wrong reason. The marker makes that visible to an assertion.
    calls.add('createPlaybackAuthorization:UNIMPLEMENTED');
    throw UnimplementedError(
      'No successful cross-space authorization fixture is defined; set '
      'failWith, or add one.',
    );
  }
}

class _StateWrite {
  _StateWrite(this.type, this.stateKey, this.content);

  final String type;
  final String stateKey;
  final Map<String, dynamic> content;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient(this.room, {String? userId = _alice}) : _userId = userId;

  final _FakeSdkRoom room;
  // Nullable so the signed-out path can be exercised: userID is null exactly
  // when there is no session, and that is what playSound branches on.
  final String? _userId;
  final List<_StateWrite> stateWrites = [];
  final List<Map<String, dynamic>> accountDataWrites = [];
  final Set<String> failSoundStateKeysOnce = {};

  /// Number of leading `uploadContent` calls that throw a transient network
  /// error before one succeeds, plus the running total of attempts made.
  int uploadTransientFailures = 0;
  int uploadAttempts = 0;
  var _eventCounter = 0;

  @override
  final CachedStreamController<
    ({String roomId, matrix.StrippedStateEvent state})
  >
  onRoomState = CachedStreamController();

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  /// Simulates a sync that delivers new room account data for [room]: applies
  /// it to the room (as the SDK does before notifying) and emits the update.
  Future<void> syncRoomAccountData(
    String roomId,
    String type,
    Map<String, dynamic> content,
  ) async {
    final event = matrix.BasicEvent(type: type, content: content);
    room.roomAccountData[type] = event;
    onSync.add(
      matrix.SyncUpdate(
        nextBatch: 'sync-${++_eventCounter}',
        rooms: matrix.RoomsUpdate(
          join: {
            roomId: matrix.JoinedRoomUpdate(accountData: [event]),
          },
        ),
      ),
    );
    // Let the broadcast listener run.
    await Future<void>.delayed(Duration.zero);
  }

  @override
  String? get userID => _userId;

  @override
  Future<String> setRoomStateWithKey(
    String roomId,
    String eventType,
    String stateKey,
    Map<String, Object?> body,
  ) async {
    if (eventType == SoundboardEventTypes.soundState &&
        failSoundStateKeysOnce.remove(stateKey)) {
      throw Exception('sound state write failed');
    }
    final content = Map<String, dynamic>.from(body);
    stateWrites.add(_StateWrite(eventType, stateKey, content));
    // State writes only happen on a signed-in path, so a null here would mean
    // the fake was driven into a state the component cannot actually reach.
    room.applyState(eventType, stateKey, content, senderId: _userId ?? _alice);
    return 'event-${++_eventCounter}';
  }

  @override
  Future<void> setAccountDataPerRoom(
    String userId,
    String roomId,
    String type,
    Map<String, Object?> body,
  ) async {
    final content = Map<String, dynamic>.from(body);
    accountDataWrites.add(content);
    room.roomAccountData[type] = matrix.BasicEvent(
      type: type,
      content: content,
    );
  }

  @override
  Future<Uri> uploadContent(
    Uint8List file, {
    String? filename,
    String? contentType,
  }) async {
    uploadAttempts++;
    if (uploadAttempts <= uploadTransientFailures) {
      // Matches the client-side transient-network signature the retry helper
      // classifies (BUG-254/BUG-266).
      throw const SocketException('Failed host lookup: matrix.example.org');
    }
    return Uri.parse('mxc://example.org/uploaded-${file.length}');
  }

  /// When set, [getRoomState] returns this instead of the room's current state,
  /// simulating the authoritative state the service wrote server-side but which
  /// the local DB has not yet synced (drives the post-mutation refresh).
  List<matrix.MatrixEvent>? serverStateOverride;

  @override
  Future<List<matrix.MatrixEvent>> getRoomState(String roomId) async {
    final override = serverStateOverride;
    if (override != null) {
      return override;
    }
    final result = <matrix.MatrixEvent>[];
    room.states.forEach((type, byKey) {
      byKey.forEach((key, event) {
        result.add(
          matrix.MatrixEvent(
            type: event.type,
            content: event.content,
            senderId: event.senderId,
            stateKey: event.stateKey,
            eventId: 'srv-${++_eventCounter}',
            originServerTs: DateTime.utc(2026, 7, 19),
          ),
        );
      });
    });
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this._sdkClient);

  final _FakeSdkClient _sdkClient;

  /// Spaces this client can see. Cross-space playSound tests set this to a
  /// destination space that owns the call room; empty otherwise.
  List<Space> spaceList = const [];

  @override
  matrix.Client get matrixClient => _sdkClient;

  @override
  List<Space> get spaces => spaceList;

  /// Needed by the SAME-space play path only: local playback asks for the space
  /// to resolve an active call session. Cross-space cases never reach it, which
  /// is why the fake did without this until emissionFailed was covered.
  /// Returning null means "no active session", which is correct here — the test
  /// is about the send failing, not about session state.
  @override
  Space? getSpace(String identifier) =>
      spaceList.where((s) => s.identifier == identifier).firstOrNull;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A Room that is not a MatrixRoom, to exercise playSound's room-type guard.
class _NotAMatrixRoom implements Room {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A call room owned by a space other than the component's own, enough for
/// _destinationSpaceIdFor to classify a play as cross-space.
class _FakeCallRoom implements MatrixRoom {
  _FakeCallRoom(this._identifier);

  final String _identifier;

  @override
  String get identifier => _identifier;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A room the component's own space owns (identifier matches [_spaceId]), whose
/// send never lands.
///
/// Explicit rather than relying on the other fakes' `noSuchMethod`: those throw
/// `NoSuchMethodError` for `sendEvent`, which playSound's catch would also turn
/// into `emissionFailed` — so a test written against them would pass because the
/// fake is incomplete, not because the refusal path works. This returns `null`,
/// which is the real "homeserver did not accept the event" branch.
class _FakeOwnedRoomWithFailingSend implements MatrixRoom {
  _FakeOwnedRoomWithFailingSend(this._sdkRoom);

  final _NonAcceptingSdkRoom _sdkRoom;

  @override
  String get identifier => _spaceId;

  @override
  matrix.Room get matrixRoom => _sdkRoom;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NonAcceptingSdkRoom implements matrix.Room {
  int sendEventCalls = 0;

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = matrix.EventTypes.Message,
    String? txid,
    matrix.Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    sendEventCalls++;
    // null is the real "homeserver did not accept the event" branch, which
    // playSound turns into emissionFailed.
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The destination space that hosts the call room, distinct from the source
/// space that owns the sound.
class _FakeDestinationSpace implements Space {
  _FakeDestinationSpace(this._identifier, this._rooms, {this.soundboard});

  final String _identifier;
  final List<Room> _rooms;

  /// Present when the test needs the destination to express a policy; null
  /// models a destination with no soundboard, which _authorizeCrossSpacePlay
  /// treats as allowed.
  final SoundboardComponent? soundboard;

  @override
  String get identifier => _identifier;

  @override
  List<Room> get roomsWithChildren => _rooms;

  @override
  T? getComponent<T extends SpaceComponent>() => soundboard as T?;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A destination soundboard whose administrator has blocked external packs.
class _BlockingSoundboardComponent implements SoundboardComponent {
  @override
  SoundboardDestinationPolicy get destinationPolicy =>
      const SoundboardDestinationPolicy(allowExternalPacks: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixSpace implements MatrixSpace {
  _FakeMatrixSpace(this._room);

  final _FakeSdkRoom _room;

  @override
  matrix.Room get matrixRoom => _room;

  @override
  String get identifier => _spaceId;

  /// The component's own space owns no child rooms in these fixtures - a call
  /// room that belongs here is modelled by [_FakeDestinationSpace] instead.
  /// Needed because playSound asks its own space whether it owns the call room
  /// before treating a play as cross-space; without it the fake throws.
  @override
  List<Room> get roomsWithChildren => const [];

  @override
  void notifyUpdate() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
