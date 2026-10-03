import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/debug/log_redactor.dart';
import 'package:matrix/matrix.dart' as matrix;
import 'package:shared_preferences/shared_preferences.dart';

class UrlPreviewDurableCacheHit {
  const UrlPreviewDurableCacheHit({required this.data, required this.isStale});

  final UrlPreviewData data;
  final bool isStale;
}

class UrlPreviewDurableCache {
  UrlPreviewDurableCache({
    SharedPreferences? preferences,
    DateTime Function()? now,
    this.validTtl = const Duration(days: 5),
    this.volatileImageTtl = const Duration(hours: 12),
    this.invalidTtl = const Duration(minutes: 10),
    this.maxStaleAge = const Duration(days: 14),
    this.maxEntries = 500,
    this.prefix = 'url_preview_cache',
  }) : _preferences = preferences,
       _now = now ?? DateTime.now;

  // Version 2 stops preserving a site-name-only fallback across restarts. The
  // service can now resolve supported providers with actual preview content,
  // but version 1 records bypass that request forever until their normal TTL.
  static const int _version = 2;
  static const Set<String> _sensitiveQueryNames = {
    'access_token',
    'refresh_token',
    'matrix_access_token',
    'openid_token',
    'id_token',
    'auth_token',
    'authorization',
    'password',
    'passwd',
    'jwt',
    'livekit_jwt',
    'client_secret',
    'api_key',
    'secret',
    'token',
  };

  SharedPreferences? _preferences;
  final DateTime Function() _now;
  final Duration validTtl;
  final Duration volatileImageTtl;
  final Duration invalidTtl;
  final Duration maxStaleAge;
  final int maxEntries;
  final String prefix;

