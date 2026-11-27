import 'dart:typed_data';
import 'package:intergalactic/client/matrix/extensions/matrix_client_extensions.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/local_file.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:matrix/matrix.dart';

import '../../utils/image/lod_image.dart';

class MatrixMxcImage extends LODImageProvider {
  Uri identifier;
  Client client;
  MatrixMxcImage(
    this.identifier,
    this.client, {
    super.blurhash,
    bool? doThumbnail,
    bool? doFullres,
    bool cache = true,
    super.autoLoadFullRes,
    super.thumbnailHeight,
    super.fullResHeight,
    Event? matrixEvent,
  }) : super(
          id: "$identifier-$doThumbnail-$doFullres-$thumbnailHeight-$fullResHeight",
          loadThumbnail: (doThumbnail == null || doThumbnail == true)
              ? () => retryUntilOnline<Uint8List?>(
                  client,
                  () => loadMatrixThumbnail(
                        client,
                        identifier,
                        matrixEvent,
                        cache: cache,
                      ))
              : null,
          loadFullRes: (doFullres == null || doFullres == true)
              ? () => retryUntilOnline<Uint8List?>(
                  client,
                  () => loadMatrixFullRes(
                        client,
                        identifier,
                        matrixEvent,
                        cache: cache,
                      ))
              : null,
        );

  static String getThumbnailIdentifier(Uri uri) {
    return "matrix_thumbnail-$uri";
  }

  static String getIdentifier(Uri uri) {
    return "matrix-$uri";
  }

  static Future<T> retryUntilOnline<T>(
      Client client, Future<T> callback()) async {
    try {
      var value = await callback();
      return value;
    } catch (error, trace) {
      if (error.toString().contains('SocketException')) {
        while (true) {
          var result = await client.onSyncStatus.stream.first;

          if (result.status == SyncStatus.finished) {
            var result = await callback();
            return result;
          }
        }
      } else if (error is MatrixException &&
          error.error == MatrixError.M_UNKNOWN_TOKEN &&
          client.onSoftLogout != null) {
        Log.w(
          'Matrix media request hit M_UNKNOWN_TOKEN. Attempting session repair and retrying once.',
        );
        await client.refreshAccessToken();
        return await callback();
      } else if (_isMatrixMediaNotFound(error) && null is T) {
        _logMissingMedia(thumbnail: null, encrypted: null);
        return null as T;
      } else {
        Log.onError(error, trace);
        rethrow;
      }
    }
  }

  static Future<Uint8List?> loadMatrixThumbnail(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
  }) async {
    var identifier = getThumbnailIdentifier(uri);

    if (await fileCache?.hasFile(identifier) == true) {
      var cacheUri = await fileCache?.getFile(identifier);

      if (cacheUri != null) {
        return readBytesFromUri(cacheUri);
      }
    }

    Uint8List? bytes;
    if (matrixEvent != null) {
      try {
        var data = await matrixEvent.downloadAndDecryptAttachment(
          getThumbnail: true,
        );

        String mime = matrixEvent.thumbnailMimetype;

        if (mime == '') {
          mime = Mime.lookupType('', data: data.bytes) ?? '';
        }

        if (Mime.imageTypes.contains(mime)) {
          bytes = data.bytes;
        } else {
          Log.w("Attachment thumbnail had unknown mime type: '${mime}'");
        }
      } catch (error) {
        if (_isMatrixMediaNotFound(error)) {
          _logMissingMedia(thumbnail: true, encrypted: true);
          return null;
        }
        rethrow;
      }
    } else {
      try {
        var response = await client.getContentThumbnailFromUri(uri, 90, 90);
        bytes = response.data;
      } catch (error) {
        if (_isMatrixMediaNotFound(error)) {
          _logMissingMedia(thumbnail: true, encrypted: false);
          return null;
        }
        rethrow;
      }
    }

    if (bytes != null && cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
  }

  static Future<Uint8List?> loadMatrixFullRes(
    Client client,
    Uri uri,
    Event? matrixEvent, {
    bool cache = true,
  }) async {
    var identifier = getIdentifier(uri);

    if (await fileCache?.hasFile(identifier) == true) {
      var cacheUri = await fileCache?.getFile(identifier);

      if (cacheUri != null) {
        return readBytesFromUri(cacheUri);
      }
    }

    Uint8List? bytes;
    if (matrixEvent != null) {
      try {
        var data = await matrixEvent.downloadAndDecryptAttachment();

        bytes = data.bytes;
      } catch (error) {
        if (_isMatrixMediaNotFound(error)) {
          _logMissingMedia(thumbnail: false, encrypted: true);
          return null;
        }
        rethrow;
      }
    } else {
      try {
        var response = await client.getContentFromUri(uri);
        bytes = response.data;
      } catch (error) {
        if (_isMatrixMediaNotFound(error)) {
          _logMissingMedia(thumbnail: false, encrypted: false);
          return null;
        }
        rethrow;
      }
    }

    if (cache) {
      fileCache?.putFile(identifier, bytes);
      return bytes;
    }

    return null;
  }

  @override
  Future<bool> hasCachedThumbnail() async {
    var id = getThumbnailIdentifier(identifier);
    return await fileCache?.hasFile(id) == true;
  }

  @override
  Future<bool> hasCachedFullres() async {
    var id = getIdentifier(identifier);
    return await fileCache?.hasFile(id) == true;
  }

  @override
  bool operator ==(Object other) {
    if (other.runtimeType != runtimeType) return false;
    bool res = other is MatrixMxcImage && other.identifier == identifier;
    return res;
  }

  @override
  int get hashCode => identifier.hashCode;

  static bool _isMatrixMediaNotFound(Object error) =>
      error is MatrixException && error.error == MatrixError.M_NOT_FOUND;

  static void _logMissingMedia({
    required bool? thumbnail,
    required bool? encrypted,
  }) {
    Log.w(
      'Matrix media request returned M_NOT_FOUND; '
      'showing unavailable image thumbnail=$thumbnail encrypted=$encrypted',
      category: LogCategory.media,
      source: 'matrix-mxc-image',
    );
  }
}
