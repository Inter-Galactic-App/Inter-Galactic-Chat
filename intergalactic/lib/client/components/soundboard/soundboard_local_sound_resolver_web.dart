import 'package:intergalactic/client/components/soundboard/soundboard_local_sound_cache.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_file_provider.dart';

Future<Uri?> resolveSoundboardLocalUri(
  MatrixClient client,
  SoundboardSound sound,
) {
  return MxcFileProvider(client.matrixClient, sound.mxcUri).resolve();
}

Future<SoundboardCachePruneResult> pruneSoundboardLocalCache({
  Uri? protectedUri,
}) async {
  return const SoundboardCachePruneResult.empty();
}
