import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/local_file.dart';

class CacheFileProvider implements FileProvider {
  @override
  late String fileIdentifier;
  Future<Uint8List> Function() getter;
  CacheFileProvider(this.fileIdentifier, this.getter);

  CacheFileProvider.thumbnail(String fileId, this.getter)
      : fileIdentifier = 'thumbnail_$fileId';

  @override
  Future<Uri?> resolve() async {
    return fileCache?.fetchFile(fileIdentifier, getter);
  }

  @override
  Future<void> save(String filepath) async {}

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uint8List?> getFileData() async {
    final path = await fileCache?.fetchFile(fileIdentifier, getter);
    if (path != null) {
      return readBytesFromUri(path);
    }

    return null;
  }
}
