import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:http/http.dart' as http;

class MxcFileProvider implements FileProvider {
  final Uri uri;
  final matrix.Client client;
  final matrix.Event? event;
  @override
  String get fileIdentifier => uri.toString();

  MxcFileProvider(this.client, this.uri, {this.event});

  /// Downloads an event-backed attachment with a short-lived client.
  ///
  /// Event attachment downloads cannot use the Matrix client's shared HTTP
  /// client because the SDK supplies a fully resolved media URL to the
  /// callback. Keeping creation and disposal together makes every uncached
  /// event-backed download release its connection, including unencrypted
  /// attachments.
  static Future<Uint8List> downloadEventBackedMedia(
    Uri url, {
    required String? accessToken,
    required http.Client Function() createClient,
    void Function(int downloaded, int? total)? onChunk,
  }) async {
    final httpClient = createClient();
    try {
      final request = http.Request('GET', url);
      if (accessToken != null && accessToken.isNotEmpty) {
        request.headers['authorization'] = 'Bearer $accessToken';
      }

      final response = await httpClient.send(request);
      if (response.statusCode != 200) {
        throw Exception('Unexpected response: ${response.statusCode}');
      }

      final downloadedBytes = BytesBuilder(copy: false);
      var downloaded = 0;
      await for (final chunk in response.stream) {
        downloadedBytes.add(chunk);
        downloaded += chunk.length;
        onChunk?.call(downloaded, response.contentLength);
      }

      return downloadedBytes.takeBytes();
    } finally {
      httpClient.close();
    }
  }

  StreamController<DownloadProgress> fileDownloadProgress =
      StreamController.broadcast();

  @override
  Future<Uri?> resolve() async {
    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return cached;
    }

    var bytes = await getFileData();

    if (bytes == null) {
      return null;
    }

    return fileCache?.putFile(fileIdentifier, bytes);
  }

  @override
  Future<void> save(String filepath) async {
    var bytes = await getFileData();
    if (bytes == null) return;

    await writeLocalFileBytes(filepath, bytes);
  }

  Future<Uint8List?> getFileData() async {
    Uint8List? bytes;

    var cached = await fileCache?.getFile(fileIdentifier);
    if (cached != null) {
      return readBytesFromUri(cached);
    }

    if (event != null) {
      var file = await event!.downloadAndDecryptAttachment(
        downloadCallback: (url) async {
          var lastUpdatedProgress = DateTime.now();
          return downloadEventBackedMedia(
            url,
            accessToken: client.accessToken,
            createClient: () => http.Client(),
            onChunk: (downloaded, total) {
              final now = DateTime.now();
              if (now.difference(lastUpdatedProgress).inMilliseconds > 16) {
                lastUpdatedProgress = now;
                fileDownloadProgress.add(
                  DownloadProgress(downloaded, total ?? -1),
                );
              }
            },
          );
        },
      );
      bytes = file.bytes;
    } else {
      try {
        var response = await client.getContent(uri.authority, uri.path);
        bytes = response.data;
      } catch (e, t) {
        Log.onError(e, t, content: 'Failed to get mxc file content');
      }
    }

    return bytes;
  }

  @override
  Stream<DownloadProgress>? get onProgressChanged =>
      fileDownloadProgress.stream;
}
