import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:intergalactic/client/components/gif/gif_component.dart';
import 'package:intergalactic/client/components/gif/gif_search_result.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/matrix_timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/config/gif_api_key_store.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:http/http.dart' as http;

import 'package:matrix/matrix.dart' as matrix;

class GifSendException implements Exception {
  final String message;

  const GifSendException(this.message);

  @override
  String toString() => "GifSendException: $message";
}

class MatrixGifComponent implements GifComponent<MatrixClient, MatrixRoom> {
  @override
  MatrixClient client;

  @override
  MatrixRoom room;

  MatrixGifComponent(this.client, this.room);

  @override
  String get searchPlaceholder => "Search KLIPY";

  static const String _klipyApiHost = "api.klipy.com";
  static const int _sizeLimit = 3000000;

  String get _gifApiBaseUrl => GifApiKeyStore.relayBaseUrl ?? "";

  Future<http.Response?> _getWithTimeout(
    Uri uri, {
    required String failureMessage,
  }) async {
    try {
      return await http.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: failureMessage);
      return null;
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: failureMessage);
      return null;
    }
  }

  @override
  Future<List<GifSearchResult>> search(String query) async {
    // The ui should never actually let the user search if this is disabled, so this *shouldn't* be neccessary
    // but just to be safe!
    if (!preferences.gifSearchEnabled.value) return [];

    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];

    if (_gifApiBaseUrl.isNotEmpty) {
      final proxiedResults = await _searchViaRelay(trimmedQuery);
      if (proxiedResults != null) {
        return proxiedResults;
      }
    }

    final klipyApiKey = GifApiKeyStore.apiKey;
    if (klipyApiKey == null) return [];

    final uri = Uri.https(_klipyApiHost, "/v2/search", {
      "q": trimmedQuery,
      "key": klipyApiKey,
      "limit": "24",
      "media_filter": "tinygif,nanogif,mediumgif,gif,webp",
    });

    final result = await _getWithTimeout(
      uri,
      failureMessage: "Failed to search KLIPY directly.",
    );
    if (result == null) {
      return [];
    }

    if (result.statusCode == 200) {
      final data = _tryDecodeJsonMap(
        result.body,
        failureMessage: "Failed to decode KLIPY search response.",
      );
      if (data == null) {
        return [];
      }

      final results = _extractResults(data);

      if (results != null) {
        return results.map(_parseResult).whereType<GifSearchResult>().toList();
      }
    }

    return [];
  }

  Future<List<GifSearchResult>?> _searchViaRelay(String query) async {
    try {
      final uri = _buildProxyUri("search", {
        "q": query,
        "limit": "24",
        "media_filter": "tinygif,nanogif,mediumgif,gif,webp",
      });

      final result = await http.get(uri).timeout(const Duration(seconds: 20));
      if (result.statusCode != 200) {
        Log.w("GIF relay search returned ${result.statusCode} for $uri");
        return null;
      }

      final data = _tryDecodeJsonMap(
        result.body,
        failureMessage: "Failed to decode GIF relay search response.",
      );
      if (data == null) {
        return null;
      }

      final results = data['results'];
      if (results is! List) {
        return null;
      }

      return results
          .whereType<Map<String, dynamic>>()
          .map(_parseResult)
          .whereType<GifSearchResult>()
          .toList();
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace,
          content: "Failed to search GIF relay. Falling back when a "
              "local KLIPY key exists.");
      return null;
    }
  }

  @override
  Future<TimelineEvent?> sendGif(
    GifSearchResult gif,
    TimelineEvent? inReplyTo, {
    String? threadRootEventId,
    String? threadLastEventId,
  }) async {
    var matrixRoom = room.matrixRoom;
    final download = await _downloadGif(gif);
    if (download == null) {
      throw const GifSendException(
          "Failed to download the selected GIF before upload.");
    }

    matrix.Event? replyingTo;
    final uri = await matrixRoom.client.uploadContent(download.data,
        filename: download.filename, contentType: download.mimeType);

    final content = {
      "body": download.filename,
      "url": uri.toString(),
      if (preferences.stickerCompatibilityMode.value) "msgtype": "m.image",
      if (preferences.stickerCompatibilityMode.value)
        "chat.commet.type": "chat.commet.sticker",
      "info": {
        "chat.commet.animated": true,
        "w": gif.x.toInt(),
        "h": gif.y.toInt(),
        "mimetype": download.mimeType
      }
    };

    if (inReplyTo != null) {
      replyingTo = await matrixRoom.getEventById(inReplyTo.eventId);
    }

    var id = await matrixRoom.sendEvent(content,
        type: preferences.stickerCompatibilityMode.value
            ? matrix.EventTypes.Message
            : matrix.EventTypes.Sticker,
        inReplyTo: replyingTo,
        threadRootEventId: threadRootEventId,
        threadLastEventId: threadLastEventId);

    if (id == null) {
      throw const GifSendException(
          "Matrix did not return an event id for the GIF send.");
    }

    var event = await matrixRoom.getEventById(id);
    if (event != null && room.timeline is MatrixTimeline) {
      return room.convertEvent(event,
          timeline: (room.timeline as MatrixTimeline).matrixTimeline);
    }

    return null;
  }

  Future<_GifDownloadResult?> _downloadGif(GifSearchResult gif) async {
    final candidates = _buildDownloadCandidates(gif);

    for (final candidate in candidates) {
      final download = await _downloadGifCandidate(
        candidate,
        fallbackMimeType: gif.mimeType,
      );
      if (download == null) {
        continue;
      }

      return download;
    }

    return null;
  }

  Future<_GifDownloadResult?> _downloadGifCandidate(
    Uri candidate, {
    required String fallbackMimeType,
  }) async {
    final client = http.Client();

    try {
      final response = await client
          .send(http.Request('GET', candidate))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        Log.w(
            "GIF download returned ${response.statusCode} for ${candidate.toString()}");
        return null;
      }

      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > _sizeLimit) {
        Log.w(
            "GIF download exceeded $_sizeLimit bytes before streaming: ${candidate.toString()}");
        return null;
      }

      final bytes = BytesBuilder(copy: false);
      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 20))) {
        bytes.add(chunk);
        if (bytes.length > _sizeLimit) {
          Log.w(
              "GIF download exceeded $_sizeLimit bytes while streaming: ${candidate.toString()}");
          return null;
        }
      }

      final data = bytes.takeBytes();
      if (data.isEmpty) {
        Log.w(
            "GIF download returned an empty body for ${candidate.toString()}");
        return null;
      }

      final mimeType = _resolveMimeType(response, fallbackMimeType);
      if (!_isSupportedGifMimeType(mimeType)) {
        Log.w(
            "Rejecting GIF download with unsupported mime type $mimeType for ${candidate.toString()}");
        return null;
      }

      if (!_matchesMediaSignature(data, mimeType)) {
        Log.w(
            "Rejecting GIF download whose payload does not match $mimeType for ${candidate.toString()}");
        return null;
      }

      return _GifDownloadResult(
        data: data,
        filename: _resolveFilename(candidate, mimeType),
        mimeType: mimeType,
      );
    } on TimeoutException catch (error, stackTrace) {
      Log.onError(error, stackTrace,
          content: "Timed out downloading GIF candidate $candidate");
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace,
          content: "Failed to download GIF candidate $candidate");
    } finally {
      client.close();
    }

    return null;
  }

  List<Uri> _buildDownloadCandidates(GifSearchResult gif) {
    final candidates = <Uri>[];
    final seen = <String>{};

    void addCandidate(Uri uri) {
      final key = uri.toString();
      if (seen.add(key)) {
        candidates.add(uri);
      }
    }

    void addSource(Uri source) {
      final relayed = _relayMediaUri(source);
      if (relayed != null) {
        addCandidate(relayed);
      }
      addCandidate(source);
    }

    addSource(gif.fullResUrl);
    if (gif.previewUrl != gif.fullResUrl) {
      addSource(gif.previewUrl);
    }

    return candidates;
  }

  List<Map<String, dynamic>>? _extractResults(Map<String, dynamic> data) {
    final directResults = data['results'];
    if (directResults is List) {
      return directResults.whereType<Map<String, dynamic>>().toList();
    }

    final payload = data['data'];
    if (payload is Map<String, dynamic>) {
      final nestedResults = payload['data'];
      if (nestedResults is List) {
        return nestedResults.whereType<Map<String, dynamic>>().toList();
      }
    }

    return null;
  }

  GifSearchResult? _parseResult(Map<String, dynamic> result) {
    final mediaFormats = result['media_formats'];
    if (mediaFormats is Map<String, dynamic>) {
      return _parseFormats(mediaFormats);
    }

    final files = result['files'];
    if (files is Map<String, dynamic>) {
      return _parseFormats(files);
    }

    return null;
  }

  GifSearchResult? _parseFormats(Map<String, dynamic> formats) {
    Map<String, dynamic>? preview =
        _pickFormat(formats, ['tinygif', 'nanogif', 'mediumgif', 'gif']);
    var fullRes =
        _pickFormat(formats, ['gif', 'mediumgif', 'tinygif', 'nanogif']);
    final webp = formats['webp'];

    if (fullRes == null && webp is Map<String, dynamic>) {
      fullRes = webp;
    }

    if (preview == null && webp is Map<String, dynamic>) {
      preview = webp;
    }

    if (preview == null || fullRes == null) {
      return null;
    }

    String mimeType = identical(fullRes, webp) ? "image/webp" : "image/gif";

    final fullResSize = _readInt(fullRes['size']);
    if (fullResSize != null &&
        fullResSize > _sizeLimit &&
        formats['mediumgif'] is Map<String, dynamic>) {
      fullRes = formats['mediumgif'] as Map<String, dynamic>;
      mimeType = "image/gif";
    }

    if (webp is Map<String, dynamic>) {
      final webpSize = _readInt(webp['size']);
      final previewSize = _readInt(preview['size']);
      if (webpSize != null && previewSize != null && webpSize < previewSize) {
        preview = webp;
      }
    }

    return _buildGifSearchResult(preview, fullRes, mimeType);
  }

  Map<String, dynamic>? _pickFormat(
      Map<String, dynamic> formats, List<String> keys) {
    for (final key in keys) {
      final value = formats[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }

    return null;
  }

  GifSearchResult? _buildGifSearchResult(Map<String, dynamic> preview,
      Map<String, dynamic> fullRes, String mimeType) {
    final previewUrl = _readUrl(preview['url']);
    final fullResUrl = _readUrl(fullRes['url']);
    final dimsValue = fullRes['dims'] ?? fullRes['dimensions'];
    final dims = dimsValue is List ? dimsValue : null;

    if (previewUrl == null ||
        fullResUrl == null ||
        dims == null ||
        dims.length < 2) {
      return null;
    }

    final width = _readDouble(dims[0]);
    final height = _readDouble(dims[1]);
    if (width == null || height == null) {
      return null;
    }

    return GifSearchResult(previewUrl, fullResUrl, width, height, mimeType);
  }

  Uri? _readUrl(dynamic value) {
    if (value is String && value.isNotEmpty) {
      try {
        return Uri.parse(value);
      } catch (error, stackTrace) {
        Log.onError(error, stackTrace,
            content: "Ignoring malformed KLIPY media url: $value");
      }
    }

    return null;
  }

  int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }

    return null;
  }

  double? _readDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }

    return null;
  }

  Map<String, dynamic>? _tryDecodeJsonMap(
    String body, {
    required String failureMessage,
  }) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      Log.w("$failureMessage Expected a JSON object.");
    } on FormatException catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: failureMessage);
    } on TypeError catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: failureMessage);
    }

    return null;
  }

  String _resolveMimeType(http.BaseResponse response, String fallbackMimeType) {
    final header = response.headers['content-type'];
    if (header == null || header.isEmpty) {
      return fallbackMimeType;
    }

    return header.split(';').first.trim();
  }

  String _resolveFilename(Uri uri, String mimeType) {
    if (uri.pathSegments.isNotEmpty) {
      final last = uri.pathSegments.last;
      if (last.isNotEmpty) {
        return last;
      }
    }

    final extension = switch (mimeType) {
      "image/webp" => ".webp",
      "image/gif" => ".gif",
      _ => "",
    };

    return "sticker$extension";
  }

  Uri _buildProxyUri(String path, [Map<String, String>? queryParameters]) {
    final base = Uri.parse(_gifApiBaseUrl);
    final basePath = base.path.endsWith("/") ? base.path : "${base.path}/";
    return base.replace(
      path: "$basePath$path",
      queryParameters: queryParameters,
    );
  }

  Uri? _relayMediaUri(Uri source) {
    if (_gifApiBaseUrl.isEmpty) {
      return null;
    }

    final base = Uri.parse(_gifApiBaseUrl);
    final basePath = base.path.endsWith("/") ? base.path : "${base.path}/";

    if (source.scheme == base.scheme &&
        source.host == base.host &&
        source.port == base.port &&
        source.path.startsWith("${basePath}media/")) {
      return source;
    }

    if (!_isKlipyHost(source.host)) {
      return null;
    }

    return base.replace(
      path: "${basePath}media${source.path}",
      query: source.hasQuery ? source.query : null,
      fragment: null,
    );
  }

  bool _isKlipyHost(String host) {
    return host == "klipy.com" || host.endsWith(".klipy.com");
  }

  bool _isSupportedGifMimeType(String mimeType) {
    return mimeType == "image/gif" || mimeType == "image/webp";
  }

  bool _matchesMediaSignature(Uint8List data, String mimeType) {
    if (mimeType == "image/gif") {
      return _hasAsciiPrefix(data, "GIF87a") || _hasAsciiPrefix(data, "GIF89a");
    }

    if (mimeType == "image/webp") {
      return _hasAsciiPrefix(data, "RIFF") &&
          data.length >= 12 &&
          String.fromCharCodes(data.sublist(8, 12)) == "WEBP";
    }

    return false;
  }

  bool _hasAsciiPrefix(Uint8List data, String prefix) {
    if (data.length < prefix.length) {
      return false;
    }

    for (var i = 0; i < prefix.length; i++) {
      if (data[i] != prefix.codeUnitAt(i)) {
        return false;
      }
    }

    return true;
  }
}

class _GifDownloadResult {
  final Uint8List data;
  final String filename;
  final String mimeType;

  const _GifDownloadResult({
    required this.data,
    required this.filename,
    required this.mimeType,
  });
}