  Future<UrlPreviewDurableCacheHit?> get(
    Uri normalizedUri,
    matrix.Client matrixClient,
  ) async {
    if (!_isSafeToPersistUri(normalizedUri)) {
      return null;
    }

    try {
      final prefs = await _prefs();
      final key = _entryKey(_hashUri(normalizedUri));
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) {
        return null;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _removeKey(prefs, key);
        return null;
      }

      final cachedAtMs = _intValue(decoded['cached_at_ms']);
      if (cachedAtMs == null) {
        await _removeKey(prefs, key);
        return null;
      }

      final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      final age = _now().difference(cachedAt);
      final isInvalid = decoded['invalid'] == true;

      if (isInvalid) {
        if (age > invalidTtl) {
          await _removeKey(prefs, key);
          return null;
        }

        return UrlPreviewDurableCacheHit(
          data: UrlPreviewComponent.invalidPreviewData,
          isStale: false,
        );
      }

      if (age > maxStaleAge) {
        await _removeKey(prefs, key);
        return null;
      }

      final data = _dataFromJson(decoded, matrixClient, cachedAtMs: cachedAtMs);
      if (data == null) {
        await _removeKey(prefs, key);
        return null;
      }

      // A version 1 entry could contain only the inferred site name after a
      // provider's generic response was sanitized. That is not enough content
      // for a preview, but returning it here prevents a newly capable service
      // from being queried. Treat it as a targeted schema migration rather
      // than asking people to clear application storage.
      if (_shouldDiscardContentlessEntry(decoded, data)) {
        await _removeKey(prefs, key);
        return null;
      }

      await _touchKey(prefs, key);

      return UrlPreviewDurableCacheHit(data: data, isStale: age > validTtl);
    } catch (error) {
      Log.d(
        'Optional durable URL preview cache read failed: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview-cache',
      );
      return null;
    }
  }

  Future<void> put(Uri normalizedUri, UrlPreviewData data) async {
    if (!_isSafeToPersistUri(normalizedUri)) {
      return;
    }

    try {
      final prefs = await _prefs();
      final hash = _hashUri(normalizedUri);
      final key = _entryKey(hash);
      if (_shouldAvoidPersistingContentlessData(data)) {
        await _removeKey(prefs, key);
        return;
      }
      final nowMs = _now().millisecondsSinceEpoch;
      final encoded = jsonEncode(
        _dataToJson(
          normalizedUri: normalizedUri,
          data: data,
          cachedAtMs: nowMs,
        ),
      );

      await prefs.setString(key, encoded);
      await _touchKey(prefs, key);
      await _prune(prefs);
    } catch (error) {
      Log.d(
        'Optional durable URL preview cache write failed: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview-cache',
      );
    }
  }

  Future<void> remove(Uri normalizedUri) async {
    if (!_isSafeToPersistUri(normalizedUri)) {
      return;
    }

    try {
      final prefs = await _prefs();
      await _removeKey(prefs, _entryKey(_hashUri(normalizedUri)));
    } catch (error) {
      Log.d(
        'Optional durable URL preview cache remove failed: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview-cache',
      );
    }
  }

  Future<void> clear() async {
    try {
      final prefs = await _prefs();
      for (final key in prefs.getStringList(_indexKey) ?? const <String>[]) {
        await prefs.remove(key);
      }
      await prefs.remove(_indexKey);
    } catch (error) {
      Log.d(
        'Optional durable URL preview cache clear failed: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview-cache',
      );
    }
  }

  Future<SharedPreferences> _prefs() async {
    return _preferences ??= await SharedPreferences.getInstance();
  }

  Map<String, Object?> _dataToJson({
    required Uri normalizedUri,
    required UrlPreviewData data,
    required int cachedAtMs,
  }) {
    final invalid = data == UrlPreviewComponent.invalidPreviewData;
    if (invalid) {
      return {
        'version': _version,
        'cached_at_ms': cachedAtMs,
        'normalized_url': normalizedUri.toString(),
        'invalid': true,
      };
    }

    final safeDataUri = _isSafeToPersistUri(data.uri)
        ? data.uri
        : normalizedUri;
    final imageJson = _imageToJson(data);
    final volatileImageJson = imageJson == null
        ? _volatileImageToJson(data)
        : null;
    final volatileImageOmitted =
        data.volatileImageOmitted ||
        volatileImageJson != null ||
        _hasOmittedVolatileImage(data, imageJson);

    return {
      'version': _version,
      'cached_at_ms': cachedAtMs,
      'normalized_url': normalizedUri.toString(),
      'uri': safeDataUri.toString(),
      'site_name': _safeText(data.siteName),
      'title': _safeText(data.title),
      'description': _safeText(data.description),
      'posting_account': _safeText(data.postingAccount),
      'stats': _safeText(data.stats),
      'image': imageJson,
      'volatile_image': volatileImageJson,
      'image_width': data.imageWidth,
      'image_height': data.imageHeight,
      'volatile_image_omitted': volatileImageOmitted,
      'invalid': false,
    };
  }

  UrlPreviewData? _dataFromJson(
    Map<String, dynamic> decoded,
    matrix.Client matrixClient, {
    required int cachedAtMs,
  }) {
    final uriValue =
        _stringValue(decoded['uri']) ?? _stringValue(decoded['normalized_url']);
    if (uriValue == null) {
      return null;
    }

    final uri = Uri.tryParse(uriValue);
    if (uri == null || !_isSafeToPersistUri(uri)) {
      return null;
    }

    final imageUri =
        _imageUriFromJson(decoded['image']) ??
        _volatileImageUriFromJson(
          decoded['volatile_image'],
          cachedAtMs: cachedAtMs,
        );

    return UrlPreviewData(
      uri,
      siteName: _safeText(_stringValue(decoded['site_name'])),
      title: _safeText(_stringValue(decoded['title'])),
      description: _safeText(_stringValue(decoded['description'])),
      postingAccount: _safeText(_stringValue(decoded['posting_account'])),
      stats: _safeText(_stringValue(decoded['stats'])),
      image: _imageFromUri(imageUri, matrixClient),
      imageUri: imageUri,
      imageWidth: _intValue(decoded['image_width']),
      imageHeight: _intValue(decoded['image_height']),
      volatileImageOmitted: decoded['volatile_image_omitted'] == true,
    );
  }

  bool _hasOmittedVolatileImage(
    UrlPreviewData data,
    Map<String, String>? persistedImage,
  ) {
    if (persistedImage != null) {
      return false;
    }

    final imageUri = data.imageUri;
    if (imageUri != null && isVolatileUrlPreviewImageUri(imageUri)) {
      return true;
    }

    final image = data.image;
    if (image is NetworkImage) {
      final uri = Uri.tryParse(image.url);
      return uri != null && isVolatileUrlPreviewImageUri(uri);
    }

    return false;
  }

  bool _shouldDiscardContentlessEntry(
    Map<String, dynamic> decoded,
    UrlPreviewData data,
  ) {
    final version = _intValue(decoded['version']) ?? 1;
    if (!_shouldAvoidPersistingContentlessData(data)) {
      return false;
    }

    // Version 1 is the migration target. A current record can reach this
    // shape later only when its short-lived volatile image expires; it must
    // also miss so a fresh provider result gets a chance to replace it.
    return version < _version || data.volatileImageOmitted;
  }

  bool _shouldAvoidPersistingContentlessData(UrlPreviewData data) {
    if (data == UrlPreviewComponent.invalidPreviewData) {
      return false;
    }

    return data.image == null &&
        data.imageUri == null &&
        normalizeUrlPreviewText(data.title) == null &&
        normalizeUrlPreviewText(data.description) == null &&
        normalizeUrlPreviewText(data.postingAccount) == null &&
        normalizeUrlPreviewText(data.stats) == null;
  }

  Map<String, String>? _imageToJson(UrlPreviewData data) {
    final explicitImageUri = data.imageUri;
    if (explicitImageUri != null) {
      final encoded = _imageUriToJson(explicitImageUri);
      if (encoded != null) {
        return encoded;
      }
    }

    final image = data.image;
    if (image is NetworkImage) {
      final uri = Uri.tryParse(image.url);
      if (uri != null) {
        final encoded = _imageUriToJson(uri);
        if (encoded != null) {
          return encoded;
        }
      }
    }

    if (image is MatrixMxcImage) {
      return _imageUriToJson(image.identifier);
    }

    return null;
  }

  Map<String, String>? _volatileImageToJson(UrlPreviewData data) {
    final explicitImageUri = data.imageUri;
    if (explicitImageUri != null) {
      final encoded = _volatileImageUriToJson(explicitImageUri);
      if (encoded != null) {
        return encoded;
      }
    }

    final image = data.image;
    if (image is NetworkImage) {
      final uri = Uri.tryParse(image.url);
      if (uri != null) {
        final encoded = _volatileImageUriToJson(uri);
        if (encoded != null) {
          return encoded;
        }
      }
    }

    return null;
  }

  Map<String, String>? _imageUriToJson(Uri uri) {
    if (!_isSafeToPersistUri(uri)) {
      return null;
    }

    if (!isDurableUrlPreviewImageUri(uri)) {
      return null;
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return {'type': 'network', 'url': uri.toString()};
    }

    if (uri.scheme == 'mxc') {
      return {'type': 'mxc', 'uri': uri.toString()};
    }

    return null;
  }

  Map<String, String>? _volatileImageUriToJson(Uri uri) {
    if (!_isSafeToPersistUri(uri)) {
      return null;
    }

    if (!isVolatileUrlPreviewImageUri(uri)) {
      return null;
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return {'type': 'network', 'url': uri.toString()};
    }

    return null;
  }

  Uri? _imageUriFromJson(Object? value) {
    if (value is! Map<String, dynamic>) {
      return null;
    }

    final type = _stringValue(value['type']);
    final rawUri = _stringValue(value['url']) ?? _stringValue(value['uri']);
    if (rawUri == null) {
      return null;
    }

    final uri = Uri.tryParse(rawUri);
    if (uri == null) {
      return null;
    }

    if (type == 'network' &&
        _isSafeToPersistUri(uri) &&
        isDurableUrlPreviewImageUri(uri)) {
      return uri;
    }

    if (type == 'mxc' && uri.scheme == 'mxc') {
      return uri;
    }

    return null;
  }

  Uri? _volatileImageUriFromJson(Object? value, {required int cachedAtMs}) {
    if (volatileImageTtl.inMicroseconds <= 0) {
      return null;
    }

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
    if (_now().difference(cachedAt) > volatileImageTtl) {
      return null;
    }

    if (value is! Map<String, dynamic>) {
      return null;
    }

    final type = _stringValue(value['type']);
    final rawUri = _stringValue(value['url']);
    if (rawUri == null) {
      return null;
    }

    final uri = Uri.tryParse(rawUri);
    if (uri == null) {
      return null;
    }

    if (type == 'network' &&
        _isSafeToPersistUri(uri) &&
        isVolatileUrlPreviewImageUri(uri)) {
      return uri;
    }

    return null;
  }

  ImageProvider? _imageFromUri(Uri? uri, matrix.Client matrixClient) {
    if (uri == null) {
      return null;
    }

    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return NetworkImage(uri.toString());
    }

    if (uri.scheme == 'mxc') {
      return MatrixMxcImage(uri, matrixClient, doThumbnail: false);
    }

    return null;
  }

  Future<void> _touchKey(SharedPreferences prefs, String key) async {
    final existing = prefs.getStringList(_indexKey) ?? const <String>[];
    final updated = [
      key,
      for (final item in existing)
        if (item != key) item,
    ];
    await prefs.setStringList(_indexKey, updated);
  }

  Future<void> _removeKey(SharedPreferences prefs, String key) async {
    await prefs.remove(key);
    final existing = prefs.getStringList(_indexKey) ?? const <String>[];
    await prefs.setStringList(_indexKey, [
      for (final item in existing)
        if (item != key) item,
    ]);
  }

  Future<void> _prune(SharedPreferences prefs) async {
    final keys = prefs.getStringList(_indexKey) ?? const <String>[];
    final retained = <String>[];
    final cutoff = _now().subtract(maxStaleAge).millisecondsSinceEpoch;

    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null) {
        continue;
      }

      final cachedAtMs = _cachedAtMs(raw);
      if (cachedAtMs == null || cachedAtMs < cutoff) {
        await prefs.remove(key);
        continue;
      }

      retained.add(key);
    }

    while (retained.length > maxEntries) {
      final removed = retained.removeLast();
      await prefs.remove(removed);
    }

    await prefs.setStringList(_indexKey, retained);
  }

  int? _cachedAtMs(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return _intValue(decoded['cached_at_ms']);
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String? _safeText(String? value) {
    final normalized = normalizeUrlPreviewText(value);
    if (normalized == null) {
      return null;
    }

    final redacted = LogRedactor.redact(normalized);
    return normalizeUrlPreviewText(redacted);
  }

  String _entryKey(String hash) => '$prefix.entry.$hash';

  String get _indexKey => '$prefix.index';

  String _hashUri(Uri uri) =>
      sha256.convert(utf8.encode(uri.toString())).toString();

  bool _isSafeToPersistUri(Uri uri) {
    if (uri.userInfo.isNotEmpty) {
      return false;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'mxc') {
      return false;
    }

    for (final name in uri.queryParametersAll.keys) {
      if (_isSensitiveName(name)) {
        return false;
      }
    }

    final fragment = uri.fragment.toLowerCase();
    if (fragment.isNotEmpty &&
        _sensitiveQueryNames.any((name) => fragment.contains(name))) {
      return false;
    }

    return true;
  }

  bool _isSensitiveName(String name) {
    final normalized = name.toLowerCase().replaceAll('-', '_');
    if (_sensitiveQueryNames.contains(normalized)) {
      return true;
    }

    return normalized.contains('access_token') ||
        normalized.contains('refresh_token') ||
        normalized.contains('authorization') ||
        normalized.contains('password') ||
        normalized.contains('client_secret') ||
        normalized.contains('api_key');
  }

  String? _stringValue(Object? value) => value is String ? value : null;

  int? _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
