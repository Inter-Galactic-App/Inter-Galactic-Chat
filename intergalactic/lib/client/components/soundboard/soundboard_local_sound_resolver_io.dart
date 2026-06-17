import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_models.dart';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

const int _minSoundBytes = 16;

Future<Uri?> resolveSoundboardLocalUri(
  MatrixClient client,
  SoundboardSound sound,
) async {
  final directory = Directory(
    path.join((await getTemporaryDirectory()).path, 'intergalactic_soundboard'),
  );
  await directory.create(recursive: true);

  final extension = _extensionForMime(
    sound.mimeType,
    originalName: sound.name,
  );
  final file =
      File(path.join(directory.path, '${_cacheToken(sound)}$extension'));
  if (await file.exists() && await file.length() == sound.sizeBytes) {
    return file.uri;
  }

  final response = await client.matrixClient.getContentFromUri(sound.mxcUri);
  final bytes = response.data;
  if (!_isValidSoundPayload(bytes.length, sound.sizeBytes)) {
    if (await file.exists()) {
      await file.delete();
    }
    return null;
  }

  await file.writeAsBytes(bytes, flush: true);
  return file.uri;
}

String _cacheToken(SoundboardSound sound) {
  final payload = jsonEncode({
    'id': sound.id,
    'mxc': sound.mxcUri.toString(),
    'mime': sound.mimeType,
    'size': sound.sizeBytes,
  });
  return sha256.convert(utf8.encode(payload)).toString();
}

bool _isValidSoundPayload(int actualBytes, int expectedBytes) {
  if (actualBytes < _minSoundBytes) {
    return false;
  }
  return expectedBytes <= 0 || actualBytes == expectedBytes;
}

String _extensionForMime(String mimeType, {String? originalName}) {
  final normalized = mimeType.toLowerCase().split(';').first.trim();
  final mappedExtension = switch (normalized) {
    'audio/aac' => '.aac',
    'audio/x-aac' => '.aac',
    'audio/flac' => '.flac',
    'audio/x-flac' => '.flac',
    'audio/mp4' => '.m4a',
    'audio/x-m4a' => '.m4a',
    'audio/mp3' => '.mp3',
    'audio/mpeg3' => '.mp3',
    'audio/mpeg' => '.mp3',
    'audio/x-mp3' => '.mp3',
    'audio/x-mpeg' => '.mp3',
    'audio/x-mpeg-3' => '.mp3',
    'audio/ogg' => '.ogg',
    'audio/opus' => '.opus',
    'audio/wav' => '.wav',
    'audio/wave' => '.wav',
    'audio/x-wav' => '.wav',
    'audio/vnd.wave' => '.wav',
    'audio/webm' => '.webm',
    _ => null,
  };

  if (mappedExtension != null) {
    return mappedExtension;
  }

  final originalExtension =
      originalName == null ? '' : path.extension(originalName).toLowerCase();
  return switch (originalExtension) {
    '.aac' ||
    '.flac' ||
    '.m4a' ||
    '.mp3' ||
    '.ogg' ||
    '.opus' ||
    '.wav' ||
    '.webm' =>
      originalExtension,
    _ => '.sound',
  };
}
