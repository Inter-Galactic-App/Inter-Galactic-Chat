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
          var request = http.Request('GET', url);
          request.headers
              .addAll({'authorization': 'Bearer ${client.accessToken}'});
          final response = await http.Client().send(request);

          List<int> downloadedBytes = response.contentLength != null
              ? Uint8List(response.contentLength!)
              : [];

          int downloaded = 0;
          if (response.statusCode != 200) {
            throw Exception('Unexpected response: ${response.statusCode}');
          }

          var lastUpdatedProgress = DateTime.now();

          var data = response.stream.listen(
            (event) {
              if (response.contentLength != null) {
                downloadedBytes.setAll(downloaded, event);
              } else {
                downloadedBytes.addAll(event);
              }
              downloaded += event.length;

              var now = DateTime.now();
              if (now.difference(lastUpdatedProgress).inMilliseconds > 16) {
                lastUpdatedProgress = now;

                fileDownloadProgress.add(
                    DownloadProgress(downloaded, response.contentLength ?? -1));
              }
            },
            cancelOnError: true,
          ).asFuture();

          await data;

          return Uint8List.fromList(downloadedBytes);
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
