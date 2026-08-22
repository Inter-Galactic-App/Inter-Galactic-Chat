import 'dart:typed_data';

import 'package:intergalactic/utils/local_file.dart';

class DownloadProgress {
  int downloaded;
  int total;

  DownloadProgress(this.downloaded, this.total);
}

abstract class FileProvider {
  Future<Uri?> resolve();

  Future<void> save(String filepath);

  Stream<DownloadProgress>? get onProgressChanged;

  Future<Uint8List?> getFileData();

  String get fileIdentifier;
}

class SystemFileProvider implements FileProvider {
  final String path;

  @override
  String get fileIdentifier => path;

  @override
  Future<Uri?> resolve() async {
    return getLocalFileUri(path);
  }

  @override
  Future<void> save(String filepath) {
    throw UnimplementedError();
  }

  SystemFileProvider(this.path);

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() {
    return readLocalFileBytes(path);
  }
}
