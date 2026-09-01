import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/soundboard_settings_page.dart';

const _alice = '@alice:example.org';
const _spaceA = '!spaceA:example.org';
const _spaceB = '!spaceB:example.org';

/// U5 app-settings surface: which packs the selected account may enable
/// globally. The list is the account's own, and only offers packs that would
/// actually resolve once enabled.
void main() {
  SoundboardPack pack(
    String id, {
    String? name,
    bool enabled = true,
    bool deleted = false,
  }) => SoundboardPack(
    id: id,
    name: name ?? id,
    createdBy: _alice,
    createdAt: DateTime.utc(2026, 7, 1),
    updatedAt: DateTime.utc(2026, 7, 1),
    enabled: enabled,
    deleted: deleted,
  );

  SoundboardSound sound(String id, {String? packId, bool deleted = false}) =>
      SoundboardSound(
        id: id,
        name: id,
        emoji: '🔊',
        mxcUri: Uri.parse('mxc://example.org/$id'),
        mimeType: 'audio/ogg',
        uploadedBy: _alice,
        createdAt: DateTime.utc(2026, 7, 1),
        sizeBytes: 1000,
        packId: packId,
        deleted: deleted,
      );

  test('offers every readable pack that has sounds, named by its space', () {
    final client = _FakeClient([
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [pack('p1', name: 'Airhorns')],
        sounds: [
          sound('s1', packId: 'p1'),
          sound('s2', packId: 'p1'),
        ],
      ),
    ]);

    final candidates = collectGlobalPackCandidates(client);

    expect(candidates, hasLength(1));
    expect(candidates.single.pack.name, 'Airhorns');
    expect(candidates.single.space.displayName, 'Alpha');
    expect(candidates.single.soundCount, 2);
  });

  test('a legacy pack is offered, counting its unreferenced sounds', () {
    // Reported: a space's own sounds never appeared under "Global sound packs"
    // and so could not be enabled anywhere else. Sounds uploaded without a pack
    // carry no pack_id at all — they belong to the uploader's derived legacy
    // pack — so counting by the raw reference counted zero for exactly the pack
    // most members have, and it was dropped as empty.
    final legacyId = SoundboardPack.legacyIdForUploader(_alice);
    final client = _FakeClient([
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [pack(legacyId, name: 'Alice')],
        sounds: [sound('s1'), sound('s2')],
      ),
    ]);

    final candidates = collectGlobalPackCandidates(client);

    expect(candidates, hasLength(1));
    expect(candidates.single.pack.id, legacyId);
    expect(candidates.single.soundCount, 2);
  });

  test('a pack that would resolve to nothing is not offered', () {
    final client = _FakeClient([
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [
          pack('empty'),
          pack('deleted', deleted: true),
          pack('disabled', enabled: false),
          pack('live'),
        ],
        sounds: [
          sound('s1', packId: 'live'),
          // Deleted sounds do not make their pack worth enabling.
          sound('s2', packId: 'empty', deleted: true),
          sound('s3', packId: 'deleted'),
          sound('s4', packId: 'disabled'),
        ],
      ),
    ]);

    expect(collectGlobalPackCandidates(client).map((c) => c.pack.id), ['live']);
  });

  test('candidates come only from this account\'s spaces', () {
    // The account has joined Alpha only; Beta belongs to another signed-in
    // account and must not be offered here, or enabling it would write a
    // reference this account cannot resolve.
    final client = _FakeClient([
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [pack('p1')],
        sounds: [sound('s1', packId: 'p1')],
      ),
    ]);

    final candidates = collectGlobalPackCandidates(client);

    expect(candidates.map((c) => c.space.identifier), [_spaceA]);
    expect(candidates.any((c) => c.space.identifier == _spaceB), isFalse);
  });

  test('a space with no soundboard is skipped rather than throwing', () {
    final client = _FakeClient([
      _FakeSpace(_spaceB, 'Beta', packs: null, sounds: const []),
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [pack('p1')],
        sounds: [sound('s1', packId: 'p1')],
      ),
    ]);

    expect(collectGlobalPackCandidates(client), hasLength(1));
  });

  test('ordering is stable: by space name, then pack name', () {
    final client = _FakeClient([
      _FakeSpace(
        _spaceB,
        'Zulu',
        packs: [pack('z1', name: 'Zebra')],
        sounds: [sound('s1', packId: 'z1')],
      ),
      _FakeSpace(
        _spaceA,
        'Alpha',
        packs: [
          pack('a2', name: 'Bells'),
          pack('a1', name: 'Airhorns'),
        ],
        sounds: [
          sound('s2', packId: 'a2'),
          sound('s3', packId: 'a1'),
        ],
      ),
    ]);

    expect(collectGlobalPackCandidates(client).map((c) => c.pack.name), [
      'Airhorns',
      'Bells',
      'Zebra',
    ]);
  });
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeClient implements Client {
  _FakeClient(this._spaces);

  final List<Space> _spaces;

  @override
  List<Space> get spaces => _spaces;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSpace implements Space {
  _FakeSpace(
    this._identifier,
    this._displayName, {
    required List<SoundboardPack>? packs,
    required List<SoundboardSound> sounds,
  }) : _soundboard = packs == null
           ? null
           : _FakeSoundboard(packs: packs, sounds: sounds);

  final String _identifier;
  final String _displayName;
  final _FakeSoundboard? _soundboard;

  @override
  String get identifier => _identifier;

  @override
  String get displayName => _displayName;

  @override
  T? getComponent<T extends SpaceComponent>() {
    final soundboard = _soundboard;
    if (soundboard is T) {
      return soundboard as T;
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

  /// Real behaviour, not a stub: a sound with no reference belongs to its
  /// uploader's derived legacy pack. Stubbing this to `sound.packId` would let
  /// the legacy-pack regression back in through the fake.
  @override
  String effectivePackIdFor(SoundboardSound sound) =>
      sound.packId ?? SoundboardPack.legacyIdForUploader(sound.uploadedBy);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
