import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_component.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/space_component.dart';
import 'package:intergalactic/client/components/profile/profile_component.dart';

/// Shared in-memory soundboard fakes for pack-aware widget tests.

const fakeSelfUser = '@self:example.org';
const fakeOtherUser = '@other:example.org';

SoundboardSound fakeSound(
  String id, {
  required String name,
  required String uploadedBy,
  String? packId,
}) {
  return SoundboardSound(
    id: id,
    name: name,
    emoji: '🔊',
    mxcUri: Uri.parse('mxc://example.org/$id'),
    mimeType: 'audio/ogg',
    uploadedBy: uploadedBy,
    createdAt: DateTime.utc(2026, 7, 1),
    sizeBytes: 100,
    packId: packId,
  );
}

class FakePackSoundboardComponent extends SoundboardComponent<Client, Space> {
  FakePackSoundboardComponent() : super(FakePackClient(), FakePackSpace()) {
    sounds2.addAll([
      fakeSound('self-horn', name: 'My horn', uploadedBy: fakeSelfUser),
      fakeSound(
        'other-raid',
        name: 'Air raid',
        uploadedBy: fakeOtherUser,
        packId: 'party-pack',
      ),
    ]);
    explicitPacks['party-pack'] = SoundboardPack(
      id: 'party-pack',
      name: 'Party pack',
      createdBy: fakeOtherUser,
      createdAt: DateTime.utc(2026, 7, 1),
      updatedAt: DateTime.utc(2026, 7, 1),
    );
  }

  final List<SoundboardSound> sounds2 = [];
  final Map<String, SoundboardPack> explicitPacks = {};
  final Map<String, bool> activeOverrides = {};
  final StreamController<void> _onChanged = StreamController.broadcast();

  bool admin = false;
  final createdPackNames = <String>[];
  final deletedPackIds = <String>[];
  final moves = <(String soundId, String packId)>[];

  void emitChanged() => _onChanged.add(null);

  @override
  List<SoundboardSound> get sounds =>
      sounds2.where((sound) => sound.isAvailable).toList(growable: false);

  @override
  List<SoundboardPack> get packs {
    return [
      ...explicitPacks.values.where((pack) => !pack.deleted),
      ...SoundboardComponent.deriveLegacyPacks(
        sounds,
        explicitPacks.keys.toSet(),
      ),
    ];
  }

  @override
  Set<String> get activePackIds {
    final result = <String>{};
    for (final pack in packs) {
      if (!pack.isAvailable) {
        continue;
      }
      final active =
          activeOverrides[pack.id] ?? (pack.createdBy == fakeSelfUser);
      if (active) {
        result.add(pack.id);
      }
    }
    return result;
  }

  @override
  List<SoundboardSound> soundsInPack(String packId) => sounds
      .where((sound) => effectivePackIdFor(sound) == packId)
      .toList(growable: false);

  @override
  Stream<void> get onChanged => _onChanged.stream;

  @override
  bool get canUploadSound => true;

  @override
  bool get canCreatePack => true;

  @override
  bool get memberUploadsEnabled => true;

  @override
  bool get canEnableMemberUploads => admin;

  @override
  int get soundUploadPowerLevel => 0;

  @override
  int get packCreationPowerLevel => 0;

  @override
  int get defaultUserPowerLevel => 0;

  @override
  int? get currentUserPowerLevel => 0;

  @override
  String? getJoinSoundId(String userId) => null;

  @override
  bool canManageSound(SoundboardSound sound, String userId) =>
      sound.uploadedBy == userId || admin;

  @override
  bool canManagePack(SoundboardPack pack, String userId) =>
      pack.createdBy == userId || admin;

  @override
  Future<void> refreshSounds() async {}

  @override
  Future<void> enableMemberUploads() async {}

  @override
  Future<void> alignPackCreationPermission() async {}

  @override
  Future<SoundboardPack> createPack(String name) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Sound packs need a name.');
    }
    createdPackNames.add(trimmedName);
    final pack = SoundboardPack(
      id: 'pack-${createdPackNames.length}',
      name: trimmedName,
      createdBy: fakeSelfUser,
      createdAt: DateTime.utc(2026, 7, 2),
      updatedAt: DateTime.utc(2026, 7, 2),
    );
    explicitPacks[pack.id] = pack;
    emitChanged();
    return pack;
  }

  @override
  Future<void> renamePack(SoundboardPack pack, String name) async {
    explicitPacks[pack.id] = pack.copyWith(name: name.trim());
    emitChanged();
  }

  final packEmojiWrites = <(String packId, String? emoji)>[];

  @override
  Future<void> setPackEmoji(SoundboardPack pack, String? emoji) async {
    final trimmed = emoji?.trim();
    final normalized = trimmed != null && trimmed.isNotEmpty ? trimmed : null;
    packEmojiWrites.add((pack.id, normalized));
    explicitPacks[pack.id] = pack.copyWith(
      emoji: normalized,
      clearEmoji: normalized == null,
    );
    emitChanged();
  }

  @override
  Future<void> setPackEnabled(SoundboardPack pack, bool enabled) async {
    explicitPacks[pack.id] = pack.copyWith(enabled: enabled);
    emitChanged();
  }

  @override
  Future<void> setPackActive(SoundboardPack pack, bool active) async {
    activeOverrides[pack.id] = active;
    emitChanged();
  }

  @override
  Future<void> deletePack(SoundboardPack pack) async {
    deletedPackIds.add(pack.id);
    explicitPacks[pack.id] = pack.copyWith(enabled: false, deleted: true);
    for (var index = 0; index < sounds2.length; index++) {
      if (effectivePackIdFor(sounds2[index]) == pack.id) {
        sounds2[index] = sounds2[index].copyWith(enabled: false, deleted: true);
      }
    }
    emitChanged();
  }

  @override
  Future<void> moveSoundToPack(SoundboardSound sound, String packId) async {
    moves.add((sound.id, packId));
    final index = sounds2.indexWhere((entry) => entry.id == sound.id);
    if (index < 0) {
      return;
    }
    if (packId ==
        SoundboardPack.legacyIdForUploader(sounds2[index].uploadedBy)) {
      sounds2[index] = sounds2[index].copyWith(clearPackId: true);
    } else {
      sounds2[index] = sounds2[index].copyWith(packId: packId);
    }
    emitChanged();
  }

  @override
  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
    String? packId,
  }) async => throw UnimplementedError();

  @override
  Future<void> updateSoundVolume(SoundboardSound sound, double volume) async {}

  @override
  Future<void> deleteSound(SoundboardSound sound) async {}

  @override
  Future<void> setJoinSoundForUser(String userId, String? soundId) async {}

  @override
  Future<SoundboardPlayOutcome> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  }) async => const SoundboardPlayOutcome.started();
}

class FakePackClient implements Client {
  @override
  Profile? self = _FakeSelfProfile();

  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSelfProfile implements Profile {
  @override
  String get identifier => fakeSelfUser;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePackSpace implements Space {
  /// Set after construction so the page under test can resolve the component
  /// from the space it received.
  SoundboardComponent? soundboard;

  @override
  final Client client = FakePackClient();

  @override
  String get identifier => '!space:example.org';

  @override
  String get displayName => 'Test Space';

  @override
  ImageProvider? get avatar => null;

  @override
  T? getComponent<T extends SpaceComponent>() =>
      soundboard is T ? soundboard as T : null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
