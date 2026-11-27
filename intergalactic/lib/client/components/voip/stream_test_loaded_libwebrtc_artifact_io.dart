import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:intergalactic/client/components/voip/stream_test_loaded_libwebrtc_artifact_model.dart';

Future<StreamTestLoadedLibwebrtcArtifact?>
    loadStreamTestLoadedLibwebrtcArtifact() async {
  final fileName = _platformLibwebrtcFileName();
  if (fileName == null) {
    return null;
  }
  final executable = File(Platform.resolvedExecutable);
  final file = File(
    '${executable.parent.path}${Platform.pathSeparator}$fileName',
  );
  if (!await file.exists()) {
    return null;
  }
  final stat = await file.stat();
  final digest = await crypto.sha256.bind(file.openRead()).first;
  return StreamTestLoadedLibwebrtcArtifact(
    fileName: fileName,
    location: 'executable_directory/$fileName',
    sha256: digest.toString().toUpperCase(),
    sizeBytes: stat.size,
    modifiedAtUtc: stat.modified.toUtc(),
  );
}

String? _platformLibwebrtcFileName() {
  if (Platform.isWindows) {
    return 'libwebrtc.dll';
  }
  if (Platform.isMacOS) {
    return 'libwebrtc.dylib';
  }
  if (Platform.isLinux) {
    return 'libwebrtc.so';
  }
  return null;
}
