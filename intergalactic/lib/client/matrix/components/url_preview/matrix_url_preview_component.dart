import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/matrix_mxc_image_provider.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_durable_cache.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/client/timeline.dart';
import 'package:intergalactic/client/timeline_events/timeline_event.dart';
import 'package:intergalactic/client/timeline_events/timeline_event_message.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/mime.dart';
import 'package:intergalactic/utils/links/tracking_parameters_cleaner.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart' as matrix;
import 'package:matrix/matrix_api_lite.dart';

typedef UrlPreviewResponseFetcher = Future<Map<String, Object?>?> Function(
  matrix.Client client,
  Uri url,
);

typedef UrlPreviewDirectFetcher = Future<UrlPreviewData?> Function(Uri url);

typedef UrlPreviewUriNormalizer = Future<Uri> Function(Uri uri);

typedef UrlPreviewMatrixClientProvider = matrix.Client Function(Room room);

typedef IntergalacticPreviewResponseFetcher = Future<Map<String, Object?>?>
    Function(Uri url);

class MatrixUrlPreviewComponent implements UrlPreviewComponent<MatrixClient> {
  static const Duration _previewRequestTimeout = Duration(seconds: 6);
  static const Duration _invalidPreviewCacheTtl = Duration(minutes: 10);
  static const Duration _intergalacticPreviewRetryDelay = Duration(minutes: 30);
  static const Duration _intergalacticPreviewTransientFailureWindow =
      Duration(minutes: 2);
  static const int _intergalacticPreviewTransientFailureThreshold = 3;
  static const int _maxLongLivedCacheEntries = 1000;
  static final LinkedHashMap<String, UrlPreviewData> _longLivedCache =
      LinkedHashMap();
  static final LinkedHashMap<String, DateTime>
      _longLivedInvalidCacheTimestamps = LinkedHashMap();
  static final LinkedHashMap<String, UrlPreviewData> _longLivedEventCache =
      LinkedHashMap();
  static final LinkedHashMap<String, DateTime>
      _longLivedInvalidEventCacheTimestamps = LinkedHashMap();
  @override
  MatrixClient client;

  MatrixUrlPreviewComponent(
    this.client, {
    UrlPreviewResponseFetcher? responseFetcher,
    UrlPreviewDirectFetcher? directFetcher,
    UrlPreviewUriNormalizer? uriNormalizer,
    UrlPreviewMatrixClientProvider? matrixClientProvider,
    UrlPreviewDurableCache? durableCache,
    IntergalacticPreviewResponseFetcher? intergalacticPreviewFetcher,
    DateTime Function()? now,
  })  : _responseFetcher = responseFetcher,
        _directFetcher =
            directFetcher ?? UrlPreviewFallbackFetcher.fetchPreview,
        _uriNormalizer = uriNormalizer,
        _matrixClientProvider = matrixClientProvider,
        _durableCache = durableCache ?? UrlPreviewDurableCache(),
        _intergalacticPreviewFetcher = intergalacticPreviewFetcher,
        _now = now ?? DateTime.now;

  Map<String, UrlPreviewData> cache = {};
  final Map<String, UrlPreviewData> _eventCache = {};
  final Map<String, DateTime> _invalidCacheTimestamps = {};
  final Map<String, DateTime> _invalidEventCacheTimestamps = {};
  final Map<String, Future<UrlPreviewData?>> _inFlight = {};
  final Map<String, Future<void>> _timelineWarmups = {};
  final Map<String, int> _timelineWarmupGenerations = {};
  final UrlPreviewResponseFetcher? _responseFetcher;
  final UrlPreviewDirectFetcher _directFetcher;
  final UrlPreviewUriNormalizer? _uriNormalizer;
  final UrlPreviewMatrixClientProvider? _matrixClientProvider;
  final UrlPreviewDurableCache _durableCache;
  final IntergalacticPreviewResponseFetcher? _intergalacticPreviewFetcher;
  final DateTime Function() _now;

  bool? serverSupportsUrlPreview;
  DateTime? _intergalacticPreviewUnavailableAt;
  DateTime? _firstIntergalacticPreviewTransientFailureAt;
  int _intergalacticPreviewTransientFailures = 0;
  String? _lastIntergalacticPreviewServiceStatus;

  @override
  Future<UrlPreviewData?> getPreview(
      Timeline timeline, TimelineEvent event) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final room = timeline.room;

    if (room.isE2EE && !preferences.shouldAllowUrlPreviewInE2EEChat) {
      Log.i(
          "Not getting url preview because chat is encrypted and its not enabled");
      return null;
    }

    final mxClient = _matrixClientForRoom(room);

    final originalUri = _firstPreviewUri(timeline, event);
    if (originalUri == null) {
      return null;
    }

    var uri = await _normalizePreviewUri(originalUri);

    final cachedEventData = _getCachedPreviewForEvent(timeline, event, uri);
    if (cachedEventData != null) {
      _logCacheHit('event', uri);
      return cachedEventData;
    }

    final cachedData = _getCachedPreviewForUri(uri);
    if (cachedData != null) {
      _cachePreviewForEventAliases(
          timeline, event, originalUri, uri, cachedData);
      _logCacheHit('url', uri);
      return cachedData;
    }

    final durableHit = await _getDurableCachedPreviewForUri(
      mxClient,
      uri,
      originalUri: originalUri,
    );
    if (durableHit != null) {
      final refreshedData = await _refreshMissingDurableImage(
        uri,
        originalUri,
        durableHit.data,
      );
      if (refreshedData != null) {
        _cachePreviewForEventAliases(
          timeline,
          event,
          originalUri,
          uri,
          refreshedData,
        );
        return refreshedData;
      }

      final shouldRefreshMissingImage =
          _shouldRefreshMissingDurableImage(uri, durableHit.data);
      if (!durableHit.isStale && !shouldRefreshMissingImage) {
        _cachePreviewForEventAliases(
          timeline,
          event,
          originalUri,
          uri,
          durableHit.data,
        );
      }
      return durableHit.data;
    }

    final existingRequest = _inFlight[uri.toString()];
    if (existingRequest != null) {
      final data = await existingRequest;
      if (data != null) {
        _cachePreviewForEventAliases(timeline, event, originalUri, uri, data);
      }
      return data;
    }

