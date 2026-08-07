import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/components/space_component.dart';

abstract class SoundboardComponent<R extends Client, S extends Space>
    extends SpaceComponent<R, S> {
  static const int maxSoundBytes = 2 * 1024 * 1024;
  static const Duration recommendedMaxDuration = Duration(seconds: 8);

  SoundboardComponent(super.client, super.space);

  List<SoundboardSound> get sounds;

  Stream<void> get onChanged;

  bool get canUploadSound;

  bool get memberUploadsEnabled;

  bool get canEnableMemberUploads;

  int get soundUploadPowerLevel;

  int get defaultUserPowerLevel;

  int? get currentUserPowerLevel;

  String? getJoinSoundId(String userId);

  bool canManageSound(SoundboardSound sound, String userId);

  Future<void> refreshSounds();

  Future<void> enableMemberUploads();

  Future<SoundboardSound> uploadSound({
    required String name,
    required String emoji,
    required Uint8List bytes,
    required String mimeType,
    int? durationMs,
    double volume = SoundboardSound.defaultVolume,
  });

  Future<void> updateSoundVolume(SoundboardSound sound, double volume);

  Future<void> deleteSound(SoundboardSound sound);

  Future<void> setJoinSoundForUser(String userId, String? soundId);

  Future<void> playSound(
    SoundboardSound sound,
    Room room, {
    String source = 'manual',
    String? callSessionId,
  });
}
