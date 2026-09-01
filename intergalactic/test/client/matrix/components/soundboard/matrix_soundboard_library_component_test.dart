import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/components/soundboard/matrix_soundboard_library_component.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:matrix/matrix.dart' as matrix;
// Reaching into `matrix/src/` is not a choice here. The fake below overrides
// `matrix.Client.onSync`, whose declared type in the SDK is
// `CachedStreamController<SyncUpdate>` (client.dart:1801) - but `matrix.dart`
// does not export `cached_stream_controller.dart`, so the type is public API
// with no public import path. Any fake of `Client` has to reach in. Drop this
// import if the SDK ever exports the type.
import 'package:matrix/src/utils/cached_stream_controller.dart';

const _alice = '@alice:example.org';
const _bob = '@bob:example.org';
const _spaceA = '!spaceA:example.org';
const _spaceB = '!spaceB:example.org';

void main() {
  late _FakeSdkClient sdk;
  late _FakeMatrixClient client;
  late MatrixSoundboardLibraryComponent component;

  /// Builds an account whose spaces each expose a soundboard with [packs].
  MatrixSoundboardLibraryComponent build({
    String userId = _alice,
    Map<String, List<SoundboardPack>> spacePacks = const {},
    Map<String, List<SoundboardSound>> spaceSounds = const {},
    Map<String, dynamic>? libraryContent,
  }) {
    sdk = _FakeSdkClient(userId: userId);
    if (libraryContent != null) {
      sdk.accountData[SoundboardEventTypes.globalPackReferences] =
          matrix.BasicEvent(
            type: SoundboardEventTypes.globalPackReferences,
            content: libraryContent,
          );
    }
    final spaces = <Space>[
      for (final entry in spacePacks.entries)
        _FakeSpace(
          entry.key,
          packs: entry.value,
          sounds: spaceSounds[entry.key] ?? const [],
        ),
    ];
    client = _FakeMatrixClient(sdk, spaces);
    return MatrixSoundboardLibraryComponent(client);
  }

  tearDown(() async {
    await component.dispose();
  });

  SoundboardPack pack(String id, {bool enabled = true, bool deleted = false}) =>
      SoundboardPack(
        id: id,
        name: id,
        createdBy: _alice,
        createdAt: DateTime.utc(2026, 7, 1),
        updatedAt: DateTime.utc(2026, 7, 1),
        enabled: enabled,
        deleted: deleted,
      );

  SoundboardSound sound(String id, {String? packId}) => SoundboardSound(
    id: id,
    name: id,
    emoji: '🔊',
    mxcUri: Uri.parse('mxc://example.org/$id'),
    mimeType: 'audio/ogg',
    uploadedBy: _alice,
    createdAt: DateTime.utc(2026, 7, 1),
    sizeBytes: 1000,
    packId: packId,
  );

  Map<String, dynamic> documentWith(List<List<String>> refs) => {
    'packs': [
      for (final r in refs) {'source_space_id': r[0], 'pack_id': r[1]},
    ],
  };

  group('resolution against the source space', () {
    test('a live reference resolves with its pack and that pack\'s sounds', () {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1'), pack('pack-2')],
        },
        spaceSounds: {
          _spaceA: [
            sound('s1', packId: 'pack-1'),
            sound('s2', packId: 'pack-1'),
            sound('other', packId: 'pack-2'),
          ],
        },
        libraryContent: documentWith([
          [_spaceA, 'pack-1'],
        ]),
      );

      final entry = component.entries.single;
      expect(entry.isResolved, isTrue);
      expect(entry.pack?.id, 'pack-1');
      expect(entry.sourceSpaceName, isNotNull);
      // Only the referenced pack's sounds, not the whole space.
      expect(entry.sounds.map((s) => s.id), ['s1', 's2']);
    });

    test('a legacy pack resolves with its loose sounds', () {
      // Reported: a legacy pack could be enabled globally but never showed up
      // in another space's in-call picker. Its sounds carry no pack_id at all,
      // so matching on the raw reference resolved zero sounds, and the picker
      // skips sound-less entries - the pack was enabled and invisible.
      final legacyId = SoundboardPack.legacyIdForUploader(_alice);
      component = build(
        spacePacks: {
          _spaceA: [pack(legacyId), pack('explicit')],
        },
        spaceSounds: {
          _spaceA: [
            sound('loose-1'),
            sound('loose-2'),
            sound('owned', packId: 'explicit'),
          ],
        },
        libraryContent: documentWith([
          [_spaceA, legacyId],
        ]),
      );

      final entry = component.entries.single;
      expect(entry.isResolved, isTrue);
      expect(entry.pack?.id, legacyId);
      // The loose sounds, and only those - not the explicitly-packed one.
      expect(entry.sounds.map((s) => s.id), ['loose-1', 'loose-2']);
    });

    test('another member\'s loose sounds stay out of this legacy pack', () {
      // Legacy packs are per-uploader, so the derivation must not sweep up
      // every unreferenced sound in the space.
      final aliceLegacy = SoundboardPack.legacyIdForUploader(_alice);
      component = build(
        spacePacks: {
          _spaceA: [pack(aliceLegacy)],
        },
        spaceSounds: {
          _spaceA: [
            sound('alice-loose'),
            SoundboardSound(
              id: 'bob-loose',
              name: 'bob-loose',
              emoji: '🔊',
              mxcUri: Uri.parse('mxc://example.org/bob-loose'),
              mimeType: 'audio/ogg',
              uploadedBy: _bob,
              createdAt: DateTime.utc(2026, 7, 1),
              sizeBytes: 1000,
            ),
          ],
        },
        libraryContent: documentWith([
          [_spaceA, aliceLegacy],
        ]),
      );

      expect(component.entries.single.sounds.map((s) => s.id), ['alice-loose']);
    });

    test('the library holds references, never copies of sounds', () {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
        spaceSounds: {
          _spaceA: [sound('s1', packId: 'pack-1')],
        },
        libraryContent: documentWith([
          [_spaceA, 'pack-1'],
        ]),
      );

      // The written document carries coordinates only - no sound payload.
      final written = component.library.toContent();
      final entries = written['packs'] as List;
      expect(entries.single, {'source_space_id': _spaceA, 'pack_id': 'pack-1'});
    });

    test('a reference to a space this account left is stale, not fatal', () {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
        libraryContent: documentWith([
          [_spaceA, 'pack-1'],
          [_spaceB, 'pack-9'],
        ]),
      );

      final entries = component.entries;
      expect(entries, hasLength(2));
      expect(entries.first.isResolved, isTrue);
      expect(entries.last.isStale, isTrue);
      // Stale entries stay listed so the member can see what became
      // unavailable, but never count as usable.
      expect(component.usableEntries.map((e) => e.reference.packId), [
        'pack-1',
      ]);
    });

    test('a deleted or disabled source pack is excluded immediately', () {
      component = build(
        spacePacks: {
          _spaceA: [
            pack('gone', deleted: true),
            pack('off', enabled: false),
            pack('live'),
          ],
        },
        libraryContent: documentWith([
          [_spaceA, 'gone'],
          [_spaceA, 'off'],
          [_spaceA, 'live'],
        ]),
      );

      expect(component.usableEntries.map((e) => e.reference.packId), ['live']);
      // Excluded immediately on read - no write needed for correctness.
      expect(sdk.accountDataWrites, isEmpty);
    });
  });

  group('enable and disable', () {
    test('enabling writes a reference and nothing else', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
      );

      expect(component.canEnable(_spaceA, 'pack-1'), isTrue);
      await component.enablePack(_spaceA, 'pack-1');

      expect(component.isEnabled(_spaceA, 'pack-1'), isTrue);
      final write = sdk.accountDataWrites.single;
      expect(write.type, SoundboardEventTypes.globalPackReferences);
      expect(write.userId, _alice);
      final packs = (write.content['packs'] as List).cast<Map>();
      expect(packs.single['source_space_id'], _spaceA);
      expect(packs.single['pack_id'], 'pack-1');
    });

    test('a pack this account cannot read cannot be enabled', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1', deleted: true)],
        },
      );

      expect(component.canEnable(_spaceA, 'pack-1'), isFalse);
      expect(component.canEnable(_spaceB, 'pack-1'), isFalse);
      await expectLater(
        component.enablePack(_spaceB, 'pack-1'),
        throwsException,
      );
      expect(sdk.accountDataWrites, isEmpty);
    });

    test('disabling one pack preserves the others in the document', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1'), pack('pack-2')],
        },
        libraryContent: documentWith([
          [_spaceA, 'pack-1'],
          [_spaceA, 'pack-2'],
        ]),
      );

      await component.disablePack(_spaceA, 'pack-1');

      final packs = (sdk.accountDataWrites.single.content['packs'] as List)
          .cast<Map>();
      expect(packs.map((p) => p['pack_id']), ['pack-2']);
    });

    test('a write rebases onto account data that changed underneath', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1'), pack('pack-2')],
        },
      );

      // Another device enabled pack-9 between our read and our write.
      sdk.accountData[SoundboardEventTypes.globalPackReferences] =
          matrix.BasicEvent(
            type: SoundboardEventTypes.globalPackReferences,
            content: documentWith([
              [_spaceB, 'pack-9'],
            ]),
          );

      await component.enablePack(_spaceA, 'pack-1');

      final packs = (sdk.accountDataWrites.single.content['packs'] as List)
          .cast<Map>();
      expect(
        packs.map((p) => '${p['source_space_id']}|${p['pack_id']}').toList()
          ..sort(),
        ['$_spaceA|pack-1', '$_spaceB|pack-9'],
      );
    });

    test('a failed write restores the last confirmed state', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
      );
      sdk.failNextAccountDataWrite = true;

      await expectLater(
        component.enablePack(_spaceA, 'pack-1'),
        throwsException,
      );

      // The optimistic entry is rolled back; the UI never shows a change the
      // server rejected.
      expect(component.isEnabled(_spaceA, 'pack-1'), isFalse);
    });
  });

  group('stale reference pruning', () {
    test('drops only references whose source is gone', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('live')],
        },
        libraryContent: documentWith([
          [_spaceA, 'live'],
          [_spaceB, 'orphan'],
        ]),
      );

      await component.pruneStaleReferences();

      final packs = (sdk.accountDataWrites.single.content['packs'] as List)
          .cast<Map>();
      expect(packs.map((p) => p['pack_id']), ['live']);
    });

    test('a clean library is not rewritten', () async {
      component = build(
        spacePacks: {
          _spaceA: [pack('live')],
        },
        libraryContent: documentWith([
          [_spaceA, 'live'],
        ]),
      );

      await component.pruneStaleReferences();

      expect(sdk.accountDataWrites, isEmpty);
    });

    test(
      'a failed prune leaves the document untouched, and does not throw',
      () async {
        component = build(
          spacePacks: {
            _spaceA: [pack('live')],
          },
          libraryContent: documentWith([
            [_spaceA, 'live'],
            [_spaceB, 'orphan'],
          ]),
        );
        sdk.failNextAccountDataWrite = true;

        // Housekeeping must not surface as an error to the caller.
        await component.pruneStaleReferences();

        expect(component.entries, hasLength(2));
      },
    );
  });

  group('multi-account isolation', () {
    test('each account reads and writes only its own document', () async {
      // Account A.
      component = build(
        userId: _alice,
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
        libraryContent: documentWith([
          [_spaceA, 'pack-1'],
        ]),
      );
      final aliceSdk = sdk;
      expect(component.entries.single.reference.packId, 'pack-1');
      await component.dispose();

      // Account B, signed in at the same time, has its own document and its
      // own spaces - account A's globals must not appear here.
      component = build(
        userId: _bob,
        spacePacks: {
          _spaceB: [pack('pack-2')],
        },
      );
      expect(component.entries, isEmpty);
      expect(component.isEnabled(_spaceA, 'pack-1'), isFalse);

      await component.enablePack(_spaceB, 'pack-2');

      // The write went to B's session, under B's user id, and A's session was
      // never touched.
      expect(sdk.accountDataWrites.single.userId, _bob);
      expect(aliceSdk.accountDataWrites, isEmpty);
    });

    test('a session without a user id refuses to write', () async {
      component = build(
        userId: '',
        spacePacks: {
          _spaceA: [pack('pack-1')],
        },
      );

      await expectLater(
        component.enablePack(_spaceA, 'pack-1'),
        throwsStateError,
      );
      expect(sdk.accountDataWrites, isEmpty);
    });
  });

  test('a sync carrying the document notifies listeners', () async {
    component = build(
      spacePacks: {
        _spaceA: [pack('pack-1')],
      },
    );
    var notifications = 0;
    final subscription = component.onChanged.listen((_) => notifications++);

    sdk.accountData[SoundboardEventTypes.globalPackReferences] =
        matrix.BasicEvent(
          type: SoundboardEventTypes.globalPackReferences,
          content: documentWith([
            [_spaceA, 'pack-1'],
          ]),
        );
    sdk.emitAccountDataSync(SoundboardEventTypes.globalPackReferences);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, 1);
    expect(component.isEnabled(_spaceA, 'pack-1'), isTrue);

    // An unrelated account-data sync does not churn listeners.
    sdk.emitAccountDataSync('im.ponies.user_emotes');
    await Future<void>.delayed(Duration.zero);
    expect(notifications, 1);

    await subscription.cancel();
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _AccountDataWrite {
  _AccountDataWrite(this.userId, this.type, this.content);

  final String userId;
  final String type;
  final Map<String, Object?> content;
}

class _FakeSdkClient implements matrix.Client {
  _FakeSdkClient({required this.userId});

  final String userId;
  final List<_AccountDataWrite> accountDataWrites = [];
  bool failNextAccountDataWrite = false;
  var _counter = 0;

  @override
  final Map<String, matrix.BasicEvent> accountData = {};

  @override
  final CachedStreamController<matrix.SyncUpdate> onSync =
      CachedStreamController();

  @override
  String? get userID => userId.isEmpty ? null : userId;

  void emitAccountDataSync(String type) {
    onSync.add(
      matrix.SyncUpdate(
        nextBatch: 'sync-${++_counter}',
        accountData: [matrix.BasicEvent(type: type, content: const {})],
      ),
    );
  }

  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> body,
  ) async {
    if (failNextAccountDataWrite) {
      failNextAccountDataWrite = false;
      throw Exception('account data write failed');
    }
    accountDataWrites.add(_AccountDataWrite(userId, type, body));
    accountData[type] = matrix.BasicEvent(
      type: type,
      content: Map<String, dynamic>.from(body),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMatrixClient implements MatrixClient {
  _FakeMatrixClient(this._sdk, this._spaces);

  final _FakeSdkClient _sdk;
  final List<Space> _spaces;

  @override
  matrix.Client get matrixClient => _sdk;

  @override
  List<Space> get spaces => _spaces;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A space exposing a soundboard component with fixed packs/sounds — enough
/// for the library to resolve references without a homeserver.
class _FakeSpace implements Space {
  _FakeSpace(
    this._identifier, {
    required List<SoundboardPack> packs,
    required List<SoundboardSound> sounds,
  }) : _soundboard = _FakeSoundboard(packs: packs, sounds: sounds);

  final String _identifier;
  final _FakeSoundboard _soundboard;

  @override
  String get identifier => _identifier;

  @override
  String get displayName => 'Space $_identifier';

  @override
  T? getComponent<T extends SpaceComponent>() {
    if (_soundboard is T) {
      return _soundboard as T;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSoundboard implements SoundboardComponent {
  _FakeSoundboard({required this.packs, required this.sounds});

  @override
  final List<SoundboardPack> packs;

  @override
  final List<SoundboardSound> sounds;

  @override
  SoundboardPack? packById(String packId) {
    for (final pack in packs) {
      if (pack.id == packId) {
        return pack;
      }
    }
    return null;
  }

  /// Real behaviour, not stubs. Resolving a pack's sounds by the RAW
  /// sound.packId is the defect these mirror out: a loose sound carries no
  /// pack_id and belongs to its uploader's derived legacy pack.
  @override
  String effectivePackIdFor(SoundboardSound sound) =>
      sound.packId ?? SoundboardPack.legacyIdForUploader(sound.uploadedBy);

  @override
  List<SoundboardSound> soundsInPack(String packId) => sounds
      .where((sound) => effectivePackIdFor(sound) == packId)
      .toList(growable: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