    final request = _fetchAndCachePreview(mxClient, uri, originalUri);
    _inFlight[uri.toString()] = request;

    try {
      final data = await request;
      if (data != null) {
        _cachePreviewForEventAliases(timeline, event, originalUri, uri, data);
      }
      return data;
    } finally {
      _inFlight.remove(uri.toString());
    }
  }

  @override
  UrlPreviewData? getCachedPreview(Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    if (!shouldGetPreviewsInRoom(timeline.room)) {
      return null;
    }

    var uri = event.getLinks(timeline: timeline)?.firstOrNull;

    if (uri == null) {
      return null;
    }

    final cachedEventData = _getCachedPreviewForEvent(timeline, event, uri);
    if (cachedEventData != null) {
      return cachedEventData;
    }

    final cachedData = _getCachedPreviewForUri(uri);
    if (cachedData != null) {
      _cachePreviewForEvent(timeline, event, uri, cachedData);
      return cachedData;
    }

    return null;
  }

  @override
  Future<UrlPreviewData?> refreshPreviewAfterImageFailure(
    Timeline timeline,
    TimelineEvent event,
    UrlPreviewData failedData,
  ) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    if (!shouldGetPreviewsInRoom(timeline.room)) {
      return null;
    }

    final originalUri = _firstPreviewUri(timeline, event);
    if (originalUri == null) {
      return null;
    }

    final normalizedUri = await _normalizePreviewUri(originalUri);
    _removeCachedPreviewForEventAliases(
      timeline,
      event,
      originalUri,
      normalizedUri,
    );
    _removeCachedPreviewForUri(originalUri);
    _removeCachedPreviewForUri(normalizedUri);
    await _removeDurableCacheBestEffort(normalizedUri, originalUri);

    final failedImageUri =
        failedData.imageUri ?? _imageUriForProvider(failedData.image);
    Log.d(
      'URL preview image failed; refreshing cached preview '
      'host=${_safePreviewHost(normalizedUri)} '
      'image_host=${failedImageUri == null ? "unknown" : _safePreviewHost(failedImageUri)}',
      category: LogCategory.media,
      source: 'url-preview',
    );

    final data = await _startPreviewRequest(
      _matrixClientForRoom(timeline.room),
      normalizedUri,
      originalUri,
      cacheInvalid: false,
    );

    if (data != null) {
      _cachePreviewForEventAliases(
        timeline,
        event,
        originalUri,
        normalizedUri,
        data,
      );
    }

    return data;
  }

  @override
  bool shouldGetPreviewsInRoom(Room room) {
    if (!room.shouldPreviewMedia) {
      return false;
    }

    if (room.isE2EE && !preferences.shouldAllowUrlPreviewInE2EEChat) {
      return false;
    }

    if (serverSupportsUrlPreview == false) {
      return false;
    }

    return true;
  }

  @override
  bool shouldGetPreviewDataForTimelineEvent(
      Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return false;
    }

    final room = timeline.room;

    if (!shouldGetPreviewsInRoom(room)) {
      return false;
    }

    final links = event.getLinks(timeline: timeline);

    return links?.isNotEmpty == true;
  }

  Future<String> getRequestPath() async {
    if (await client.getMatrixClient().authenticatedMediaSupported()) {
      return '/client/v1/media/preview_url';
    } else {
      return '/media/v3/preview_url';
    }
  }

  @override
  Future<UrlPreviewData?> getPreviewForUrl(Room room, Uri uri) async {
    if (shouldGetPreviewsInRoom(room) == false) {
      return null;
    }

    if (uri.authority == "matrix.to") {
      return null;
    }

    final normalizedUri = await _normalizePreviewUri(uri);

    final normalizedCachedData = _getCachedPreviewForUri(normalizedUri);
    if (normalizedCachedData != null) {
      _logCacheHit('url', normalizedUri);
      return normalizedCachedData;
    }

    final originalCachedData = _getCachedPreviewForUri(uri);
    if (originalCachedData != null) {
      _logCacheHit('url', uri);
      return originalCachedData;
    }

    final durableHit = await _getDurableCachedPreviewForUri(
      _matrixClientForRoom(room),
      normalizedUri,
      originalUri: uri,
    );
    if (durableHit != null) {
      final refreshedData = await _refreshMissingDurableImage(
        normalizedUri,
        uri,
        durableHit.data,
      );
      if (refreshedData != null) {
        return refreshedData;
      }
      return durableHit.data;
    }

    final cacheKey = normalizedUri.toString();
    final existingRequest = _inFlight[cacheKey];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _fetchAndCachePreview(
      _matrixClientForRoom(room),
      normalizedUri,
      uri,
    );
    _inFlight[cacheKey] = request;

    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<UrlPreviewData?> buildPreviewData(
      matrix.Client client, Uri url) async {
    final timer = Stopwatch()..start();
    final preferDirectByProvider =
        UrlPreviewFallbackFetcher.shouldPreferDirectFetch(url);
    final serverFuture = fetchConfiguredPreviewResponse(client, url);
    final directFuture =
        preferDirectByProvider ? _fetchDirectPreview(url) : null;
    UrlPreviewData? directData;

    if (directFuture != null) {
      directData = sanitizeUrlPreviewDataForUri(url, await directFuture);
      if (urlPreviewCompletenessScore(directData) >= 4) {
        timer.stop();
        serverFuture.catchError((_) => null);
        Log.d(
          "URL preview resolved host=${_safePreviewHost(url)} "
          "direct_preferred=true direct_used=true server_used=false "
          "duration_ms=${timer.elapsedMilliseconds}",
        );
        return directData;
      }
    }

    final response = await serverFuture;
    final rawServerData = response != null
        ? buildPreviewFromResponse(client, url, response)
        : null;
    final serverData = sanitizeUrlPreviewDataForUri(url, rawServerData);

    if (preferDirectByProvider && directData == null) {
      final rawDirectData = await _fetchDirectPreview(url);
      directData = sanitizeUrlPreviewDataForUri(url, rawDirectData);
    }

    final sanitizedGenericTikTokServerData = isTikTokPreviewUri(url) &&
        _didSanitizePreview(rawServerData, serverData) &&
        directData == null;

    if (sanitizedGenericTikTokServerData) {
      Log.i(
        "URL preview sanitized generic TikTok server metadata for host "
        "${_safePreviewHost(url)} because direct metadata was unavailable.",
      );

      // On web, direct TikTok fetches are always blocked by CORS, so
      // directData will never be available. Rather than returning null and
      // showing no preview at all, fall back to a stripped version of the
      // server data: keep the site name, any thumbnail image, and the posting
      // account, but drop the generic marketing title/description.
      // Something > nothing for the user.
      if (kIsWeb && rawServerData != null) {
        final fallbackSiteName = rawServerData.siteName;
        final fallbackImage = _safeTikTokWebFallbackImage(rawServerData.image);
        final fallbackAccount = rawServerData.postingAccount;

        if (fallbackSiteName != null ||
            fallbackImage != null ||
            fallbackAccount != null) {
          return UrlPreviewData(
            rawServerData.uri,
            siteName: fallbackSiteName,
            title: null,
            description: null,
            image: fallbackImage,
            imageUri: _imageUriForProvider(fallbackImage),
            imageWidth: rawServerData.imageWidth,
            imageHeight: rawServerData.imageHeight,
            postingAccount: fallbackAccount,
            stats: null,
          );
        }
      }
    }

    final preferDirectFetch = directData != null &&
        (UrlPreviewFallbackFetcher.shouldPreferDirectFetch(url) ||
            urlPreviewCompletenessScore(directData) >
                urlPreviewCompletenessScore(serverData));

    final merged = mergeUrlPreviewData(
      serverData,
      directData,
      preferSecondary: preferDirectFetch,
    );

    timer.stop();
    Log.d(
      "URL preview resolved host=${_safePreviewHost(url)} "
      "direct_preferred=$preferDirectByProvider "
      "direct_used=${directData != null} "
      "server_used=${serverData != null} "
      "duration_ms=${timer.elapsedMilliseconds}",
    );

    return merged;
  }

  Future<Map<String, Object?>?> fetchConfiguredPreviewResponse(
    matrix.Client client,
    Uri url,
  ) async {
    final intergalacticResponse = await fetchIntergalacticPreviewResponse(url);
    if (intergalacticResponse != null) {
      return intergalacticResponse;
    }

    return fetchPreviewResponse(client, url);
  }

  Future<Map<String, Object?>?> fetchIntergalacticPreviewResponse(
    Uri url,
  ) async {
    final override = _intergalacticPreviewFetcher;
    if (override != null) {
      if (_isIntergalacticPreviewUnavailable()) {
        _logIntergalacticPreviewServiceStatus(
          'configured but temporarily unavailable',
        );
        return null;
      }

      try {
        final response = await override(url).timeout(_previewRequestTimeout);
        _resetIntergalacticPreviewTransientFailures();
        return response;
      } catch (error) {
        _recordIntergalacticPreviewTransientFailure(url, error);
        return null;
      }
    }

    final endpoint = BuildConfig.INTERGALACTIC_URL_PREVIEW_ENDPOINT.trim();
    if (endpoint.isEmpty) {
      return null;
    }

    if (_isIntergalacticPreviewUnavailable()) {
      _logIntergalacticPreviewServiceStatus(
        'configured but temporarily unavailable',
      );
      return null;
    }

    final endpointUri = Uri.tryParse(endpoint);
    if (endpointUri == null || !endpointUri.hasScheme) {
      _logIntergalacticPreviewServiceStatus(
        'configured but endpoint is invalid',
      );
      return null;
    }

    if (!_canUseConfiguredIntergalacticPreviewService()) {
      _logIntergalacticPreviewServiceStatus(
        'configured but blocked by homeserver scope',
      );
      return null;
    }

    _logIntergalacticPreviewServiceStatus(
      'configured and homeserver-scoped',
    );

    final requestUri = endpointUri.replace(queryParameters: {
      ...endpointUri.queryParameters,
      'url': url.toString(),
    });

    try {
      final response = await http.get(requestUri).timeout(
            _previewRequestTimeout,
          );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _logIntergalacticPreviewHttpStatus(url, response.statusCode);
        if (shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
          response.statusCode,
        )) {
          _markIntergalacticPreviewUnavailable();
          _logIntergalacticPreviewServiceStatus(
            'configured but temporarily unavailable',
          );
        }
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        _resetIntergalacticPreviewTransientFailures();
        return Map<String, Object?>.from(decoded);
      }

      _recordIntergalacticPreviewTransientFailure(
        url,
        const FormatException('Preview service returned a non-object body.'),
      );
    } catch (error) {
      _recordIntergalacticPreviewTransientFailure(url, error);
    }

    return null;
  }

  Future<Map<String, Object?>?> fetchPreviewResponse(
      matrix.Client client, Uri url) async {
    final override = _responseFetcher;
    if (override != null) {
      return override(client, url);
    }

    late Map<String, Object?> response;
    try {
      response = await client.request(
          matrix.RequestType.GET, await getRequestPath(),
          query: {"url": url.toString()}).timeout(_previewRequestTimeout);
    } catch (e) {
      if (e is MatrixException) {
        if (e.error == MatrixError.M_UNRECOGNIZED) {
          serverSupportsUrlPreview = false;
        }
      }

      Log.d(
        'Optional Matrix URL preview request failed for host '
        '${_safePreviewHost(url)}: ${e.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview',
      );

      return null;
    }

    serverSupportsUrlPreview = true;
    return response;
  }

  Future<UrlPreviewData?> _fetchAndCachePreview(
    matrix.Client mxClient,
    Uri normalizedUri,
    Uri originalUri, {
    bool cacheInvalid = true,
  }) async {
    UrlPreviewData? data;

    try {
      data = await buildPreviewData(mxClient, normalizedUri).timeout(
        _previewRequestTimeout + const Duration(seconds: 2),
        onTimeout: () => null,
      );
    } catch (_) {
      return null;
    }

    if (data != null) {
      _cachePreviewForUri(normalizedUri, data);
      _cachePreviewForUri(originalUri, data);
      await _putDurableCacheBestEffort(normalizedUri, originalUri, data);
    } else if (cacheInvalid) {
      _cachePreviewForUri(
          normalizedUri, UrlPreviewComponent.invalidPreviewData);
      _cachePreviewForUri(originalUri, UrlPreviewComponent.invalidPreviewData);
      await _putDurableCacheBestEffort(
        normalizedUri,
        originalUri,
        UrlPreviewComponent.invalidPreviewData,
      );
    }

    return data;
  }

  Future<void> _putDurableCacheBestEffort(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData data,
  ) async {
    try {
      await _durableCache.put(normalizedUri, data);
    } catch (error) {
      Log.d(
        'Durable URL preview cache write failed for host '
        '${_safePreviewHost(normalizedUri)} from original host '
        '${_safePreviewHost(originalUri)}: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview',
      );
    }
  }

  Future<void> _removeDurableCacheBestEffort(
    Uri normalizedUri,
    Uri originalUri,
  ) async {
    try {
      await _durableCache.remove(normalizedUri);
      if (originalUri != normalizedUri) {
        await _durableCache.remove(originalUri);
      }
    } catch (error) {
      Log.d(
        'Durable URL preview cache remove failed for host '
        '${_safePreviewHost(normalizedUri)} from original host '
        '${_safePreviewHost(originalUri)}: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview',
      );
    }
  }

  Future<UrlPreviewData?> _fetchDirectPreview(Uri url) async {
    try {
      final directPreview = _directFetcher(url).then<UrlPreviewData?>(
        (preview) => preview,
      );
      return await directPreview.timeout(
        _previewRequestTimeout,
        onTimeout: () => null,
      );
    } catch (error) {
      Log.d(
        'Optional direct URL preview fallback failed for host '
        '${_safePreviewHost(url)}: ${error.runtimeType}',
        category: LogCategory.media,
        source: 'url-preview',
      );
      return null;
    }
  }

  @override
  Future<void> warmTimelinePreviews(
    Timeline timeline, {
    int limit = 8,
    int concurrency = 2,
  }) {
    if (!shouldGetPreviewsInRoom(timeline.room)) {
      return Future.value();
    }

    final key = "${timeline.room.identifier}|${identityHashCode(timeline)}";
    final generation = (_timelineWarmupGenerations[key] ?? 0) + 1;
    _timelineWarmupGenerations[key] = generation;

    final existing = _timelineWarmups[key];
    if (existing != null) {
      return existing;
    }

    final future = _runTimelineWarmup(
      key,
      timeline,
      limit: limit,
      concurrency: concurrency,
      generation: generation,
    );
    _timelineWarmups[key] = future;
    return future;
  }

  Future<void> _runTimelineWarmup(
    String key,
    Timeline timeline, {
    required int limit,
    required int concurrency,
    required int generation,
  }) {
    return _warmTimelinePreviews(
      timeline,
      limit: limit,
      concurrency: concurrency,
    ).whenComplete(() {
      final latestGeneration = _timelineWarmupGenerations[key];
      if (latestGeneration != null && latestGeneration != generation) {
        _timelineWarmups[key] = _runTimelineWarmup(
          key,
          timeline,
          limit: limit,
          concurrency: concurrency,
          generation: latestGeneration,
        );
        return;
      }

      _timelineWarmups.remove(key);
      _timelineWarmupGenerations.remove(key);
    });
  }

  Future<void> _warmTimelinePreviews(
    Timeline timeline, {
    required int limit,
    required int concurrency,
  }) async {
    final safeLimit = limit.clamp(0, 50).toInt();
    final safeConcurrency = concurrency.clamp(1, 6).toInt();
    final events = List<TimelineEvent>.of(timeline.events, growable: false);
    if (safeLimit == 0 || events.isEmpty) {
      return;
    }

    final candidates = <_UrlPreviewWarmupCandidate>[];
    final seenUrls = <String>{};

    for (final event in events) {
      if (candidates.length >= safeLimit) {
        break;
      }

      if (event.status != TimelineEventStatus.synced ||
          !shouldGetPreviewDataForTimelineEvent(timeline, event)) {
        continue;
      }

      final uri = _firstPreviewUri(timeline, event);
      if (uri == null) {
        continue;
      }

      final normalizedUri = await _normalizePreviewUri(uri);
      if (_getCachedPreviewForEvent(timeline, event, normalizedUri) != null) {
        continue;
      }

      final cacheKey = normalizedUri.toString();
      if (!seenUrls.add(cacheKey)) {
        continue;
      }

      final cachedData = _getCachedPreviewForUri(normalizedUri);
      if (cachedData != null) {
        _cachePreviewForEventAliases(
          timeline,
          event,
          uri,
          normalizedUri,
          cachedData,
        );
        continue;
      }

      final durableHit = await _getDurableCachedPreviewForUri(
        _matrixClientForRoom(timeline.room),
        normalizedUri,
        originalUri: uri,
      );
      if (durableHit != null) {
        if (_shouldRefreshMissingDurableImage(
          normalizedUri,
          durableHit.data,
        )) {
          candidates.add(_UrlPreviewWarmupCandidate(
            event: event,
            originalUri: uri,
            normalizedUri: normalizedUri,
          ));
          continue;
        }

        if (!durableHit.isStale) {
          _cachePreviewForEventAliases(
            timeline,
            event,
            uri,
            normalizedUri,
            durableHit.data,
          );
        }
        continue;
      }

      candidates.add(_UrlPreviewWarmupCandidate(
        event: event,
        originalUri: uri,
        normalizedUri: normalizedUri,
      ));
    }

    if (candidates.isEmpty) {
      return;
    }

    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < candidates.length) {
        final candidate = candidates[nextIndex++];
        await _fetchPreviewForWarmup(timeline, candidate);
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(safeConcurrency, candidates.length); i++)
        worker(),
    ]);
  }

  Future<void> _fetchPreviewForWarmup(
    Timeline timeline,
    _UrlPreviewWarmupCandidate candidate,
  ) async {
    final uri = candidate.normalizedUri;
    final existingRequest = _inFlight[uri.toString()];
    final data = existingRequest != null
        ? await existingRequest
        : await _startPreviewRequest(
            _matrixClientForRoom(timeline.room),
            uri,
            candidate.originalUri,
          );

    if (data != null) {
      _cachePreviewForEventAliases(
        timeline,
        candidate.event,
        candidate.originalUri,
        candidate.normalizedUri,
        data,
      );
    }
  }

  Future<UrlPreviewData?> _startPreviewRequest(
    matrix.Client mxClient,
    Uri normalizedUri,
    Uri originalUri, {
    bool cacheInvalid = true,
  }) async {
    final cacheKey = normalizedUri.toString();
    final existingRequest = _inFlight[cacheKey];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _fetchAndCachePreview(
      mxClient,
      normalizedUri,
      originalUri,
      cacheInvalid: cacheInvalid,
    );
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<UrlPreviewDurableCacheHit?> _getDurableCachedPreviewForUri(
    matrix.Client mxClient,
    Uri normalizedUri, {
    required Uri originalUri,
  }) async {
    final hit = await _durableCache.get(normalizedUri, mxClient);
    if (hit == null) {
      return null;
    }

    final shouldRefreshMissingImage =
        _shouldRefreshMissingDurableImage(normalizedUri, hit.data);
    if ((!hit.isStale || hit.data == UrlPreviewComponent.invalidPreviewData) &&
        !shouldRefreshMissingImage) {
      _cachePreviewForUri(normalizedUri, hit.data);
      _cachePreviewForUri(originalUri, hit.data);
    }
    _logCacheHit(
      shouldRefreshMissingImage
          ? 'durable-missing-image'
          : hit.isStale
              ? 'durable-stale'
              : 'durable',
      normalizedUri,
    );

    if (hit.isStale && hit.data != UrlPreviewComponent.invalidPreviewData) {
      _refreshStaleDurablePreview(mxClient, normalizedUri, originalUri);
    }

    return hit;
  }

  Future<UrlPreviewData?> _refreshMissingDurableImage(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData cachedData,
  ) async {
    if (!_shouldRefreshMissingDurableImage(normalizedUri, cachedData)) {
      return null;
    }

    Log.d(
      'URL preview durable cache is missing a volatile social thumbnail; '
      'refreshing host=${_safePreviewHost(normalizedUri)}',
      category: LogCategory.media,
      source: 'url-preview',
    );

    return _startDirectImageRefreshRequest(
      normalizedUri,
      originalUri,
      cachedData,
    );
  }

  Future<UrlPreviewData?> _startDirectImageRefreshRequest(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData cachedData,
  ) async {
    final cacheKey = normalizedUri.toString();
    final existingRequest = _inFlight[cacheKey];
    if (existingRequest != null) {
      return existingRequest;
    }

    final request = _fetchAndCacheDirectImageRefresh(
      normalizedUri,
      originalUri,
      cachedData,
    );
    _inFlight[cacheKey] = request;
    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  Future<UrlPreviewData?> _fetchAndCacheDirectImageRefresh(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData cachedData,
  ) async {
    final directData = sanitizeUrlPreviewDataForUri(
      normalizedUri,
      await _fetchDirectPreview(normalizedUri),
    );
    if (directData == null) {
      return null;
    }

    final refreshedData = mergeUrlPreviewData(
      cachedData,
      directData,
      preferSecondary: true,
    );
    if (refreshedData == null ||
        refreshedData.image == null && refreshedData.imageUri == null) {
      return null;
    }

    final cacheData = refreshedData.copyWith(volatileImageOmitted: false);
    _cachePreviewForUri(normalizedUri, cacheData);
    _cachePreviewForUri(originalUri, cacheData);
    await _putDurableCacheBestEffort(
      normalizedUri,
      originalUri,
      cacheData,
    );
    return cacheData;
  }

  bool _shouldRefreshMissingDurableImage(Uri uri, UrlPreviewData data) {
    return data != UrlPreviewComponent.invalidPreviewData &&
        data.image == null &&
        data.imageUri == null &&
        data.volatileImageOmitted &&
        UrlPreviewFallbackFetcher.shouldPreferDirectFetch(uri);
  }

  void _refreshStaleDurablePreview(
    matrix.Client mxClient,
    Uri normalizedUri,
    Uri originalUri,
  ) {
    if (_inFlight.containsKey(normalizedUri.toString())) {
      return;
    }

    unawaited(_startPreviewRequest(mxClient, normalizedUri, originalUri));
  }

  UrlPreviewData? _getCachedPreviewForUri(Uri uri) {
    final localCacheKey = uri.toString();
    final localCacheData = cache[localCacheKey];
    if (localCacheData != null) {
      if (_isExpiredInvalidPreview(
          localCacheData, _invalidCacheTimestamps[localCacheKey])) {
        cache.remove(localCacheKey);
        _invalidCacheTimestamps.remove(localCacheKey);
      } else {
        return localCacheData;
      }
    }

    final longLivedCacheKey = _longLivedCacheKey(uri);
    final longLivedCacheData = _longLivedCache.remove(longLivedCacheKey);
    final invalidTimestamp =
        _longLivedInvalidCacheTimestamps.remove(longLivedCacheKey);
    if (longLivedCacheData == null) {
      return null;
    }

    if (_isExpiredInvalidPreview(longLivedCacheData, invalidTimestamp)) {
      return null;
    }

    _longLivedCache[longLivedCacheKey] = longLivedCacheData;
    if (invalidTimestamp != null) {
      _longLivedInvalidCacheTimestamps[longLivedCacheKey] = invalidTimestamp;
    }

    return longLivedCacheData;
  }

  void _removeCachedPreviewForUri(Uri uri) {
    cache.remove(uri.toString());

    final longLivedCacheKey = _longLivedCacheKey(uri);
    _longLivedCache.remove(longLivedCacheKey);
    _longLivedInvalidCacheTimestamps.remove(longLivedCacheKey);
    _invalidCacheTimestamps.remove(uri.toString());
  }

  bool _isExpiredInvalidPreview(UrlPreviewData data, DateTime? addedAt) {
    if (data != UrlPreviewComponent.invalidPreviewData) {
      return false;
    }

    if (addedAt == null) {
      return true;
    }

    return _now().difference(addedAt) > _invalidPreviewCacheTtl;
  }

  void _cachePreviewForUri(Uri uri, UrlPreviewData data) {
    final localCacheKey = uri.toString();
    cache[localCacheKey] = data;
    final cacheKey = _longLivedCacheKey(uri);
    _longLivedCache.remove(cacheKey);
    _longLivedInvalidCacheTimestamps.remove(cacheKey);
    _longLivedCache[cacheKey] = data;

    if (data == UrlPreviewComponent.invalidPreviewData) {
      final now = _now();
      _invalidCacheTimestamps[localCacheKey] = now;
      _longLivedInvalidCacheTimestamps[cacheKey] = now;
    } else {
      _invalidCacheTimestamps.remove(localCacheKey);
    }

    while (_longLivedCache.length > _maxLongLivedCacheEntries) {
      final oldestKey = _longLivedCache.keys.first;
      _longLivedCache.remove(oldestKey);
      _longLivedInvalidCacheTimestamps.remove(oldestKey);
    }
  }

  UrlPreviewData? _getCachedPreviewForEvent(
    Timeline timeline,
    TimelineEvent event,
    Uri uri,
  ) {
    final localCacheKey = _eventCacheKey(timeline, event, uri);
    final localCacheData = _eventCache[localCacheKey];
    if (localCacheData != null) {
      if (_isExpiredInvalidPreview(
          localCacheData, _invalidEventCacheTimestamps[localCacheKey])) {
        _eventCache.remove(localCacheKey);
        _invalidEventCacheTimestamps.remove(localCacheKey);
      } else {
        return localCacheData;
      }
    }

    final longLivedCacheKey = _eventCacheKey(timeline, event, uri);
    final longLivedCacheData = _longLivedEventCache.remove(longLivedCacheKey);
    final invalidTimestamp =
        _longLivedInvalidEventCacheTimestamps.remove(longLivedCacheKey);
    if (longLivedCacheData == null) {
      return null;
    }

    if (_isExpiredInvalidPreview(longLivedCacheData, invalidTimestamp)) {
      return null;
    }

    _longLivedEventCache[longLivedCacheKey] = longLivedCacheData;
    if (invalidTimestamp != null) {
      _longLivedInvalidEventCacheTimestamps[longLivedCacheKey] =
          invalidTimestamp;
    }

    return longLivedCacheData;
  }

  void _cachePreviewForEventAliases(
    Timeline timeline,
    TimelineEvent event,
    Uri originalUri,
    Uri normalizedUri,
    UrlPreviewData data,
  ) {
    _cachePreviewForEvent(timeline, event, normalizedUri, data);
    if (originalUri != normalizedUri) {
      _cachePreviewForEvent(timeline, event, originalUri, data);
    }
  }

  void _removeCachedPreviewForEventAliases(
    Timeline timeline,
    TimelineEvent event,
    Uri originalUri,
    Uri normalizedUri,
  ) {
    _removeCachedPreviewForEvent(timeline, event, normalizedUri);
    if (originalUri != normalizedUri) {
      _removeCachedPreviewForEvent(timeline, event, originalUri);
    }
  }

  void _removeCachedPreviewForEvent(
    Timeline timeline,
    TimelineEvent event,
    Uri uri,
  ) {
    final cacheKey = _eventCacheKey(timeline, event, uri);
    _eventCache.remove(cacheKey);
    _invalidEventCacheTimestamps.remove(cacheKey);
    _longLivedEventCache.remove(cacheKey);
    _longLivedInvalidEventCacheTimestamps.remove(cacheKey);
  }

  void _cachePreviewForEvent(
    Timeline timeline,
    TimelineEvent event,
    Uri uri,
    UrlPreviewData data,
  ) {
    final localCacheKey = _eventCacheKey(timeline, event, uri);
    _eventCache[localCacheKey] = data;
    _longLivedEventCache.remove(localCacheKey);
    _longLivedInvalidEventCacheTimestamps.remove(localCacheKey);
    _longLivedEventCache[localCacheKey] = data;

    if (data == UrlPreviewComponent.invalidPreviewData) {
      final now = _now();
      _invalidEventCacheTimestamps[localCacheKey] = now;
      _longLivedInvalidEventCacheTimestamps[localCacheKey] = now;
    } else {
      _invalidEventCacheTimestamps.remove(localCacheKey);
    }

    while (_longLivedEventCache.length > _maxLongLivedCacheEntries) {
      final oldestKey = _longLivedEventCache.keys.first;
      _eventCache.remove(oldestKey);
      _invalidEventCacheTimestamps.remove(oldestKey);
      _longLivedEventCache.remove(oldestKey);
      _longLivedInvalidEventCacheTimestamps.remove(oldestKey);
    }
  }

  String _longLivedCacheKey(Uri uri) => "${client.identifier}|$uri";

  String _eventCacheKey(Timeline timeline, TimelineEvent event, Uri uri) {
    return "${client.identifier}|${timeline.room.identifier}|"
        "${event.eventId}|${uri.toString()}";
  }

  Uri? _firstPreviewUri(Timeline timeline, TimelineEvent event) {
    if (event is! TimelineEventMessage) {
      return null;
    }

    return event.getLinks(timeline: timeline)?.firstOrNull;
  }

  void _logCacheHit(String source, Uri uri) {
    Log.d("URL preview cache hit source=$source host=${_safePreviewHost(uri)}");
  }

  void _logIntergalacticPreviewServiceStatus(String status) {
    if (_lastIntergalacticPreviewServiceStatus == status) {
      return;
    }

    _lastIntergalacticPreviewServiceStatus = status;
    Log.i(
      'Optional Inter Galactic URL preview service: $status',
      category: LogCategory.media,
      source: 'url-preview',
    );
  }

  void _logIntergalacticPreviewHttpStatus(Uri url, int statusCode) {
    Log.d(
      'Optional Inter Galactic URL preview service returned HTTP $statusCode '
      'for host ${_safePreviewHost(url)}',
      category: LogCategory.media,
      source: 'url-preview',
    );
  }

  void _recordIntergalacticPreviewTransientFailure(Uri url, Object error) {
    final now = _now();
    final firstFailureAt = _firstIntergalacticPreviewTransientFailureAt;
    if (firstFailureAt == null ||
        now.difference(firstFailureAt) >
            _intergalacticPreviewTransientFailureWindow) {
      _firstIntergalacticPreviewTransientFailureAt = now;
      _intergalacticPreviewTransientFailures = 1;
    } else {
      _intergalacticPreviewTransientFailures += 1;
    }

    Log.d(
      'Optional Inter Galactic URL preview service transient failure for host '
      '${_safePreviewHost(url)}: ${error.runtimeType} '
      '($_intergalacticPreviewTransientFailures/'
      '$_intergalacticPreviewTransientFailureThreshold)',
      category: LogCategory.media,
      source: 'url-preview',
    );

    if (_intergalacticPreviewTransientFailures >=
        _intergalacticPreviewTransientFailureThreshold) {
      _markIntergalacticPreviewUnavailable();
      _logIntergalacticPreviewServiceStatus(
        'configured but temporarily unavailable',
      );
    }
  }

  void _markIntergalacticPreviewUnavailable() {
    _intergalacticPreviewUnavailableAt = _now();
    _resetIntergalacticPreviewTransientFailures();
  }

  void _resetIntergalacticPreviewTransientFailures() {
    _firstIntergalacticPreviewTransientFailureAt = null;
    _intergalacticPreviewTransientFailures = 0;
  }

  bool _isIntergalacticPreviewUnavailable() {
    final unavailableAt = _intergalacticPreviewUnavailableAt;
    if (unavailableAt == null) {
      return false;
    }

    if (_now().difference(unavailableAt) > _intergalacticPreviewRetryDelay) {
      _intergalacticPreviewUnavailableAt = null;
      return false;
    }

    return true;
  }

  @visibleForTesting
  bool get isIntergalacticPreviewTemporarilyUnavailableForTesting =>
      _isIntergalacticPreviewUnavailable();

  @visibleForTesting
  static bool shouldTemporarilyDisableIntergalacticPreviewServiceForStatus(
    int statusCode,
  ) {
    return statusCode == 404 ||
        statusCode == 429 ||
        statusCode == 501 ||
        statusCode >= 500;
  }

  bool _canUseConfiguredIntergalacticPreviewService() {
    final matrixClient = client.getMatrixClient();
    return canUseIntergalacticPreviewServiceForIdentity(
      homeserver: matrixClient.homeserver,
      baseUri: matrixClient.baseUri,
      userId: matrixClient.userID,
    );
  }

  @visibleForTesting
  static bool canUseIntergalacticPreviewServiceForIdentity({
    Uri? homeserver,
    Uri? baseUri,
    String? userId,
    String allowedHomeservers =
        BuildConfig.INTERGALACTIC_URL_PREVIEW_ALLOWED_HOMESERVERS,
  }) {
    final allowedHosts = _allowedIntergalacticPreviewHosts(allowedHomeservers);
    if (allowedHosts.isEmpty) {
      return false;
    }

    return _isAllowedIntergalacticPreviewHost(homeserver?.host, allowedHosts) ||
        _isAllowedIntergalacticPreviewHost(baseUri?.host, allowedHosts) ||
        _isAllowedIntergalacticPreviewUserId(userId, allowedHosts);
  }

  static Set<String> _allowedIntergalacticPreviewHosts(
    String allowedHomeservers,
  ) {
    return allowedHomeservers
        .split(',')
        .map((host) => host.trim().toLowerCase())
        .where((host) => host.isNotEmpty)
        .toSet();
  }

  static bool _isAllowedIntergalacticPreviewHost(
    String? host,
    Set<String> allowedHosts,
  ) {
    if (host == null || host.isEmpty) {
      return false;
    }

    return allowedHosts.contains(host.toLowerCase());
  }

  static bool _isAllowedIntergalacticPreviewUserId(
    String? userId,
    Set<String> allowedHosts,
  ) {
    if (userId == null || userId.isEmpty) {
      return false;
    }

    final separatorIndex = userId.indexOf(':');
    if (separatorIndex == -1 || separatorIndex == userId.length - 1) {
      return false;
    }

    final serverName = userId.substring(separatorIndex + 1).toLowerCase();
    final parsed = Uri.tryParse('https://$serverName');
    final host = parsed?.host.toLowerCase();
    return _isAllowedIntergalacticPreviewHost(host, allowedHosts) ||
        allowedHosts.contains(serverName);
  }

  String _safePreviewHost(Uri uri) {
    final host = uri.host;
    return host.isEmpty ? "unknown" : host.toLowerCase();
  }

  matrix.Client _matrixClientForRoom(Room room) {
    final override = _matrixClientProvider;
    if (override != null) {
      return override(room);
    }

    return (room as MatrixRoom).matrixRoom.client;
  }

  bool _didSanitizePreview(
      UrlPreviewData? original, UrlPreviewData? sanitized) {
    if (identical(original, sanitized)) {
      return false;
    }

    return original?.title != sanitized?.title ||
        original?.description != sanitized?.description;
  }

  ImageProvider? _safeTikTokWebFallbackImage(ImageProvider? image) {
    if (image is MatrixMxcImage) {
      return image;
    }

    if (image is NetworkImage) {
      final uri = Uri.tryParse(image.url);
      final host = uri?.host.toLowerCase();

      if (host == null || host.isEmpty) {
        return null;
      }

      // TikTok often serves non-image anti-bot / error payloads from direct
      // CDN URLs in the browser, which then explode as ImageCodecException.
      // Keep only safer non-TikTok fallback images here.
      if (host.contains('tiktok') ||
          host.contains('tiktokcdn') ||
          host.contains('byteoversea') ||
          host.contains('ibyteimg') ||
          host.contains('ibytedtos')) {
        return null;
      }

      return image;
    }

    return null;
  }

  UrlPreviewData? buildPreviewFromResponse(
    matrix.Client client,
    Uri url,
    Map<String, Object?> response,
  ) {
    var title = _firstString(response, [
      'og:title',
      'twitter:title',
      'title',
    ]);
    var siteName = _firstString(response, [
          'og:site_name',
          'twitter:site',
          'site_name',
          'siteName',
        ]) ??
        inferUrlPreviewSource(url);
    var imageUrl = _firstString(response, [
      'og:image:secure_url',
      'og:image:url',
      'og:image',
      'twitter:image',
      'twitter:image:src',
      'image_url',
      'imageUrl',
      'image',
    ]);
    var description = trimUrlPreviewDescription(_firstString(response, [
      'og:description',
      'twitter:description',
      'description',
    ]));

    var type = _firstString(response, ["og:image:type", "twitter:image:type"]);
    if (type != null) {
      if (Mime.displayableImageTypes.contains(type) == false) {
        imageUrl = null;
      }
    }

    ImageProvider? image;
    Uri? imageUri;
    var volatileImageOmitted = false;
    if (imageUrl != null) {
      final parsedImageUri = Uri.parse(imageUrl);
      if (parsedImageUri.scheme == "mxc") {
        try {
          image = MatrixMxcImage(parsedImageUri, client, doThumbnail: false);
          imageUri = parsedImageUri;
        } catch (exception, stack) {
          Log.onError(exception, stack);
          Log.w("Failed to get mxc image");
        }
      } else if (parsedImageUri.scheme == "http" ||
          parsedImageUri.scheme == "https") {
        if (isVolatileUrlPreviewImageUri(parsedImageUri)) {
          Log.d(
            'URL preview dropped volatile network image from server response '
            'host=${_safePreviewHost(url)} '
            'image_host=${_safePreviewHost(parsedImageUri)}',
            category: LogCategory.media,
            source: 'url-preview',
          );
          volatileImageOmitted = true;
        } else {
          image = NetworkImage(parsedImageUri.toString());
          imageUri = parsedImageUri;
        }
      }
    }

    final postingAccount = normalizeUrlPreviewPostingAccount(_firstString(
      response,
      [
        'author_name',
        'author',
        'article:author',
        'profile:username',
        'twitter:creator',
        'posting_account',
        'postingAccount',
      ],
    ));

    final publishedAt = _parsePublishedDate(
      _firstString(response, [
        'article:published_time',
        'og:updated_time',
        'published_time',
        'published_at',
        'publishedAt',
      ]),
    );

    final stats = _firstString(response, [
          'stats',
          'stats_line',
          'statsLine',
        ]) ??
        buildUrlPreviewStatsLine(
          likes: _parseIntValue(_firstValue(response, [
            'likes',
            'like_count',
            'og:likes',
            'likeCount',
          ])),
          comments: _parseIntValue(_firstValue(response, [
            'comments',
            'comment_count',
            'og:comments',
            'commentCount',
          ])),
          publishedAt: publishedAt,
        );

    final imageWidth = _parseIntValue(_firstValue(response, [
      'og:image:width',
      'twitter:image:width',
      'image:width',
      'image_width',
      'imageWidth',
    ]));
    final imageHeight = _parseIntValue(_firstValue(response, [
      'og:image:height',
      'twitter:image:height',
      'image:height',
      'image_height',
      'imageHeight',
    ]));

    if (title == null && description == null && image == null) {
      return null;
    }

    final previewUrl = _previewUriFromResponse(response, url);

    return UrlPreviewData(previewUrl,
        siteName: siteName,
        title: title,
        image: image,
        imageUri: imageUri,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        description: description,
        postingAccount: postingAccount,
        stats: stats,
        volatileImageOmitted: volatileImageOmitted);
  }

  Future<Uri> _normalizePreviewUri(Uri uri) async {
    final override = _uriNormalizer;
    if (override != null) {
      return override(uri);
    }

    try {
      return await UrlTrackingParametersCleaner.cleanTrackingParameters(uri);
    } catch (_) {
      return uri;
    }
  }

  String? _firstString(Map<String, Object?> response, List<String> keys) {
    for (final key in keys) {
      final value = response[key];
      if (value is String) {
        final normalized = normalizeUrlPreviewText(value);
        if (normalized != null) {
          return normalized;
        }
      }
    }

    return null;
  }

  Uri? _imageUriForProvider(ImageProvider? image) {
    if (image is MatrixMxcImage) {
      return image.identifier;
    }

    if (image is NetworkImage) {
      return Uri.tryParse(image.url);
    }

    return null;
  }

  Object? _firstValue(Map<String, Object?> response, List<String> keys) {
    for (final key in keys) {
      final value = response[key];
      if (value != null) {
        return value;
      }
    }

    return null;
  }

  Uri _previewUriFromResponse(Map<String, Object?> response, Uri fallback) {
    final value = _firstString(response, [
      'url',
      'uri',
      'canonical_url',
      'canonicalUrl',
      'og:url',
    ]);
    if (value == null) {
      return fallback;
    }

    final candidate = Uri.tryParse(value);
    if (candidate == null || !_isSafeCanonicalPreviewUri(candidate, fallback)) {
      return fallback;
    }

    return candidate;
  }

  bool _isSafeCanonicalPreviewUri(Uri candidate, Uri original) {
    if (candidate.scheme != 'http' && candidate.scheme != 'https') {
      return false;
    }
    if (original.scheme != 'http' && original.scheme != 'https') {
      return false;
    }
    if (candidate.scheme != original.scheme) {
      return false;
    }

    return _normalizedHost(candidate.host) == _normalizedHost(original.host) &&
        _effectivePort(candidate) == _effectivePort(original);
  }

  String _normalizedHost(String host) {
    return host
        .toLowerCase()
        .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '');
  }

  int _effectivePort(Uri uri) {
    if (uri.port != 0) {
      return uri.port;
    }

    return switch (uri.scheme) {
      'http' => 80,
      'https' => 443,
      _ => 0,
    };
  }

  int? _parseIntValue(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.round();
    }

    if (value is String) {
      return int.tryParse(value.replaceAll(RegExp(r"[^0-9]"), ""));
    }

    return null;
  }

  DateTime? _parsePublishedDate(String? value) {
    if (value == null) {
      return null;
    }

    final epoch = int.tryParse(value);
    if (epoch != null) {
      return DateTime.fromMillisecondsSinceEpoch(
        value.length >= 13 ? epoch : epoch * 1000,
      );
    }

    return DateTime.tryParse(value);
  }
}

class _UrlPreviewWarmupCandidate {
  const _UrlPreviewWarmupCandidate({
    required this.event,
    required this.originalUri,
    required this.normalizedUri,
  });

  final TimelineEvent event;
  final Uri originalUri;
  final Uri normalizedUri;
}
