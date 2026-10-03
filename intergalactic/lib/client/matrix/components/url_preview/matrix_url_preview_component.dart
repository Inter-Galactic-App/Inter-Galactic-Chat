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

typedef UrlPreviewResponseFetcher =
    Future<Map<String, Object?>?> Function(matrix.Client client, Uri url);

typedef UrlPreviewDirectFetcher = Future<UrlPreviewData?> Function(Uri url);

typedef UrlPreviewUriNormalizer = Future<Uri> Function(Uri uri);

typedef UrlPreviewMatrixClientProvider = matrix.Client Function(Room room);

typedef IntergalacticPreviewResponseFetcher =
    Future<Map<String, Object?>?> Function(Uri url);

/// Which backend actually answered a preview request.
///
/// `server_used` in the resolved log line only says that SOME server
/// answered. [fetchConfiguredPreviewResponse] falls back from the Inter
/// Galactic service to the homeserver's native preview SILENTLY, on every
/// failure mode - non-2xx, a non-object body, a thrown exception, DNS - so a
/// capture taken to measure the service can be measuring Synapse instead.
/// That happened to the 2026-09-11 capture: at least 21 of its responses were
/// Synapse's, and the service's own coverage for those hosts was never
/// measured.
enum UrlPreviewBackend {
  /// The configured Inter Galactic URL preview service answered.
  intergalactic,

  /// The homeserver's native `preview_url` answered.
  synapse,

  /// Neither answered: both returned null, or the homeserver does not
  /// support previews and the service did not answer.
  none,
}

class MatrixUrlPreviewComponent implements UrlPreviewComponent<MatrixClient> {
  static const Duration _previewRequestTimeout = Duration(seconds: 6);

  /// What is left of the caller's budget once the preview fetch has had its
  /// own [_previewRequestTimeout]. `_fetchAndCachePreview` allows
  /// `_previewRequestTimeout + 2s` for the whole build, so the site icon -
  /// which is optional decoration - gets the remainder and never borrows from
  /// the deadline that decides whether the preview itself survives.
  static const Duration _siteIconBudget = Duration(seconds: 2);

  /// Headroom the whole build gets ON TOP of both inner budgets.
  ///
  /// This exists because the two budgets used to sum to exactly the outer
  /// deadline: the fetch could take all of [_previewRequestTimeout] and the
  /// icon all of [_siteIconBudget], so any scheduling or parsing overhead
  /// made the outer timeout fire first. `_fetchAndCachePreview` answers that
  /// timeout by caching the URL as `invalidPreviewData`, which
  /// [_invalidPreviewCacheTtl] then suppresses any retry of for ten minutes -
  /// so a slow favicon destroyed a preview that had ALREADY resolved, the
  /// exact failure [_siteIconBudget]'s comment says the split avoids.
  ///
  /// Derive the deadline from the budgets rather than writing a third number,
  /// so raising either one cannot silently reintroduce the overlap.
  static const Duration _previewBuildSlack = Duration(milliseconds: 500);

  /// The whole-build deadline: both inner budgets in full, plus headroom.
  ///
  /// `static final`, not `const`: `Duration + Duration` is not a constant
  /// expression, and `dart analyze` accepts it while the compiler rejects it.
  static final Duration _previewBuildDeadline =
      _previewRequestTimeout + _siteIconBudget + _previewBuildSlack;

  static const Duration _invalidPreviewCacheTtl = Duration(minutes: 10);
  static const Duration _missingImageRefreshRetryDelay = Duration(minutes: 5);
  static const Duration _intergalacticPreviewRetryDelay = Duration(minutes: 30);
  static const Duration _intergalacticPreviewTransientFailureWindow = Duration(
    minutes: 2,
  );
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
    Future<UrlPreviewSiteIcon?> Function(Uri uri)? siteIconFetcher,
    UrlPreviewUriNormalizer? uriNormalizer,
    UrlPreviewMatrixClientProvider? matrixClientProvider,
    UrlPreviewDurableCache? durableCache,
    IntergalacticPreviewResponseFetcher? intergalacticPreviewFetcher,
    DateTime Function()? now,
    Duration? previewBuildDeadline,
  }) : _responseFetcher = responseFetcher,
       _directFetcher = directFetcher ?? UrlPreviewFallbackFetcher.fetchPreview,
       _siteIconFetcher =
           siteIconFetcher ?? UrlPreviewFallbackFetcher.fetchSiteIcon,
       _uriNormalizer = uriNormalizer,
       _matrixClientProvider = matrixClientProvider,
       _durableCache = durableCache ?? UrlPreviewDurableCache(),
       _intergalacticPreviewFetcher = intergalacticPreviewFetcher,
       _now = now ?? DateTime.now,
       _buildDeadline = previewBuildDeadline ?? _previewBuildDeadline;

  Map<String, UrlPreviewData> cache = {};
  final Map<String, UrlPreviewData> _eventCache = {};
  final Map<String, DateTime> _invalidCacheTimestamps = {};
  final Map<String, DateTime> _invalidEventCacheTimestamps = {};
  final Map<String, DateTime> _missingImageRefreshFailureTimestamps = {};
  final Map<String, Future<UrlPreviewData?>> _inFlight = {};
  final Map<String, Future<void>> _timelineWarmups = {};
  final Map<String, int> _timelineWarmupGenerations = {};
  final UrlPreviewResponseFetcher? _responseFetcher;
  final UrlPreviewDirectFetcher _directFetcher;
  final Future<UrlPreviewSiteIcon?> Function(Uri uri) _siteIconFetcher;
  final UrlPreviewUriNormalizer? _uriNormalizer;
  final UrlPreviewMatrixClientProvider? _matrixClientProvider;
  final UrlPreviewDurableCache _durableCache;
  final IntergalacticPreviewResponseFetcher? _intergalacticPreviewFetcher;
  final DateTime Function() _now;
  final Duration _buildDeadline;

  bool? serverSupportsUrlPreview;
  DateTime? _intergalacticPreviewUnavailableAt;
  DateTime? _firstIntergalacticPreviewTransientFailureAt;
  int _intergalacticPreviewTransientFailures = 0;
  String? _lastIntergalacticPreviewServiceStatus;

  @override
  Future<UrlPreviewData?> getPreview(
    Timeline timeline,
    TimelineEvent event,
  ) async {
    if (event is! TimelineEventMessage) {
      return null;
    }

    final room = timeline.room;

    if (room.isE2EE && !preferences.shouldAllowUrlPreviewInE2EEChat) {
      Log.i(
        "Not getting url preview because chat is encrypted and its not enabled",
      );
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
        timeline,
        event,
        originalUri,
        uri,
        cachedData,
      );
      _logCacheHit('url', uri);
      return cachedData;
    }

    final durableHit = await _getDurableCachedPreviewForUri(
      mxClient,
      uri,
      originalUri: originalUri,
      roomIsE2EE: room.isE2EE,
    );
    if (durableHit != null) {
      final refreshedData = await _refreshMissingDurableImage(
        uri,
        originalUri,
        durableHit.data,
        roomIsE2EE: room.isE2EE,
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

      final shouldRefreshMissingImage = _shouldRefreshMissingDurableImage(
        uri,
        durableHit.data,
      );
      final fallbackData = _withoutVisiblyEmptyDurableData(durableHit.data);
      if (!durableHit.isStale && !shouldRefreshMissingImage) {
        _cachePreviewForEventAliases(
          timeline,
          event,
          originalUri,
          uri,
          fallbackData,
        );
      }
      return fallbackData;
    }

    if (!_canFetchPreviewForUri(uri)) {
      return null;
    }

    final existingRequest = _inFlight[uri.toString()];
    if (existingRequest != null) {
      final data = await existingRequest;
      if (data != null) {
        _cachePreviewForEventAliases(timeline, event, originalUri, uri, data);
      }
      return data;
    }

    final request = _fetchAndCachePreview(
      mxClient,
      uri,
      originalUri,
      roomIsE2EE: room.isE2EE,
    );
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
    // Each of these returns used to be silent, and all three run BEFORE the
    // refresh line below - so a capture showing an image error and no refresh
    // line could not say whether the refresh was skipped here or never
    // requested at all.
    if (event is! TimelineEventMessage) {
      _logImageRefreshSkipped(failedData, 'not_a_message_event');
      return null;
    }

    if (!shouldGetPreviewsInRoom(timeline.room)) {
      _logImageRefreshSkipped(failedData, 'previews_off_for_room');
      return null;
    }

    final originalUri = _firstPreviewUri(timeline, event);
    if (originalUri == null) {
      _logImageRefreshSkipped(failedData, 'no_link_on_event');
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
      roomIsE2EE: timeline.room.isE2EE,
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

    return true;
  }

  @override
  bool shouldGetPreviewDataForTimelineEvent(
    Timeline timeline,
    TimelineEvent event,
  ) {
    if (event is! TimelineEventMessage) {
      return false;
    }

    final room = timeline.room;

    if (!shouldGetPreviewsInRoom(room)) {
      return false;
    }

    final links = event.getLinks(timeline: timeline);
    final uri = links?.firstOrNull;
    if (uri == null) {
      return false;
    }

    return _canShowOrFetchPreviewForUri(timeline, event, uri);
  }

  bool _canShowOrFetchPreviewForUri(
    Timeline timeline,
    TimelineEventMessage event,
    Uri uri,
  ) {
    return _getCachedPreviewForEvent(timeline, event, uri) != null ||
        _getCachedPreviewForUri(uri) != null ||
        _canFetchPreviewForUri(uri);
  }

  bool _canFetchPreviewForUri(Uri uri) {
    if (serverSupportsUrlPreview != false) {
      return true;
    }

    if (UrlPreviewFallbackFetcher.shouldPreferDirectFetch(uri)) {
      return true;
    }

    return _canAttemptIntergalacticPreviewService();
  }

  bool _canAttemptIntergalacticPreviewService() {
    if (_isIntergalacticPreviewUnavailable()) {
      return false;
    }

    if (_intergalacticPreviewFetcher != null) {
      return true;
    }

    if (BuildConfig.INTERGALACTIC_URL_PREVIEW_ENDPOINT.trim().isEmpty) {
      return false;
    }

    return _canUseConfiguredIntergalacticPreviewService();
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
      roomIsE2EE: room.isE2EE,
    );
    if (durableHit != null) {
      final refreshedData = await _refreshMissingDurableImage(
        normalizedUri,
        uri,
        durableHit.data,
        roomIsE2EE: room.isE2EE,
      );
      if (refreshedData != null) {
        return refreshedData;
      }
      return _withoutVisiblyEmptyDurableData(durableHit.data);
    }

    if (!_canFetchPreviewForUri(normalizedUri)) {
      return null;
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
      roomIsE2EE: room.isE2EE,
    );
    _inFlight[cacheKey] = request;

    try {
      return await request;
    } finally {
      _inFlight.remove(cacheKey);
    }
  }

  /// Wraps [_buildPreviewData] so the site-icon fallback covers EVERY return
  /// path, not one branch.
  ///
  /// Owner QA 2026-09-03 found the real gap: the fallback used to live only
  /// inside `UrlPreviewFallbackFetcher.fetchPreview`, so it decorated the
  /// DIRECT fetch's own result and nothing else. TikTok and Instagram routinely
  /// block a client-side fetch, in which case the card is assembled from
  /// homeserver metadata instead - text with no image - and never passed
  /// through the fallback at all. That is why one Instagram post showed the
  /// icon (direct fetch succeeded, imageless) and another rendered as the bare
  /// word "Instagram" (direct fetch failed, server text used).
  ///
  /// Scope is unchanged: `shouldPreferDirectFetch` still gates it, so no host
  /// becomes fetchable that was not already. REVIEW 2026-09-09: it is ALSO now
  /// gated on `preferences.shouldAllowDirectUrlPreviewFallback` - fetching the
  /// provider's own site icon is a request to that same third-party origin,
  /// and this method used to run it unconditionally on any preferred-host
  /// preview with no image, which reached that origin even when the user had
  /// declined the direct-fetch fallback entirely.
  Future<UrlPreviewData?> buildPreviewData(
    matrix.Client client,
    Uri url, {
    required bool roomIsE2EE,
  }) async {
    final timer = Stopwatch()..start();
    final data = await _buildPreviewData(client, url, roomIsE2EE: roomIsE2EE);
    final remaining = _buildDeadline - timer.elapsed - _previewBuildSlack;
    return _withProviderSiteIcon(
      url,
      data,
      roomIsE2EE: roomIsE2EE,
      budget: remaining < _siteIconBudget ? remaining : _siteIconBudget,
    );
  }

  Future<UrlPreviewData?> _withProviderSiteIcon(
    Uri url,
    UrlPreviewData? data, {
    required bool roomIsE2EE,
    required Duration budget,
  }) async {
    if (data == null || data == UrlPreviewComponent.invalidPreviewData) {
      return data;
    }

    // kIsWeb matches the guard the sibling copy of this logic already carries
    // (UrlPreviewFallbackFetcher._withSiteIconFallback). Without it, every
    // imageless provider preview on web starts icon requests that CORS blocks.
    if (kIsWeb || !UrlPreviewFallbackFetcher.shouldPreferDirectFetch(url)) {
      return data;
    }

    // The same disclosure the direct-fetch fallback gates, to the same
    // provider origin: a site-icon request is still a connection this device
    // makes to instagram.com/tiktok.com/reddit.com rather than through the
    // preferred service, and a user who declined that disclosure must not
    // have it happen anyway just because the preview came back imageless.
    // REVIEW 2026-09-09, found while answering an unrelated owner question -
    // same shape as the durable-cache-hit bypass, a different entry path.
    if (!preferences.shouldAllowDirectUrlPreviewFallback(
      roomIsE2EE: roomIsE2EE,
    )) {
      return data;
    }

    if (!UrlPreviewFallbackFetcher.shouldUseSiteIconFallback(data)) {
      return data;
    }
    if (budget <= Duration.zero) return data;

    // Bounded, and its failure swallowed. The icon is decoration on a card
    // that is otherwise complete, and it used to be able to destroy one:
    // fetchSiteIcon tries three paths in sequence and each can redirect up to
    // six times at four seconds a hop, so it can outlast the caller's whole
    // budget - and _fetchAndCachePreview answers a timeout by caching the URL
    // as invalidPreviewData for ten minutes. A slow favicon would take the
    // preview with it, and then suppress the retry that would have fixed it.
    UrlPreviewSiteIcon? icon;
    try {
      icon = await _siteIconFetcher(url).timeout(budget);
    } on TimeoutException {
      icon = null;
    } catch (error, stackTrace) {
      Log.onError(error, stackTrace, content: 'URL preview site icon failed');
      icon = null;
    }
    if (icon == null) {
      return data;
    }

    return data.copyWith(
      image: icon.provider,
      imageUri: icon.uri,
      imageWidth: icon.width,
      imageHeight: icon.height,
    );
  }

  Future<UrlPreviewData?> _buildPreviewData(
    matrix.Client client,
    Uri url, {
    required bool roomIsE2EE,
  }) async {
    final timer = Stopwatch()..start();

    // Owner decision A, 2026-09-09: the homeserver/service path is preferred
    // and runs FIRST, unconditionally - it used to race a direct fetch in
    // parallel for these same hosts, which meant both the provider's CDN and
    // our own service received the request regardless of which one the
    // result actually used. Direct fetch is now attempted only as a
    // FALLBACK, and only after the preferred path has already been given the
    // chance to answer.
    final configured = await fetchConfiguredPreviewResponse(client, url);
    final response = configured.response;
    final rawServerData = response != null
        ? buildPreviewFromResponse(client, url, response)
        : null;
    final serverData = sanitizeUrlPreviewDataForUri(url, rawServerData);

    // Owner decisions B/C and S&C's ruling, 2026-09-09: a direct fetch is a
    // disclosure to a third-party CDN, and which recipient gets the
    // disclosure must be something the user chose, not something service
    // availability decided for them - so the fallback needs the user's
    // opt-in for THIS room's encryption state before it can even be
    // attempted, on top of the existing host-completeness signal
    // (`shouldPreferDirectFetch`) this project already had for which hosts
    // are worth a direct attempt at all.
    final directFallbackEligible =
        UrlPreviewFallbackFetcher.shouldPreferDirectFetch(url) &&
        preferences.shouldAllowDirectUrlPreviewFallback(roomIsE2EE: roomIsE2EE);

    UrlPreviewData? directData;
    final remaining = _buildDeadline - timer.elapsed - _previewBuildSlack;
    if (directFallbackEligible &&
        urlPreviewCompletenessScore(serverData) < 4 &&
        remaining > Duration.zero) {
      final rawDirectData = await _fetchDirectPreview(
        url,
        timeout: remaining < _previewRequestTimeout
            ? remaining
            : _previewRequestTimeout,
      );
      directData = sanitizeUrlPreviewDataForUri(url, rawDirectData);
    }

    final sanitizedGenericTikTokServerData =
        isTikTokPreviewUri(url) &&
        _didSanitizePreview(rawServerData, serverData) &&
        directData == null;

    if (sanitizedGenericTikTokServerData) {
      Log.i(
        "URL preview sanitized generic TikTok server metadata for host "
        "${_safePreviewHost(url)} because direct metadata was unavailable.",
      );

      // directData is null here for one of three reasons: web (CORS always
      // blocks a direct TikTok fetch), the room's consent gate declined the
      // direct-fetch fallback, or the fetch was attempted and simply
      // returned nothing. This used to be gated `kIsWeb &&`, on the
      // assumption that only web could reach this branch with directData
      // null - REVIEW 2026-09-11: the 2026-09-09 consent gate falsified
      // that, since a desktop/mobile room with the fallback declined reaches
      // it too, and desktop's TikTok tiles went blank because of exactly
      // that gap. Rather than returning null and showing no preview at all
      // on ANY platform, fall back to a stripped version of the server data:
      // keep the site name, any thumbnail image, and the posting account,
      // but drop the generic marketing title/description. Something >
      // nothing for the user. This reuses data the server already
      // returned - it is not a new third-party disclosure, so it is not
      // gated by the direct-fallback opt-in above.
      if (rawServerData != null) {
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

    final preferDirectFetch =
        directData != null &&
        (directFallbackEligible ||
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
      "direct_fallback_allowed=$directFallbackEligible "
      "direct_used=${directData != null} "
      "server_used=${serverData != null} "
      // WHICH server, not merely that one answered. server_used can also be
      // false while a backend did answer, when sanitization drops the whole
      // card - the source still names who produced what was dropped.
      "source=${configured.source.name} "
      "duration_ms=${timer.elapsedMilliseconds}",
    );

    return merged;
  }

  Future<({Map<String, Object?>? response, UrlPreviewBackend source})>
  fetchConfiguredPreviewResponse(matrix.Client client, Uri url) async {
    final intergalacticResponse = await fetchIntergalacticPreviewResponse(url);
    if (intergalacticResponse != null) {
      return (
        response: intergalacticResponse,
        source: UrlPreviewBackend.intergalactic,
      );
    }

    if (serverSupportsUrlPreview == false) {
      return (response: null, source: UrlPreviewBackend.none);
    }

    final serverResponse = await fetchPreviewResponse(client, url);
    return (
      response: serverResponse,
      source: serverResponse == null
          ? UrlPreviewBackend.none
          : UrlPreviewBackend.synapse,
    );
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

    _logIntergalacticPreviewServiceStatus('configured and homeserver-scoped');

    final requestUri = endpointUri.replace(
      queryParameters: {...endpointUri.queryParameters, 'url': url.toString()},
    );

    try {
      final response = await http
          .get(requestUri)
          .timeout(_previewRequestTimeout);
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
    matrix.Client client,
    Uri url,
  ) async {
    final override = _responseFetcher;
    if (override != null) {
      return override(client, url);
    }

    late Map<String, Object?> response;
    try {
      response = await client
          .request(
            matrix.RequestType.GET,
            await getRequestPath(),
            query: {"url": url.toString()},
          )
          .timeout(_previewRequestTimeout);
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
    required bool roomIsE2EE,
    bool cacheInvalid = true,
  }) async {
    UrlPreviewData? data;

    try {
      data = await buildPreviewData(
        mxClient,
        normalizedUri,
        roomIsE2EE: roomIsE2EE,
      ).timeout(_buildDeadline, onTimeout: () => null);
    } catch (_) {
      return null;
    }

    if (data != null) {
      _cachePreviewForUri(normalizedUri, data);
      _cachePreviewForUri(originalUri, data);
      await _putDurableCacheBestEffort(normalizedUri, originalUri, data);
    } else if (cacheInvalid) {
      _cachePreviewForUri(
        normalizedUri,
        UrlPreviewComponent.invalidPreviewData,
      );
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

  Future<UrlPreviewData?> _fetchDirectPreview(
    Uri url, {
    Duration timeout = _previewRequestTimeout,
  }) async {
    try {
      final directPreview = _directFetcher(
        url,
      ).then<UrlPreviewData?>((preview) => preview);
      return await directPreview.timeout(timeout, onTimeout: () => null);
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
        roomIsE2EE: timeline.room.isE2EE,
      );
      if (durableHit != null) {
        if (_shouldRefreshMissingDurableImage(normalizedUri, durableHit.data)) {
          candidates.add(
            _UrlPreviewWarmupCandidate(
              event: event,
              originalUri: uri,
              normalizedUri: normalizedUri,
            ),
          );
          continue;
        }

        if (!durableHit.isStale) {
          _cachePreviewForEventAliases(
            timeline,
            event,
            uri,
            normalizedUri,
            _withoutVisiblyEmptyDurableData(durableHit.data),
          );
        }
        continue;
      }

      candidates.add(
        _UrlPreviewWarmupCandidate(
          event: event,
          originalUri: uri,
          normalizedUri: normalizedUri,
        ),
      );
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
            roomIsE2EE: timeline.room.isE2EE,
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
    required bool roomIsE2EE,
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
      roomIsE2EE: roomIsE2EE,
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
    required bool roomIsE2EE,
  }) async {
    final hit = await _durableCache.get(normalizedUri, mxClient);
    if (hit == null) {
      return null;
    }

    final shouldRefreshMissingImage = _shouldRefreshMissingDurableImage(
      normalizedUri,
      hit.data,
    );
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
      _refreshStaleDurablePreview(
        mxClient,
        normalizedUri,
        originalUri,
        roomIsE2EE: roomIsE2EE,
      );
    }

    return hit;
  }

  Future<UrlPreviewData?> _refreshMissingDurableImage(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData cachedData, {
    required bool roomIsE2EE,
  }) async {
    if (!_shouldRefreshMissingDurableImage(normalizedUri, cachedData)) {
      return null;
    }

    // This is the SAME direct-fetch disclosure the _buildPreviewData fallback
    // gates, to the same provider CDN, via the same shouldPreferDirectFetch
    // predicate (_isMissingImageRefreshCandidate uses it too) - it just
    // arrives from a different call path: a durable-cache hit returns before
    // control ever reaches _buildPreviewData. Without this check, a user who
    // declined the fallback on first view would have that very refusal (a
    // cached preview with volatileImageOmitted true, exactly what a decline
    // produces) arm the direct fetch on the SECOND view - the refusal itself
    // becoming the trigger. REVIEW 2026-09-09.
    if (!preferences.shouldAllowDirectUrlPreviewFallback(
      roomIsE2EE: roomIsE2EE,
    )) {
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
      _cacheMissingImageRefreshFailure(normalizedUri, originalUri, cachedData);
      return null;
    }

    final refreshedData = mergeUrlPreviewData(
      cachedData,
      directData,
      preferSecondary: true,
    );
    if (refreshedData == null ||
        refreshedData.image == null && refreshedData.imageUri == null) {
      _cacheMissingImageRefreshFailure(normalizedUri, originalUri, cachedData);
      return null;
    }

    final cacheData = refreshedData.copyWith(volatileImageOmitted: false);
    _clearMissingImageRefreshFailure(normalizedUri, originalUri);
    _cachePreviewForUri(normalizedUri, cacheData);
    _cachePreviewForUri(originalUri, cacheData);
    await _putDurableCacheBestEffort(normalizedUri, originalUri, cacheData);
    return cacheData;
  }

  bool _shouldRefreshMissingDurableImage(Uri uri, UrlPreviewData data) {
    return _isMissingImageRefreshCandidate(uri, data) &&
        !_isMissingImageRefreshCoolingDown(uri);
  }

  bool _isMissingImageRefreshCandidate(Uri uri, UrlPreviewData data) {
    return data != UrlPreviewComponent.invalidPreviewData &&
        data.image == null &&
        data.imageUri == null &&
        data.volatileImageOmitted &&
        UrlPreviewFallbackFetcher.shouldPreferDirectFetch(uri);
  }

  /// A durable-cache hit whose only content was a volatile social-CDN image
  /// (TikTok/Instagram) can come back with title, description, postingAccount
  /// and stats all null and no image, once that image's TTL expires -
  /// [buildPreviewFromResponse]'s emptiness guard only runs when a preview is
  /// built fresh from a response, never when one is reconstructed directly
  /// from [UrlPreviewDurableCache], so nothing upstream of a caller ever
  /// catches this. Call after a missing-image refresh attempt (just above
  /// each call site) has already had its chance to restore the image -
  /// substituting this before that would disable the refresh entirely, since
  /// [_isMissingImageRefreshCandidate] treats the sentinel as never a
  /// candidate.
  UrlPreviewData _withoutVisiblyEmptyDurableData(UrlPreviewData data) {
    if (data == UrlPreviewComponent.invalidPreviewData) {
      return data;
    }

    if (data.image != null || data.imageUri != null) {
      return data;
    }

    if (normalizeUrlPreviewText(data.title) != null ||
        normalizeUrlPreviewText(data.description) != null ||
        normalizeUrlPreviewText(data.postingAccount) != null ||
        normalizeUrlPreviewText(data.stats) != null) {
      return data;
    }

    return UrlPreviewComponent.invalidPreviewData;
  }

  void _cacheMissingImageRefreshFailure(
    Uri normalizedUri,
    Uri originalUri,
    UrlPreviewData cachedData,
  ) {
    _recordMissingImageRefreshFailure(normalizedUri, originalUri);
    _cachePreviewForUri(normalizedUri, cachedData);
    _cachePreviewForUri(originalUri, cachedData);
  }

  void _recordMissingImageRefreshFailure(Uri normalizedUri, Uri originalUri) {
    final now = _now();
    _missingImageRefreshFailureTimestamps[normalizedUri.toString()] = now;
    _missingImageRefreshFailureTimestamps[originalUri.toString()] = now;
  }

  void _clearMissingImageRefreshFailure(Uri normalizedUri, Uri originalUri) {
    _missingImageRefreshFailureTimestamps.remove(normalizedUri.toString());
    _missingImageRefreshFailureTimestamps.remove(originalUri.toString());
  }

  bool _isMissingImageRefreshCoolingDown(Uri uri) {
    final key = uri.toString();
    final failedAt = _missingImageRefreshFailureTimestamps[key];
    if (failedAt == null) {
      return false;
    }

    if (_now().difference(failedAt) > _missingImageRefreshRetryDelay) {
      _missingImageRefreshFailureTimestamps.remove(key);
      return false;
    }

    return true;
  }

  void _refreshStaleDurablePreview(
    matrix.Client mxClient,
    Uri normalizedUri,
    Uri originalUri, {
    required bool roomIsE2EE,
  }) {
    if (_inFlight.containsKey(normalizedUri.toString())) {
      return;
    }

    unawaited(
      _startPreviewRequest(
        mxClient,
        normalizedUri,
        originalUri,
        roomIsE2EE: roomIsE2EE,
      ),
    );
  }

  UrlPreviewData? _getCachedPreviewForUri(Uri uri) {
    final localCacheKey = uri.toString();
    final localCacheData = cache[localCacheKey];
    if (localCacheData != null) {
      if (_isExpiredInvalidPreview(
        localCacheData,
        _invalidCacheTimestamps[localCacheKey],
      )) {
        cache.remove(localCacheKey);
        _invalidCacheTimestamps.remove(localCacheKey);
      } else if (_isExpiredMissingImageRefreshPreview(uri, localCacheData)) {
        cache.remove(localCacheKey);
      } else {
        return localCacheData;
      }
    }

    final longLivedCacheKey = _longLivedCacheKey(uri);
    final longLivedCacheData = _longLivedCache.remove(longLivedCacheKey);
    final invalidTimestamp = _longLivedInvalidCacheTimestamps.remove(
      longLivedCacheKey,
    );
    if (longLivedCacheData == null) {
      return null;
    }

    if (_isExpiredInvalidPreview(longLivedCacheData, invalidTimestamp)) {
      return null;
    }

    if (_isExpiredMissingImageRefreshPreview(uri, longLivedCacheData)) {
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
    _missingImageRefreshFailureTimestamps.remove(uri.toString());

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

  bool _isExpiredMissingImageRefreshPreview(Uri uri, UrlPreviewData data) {
    return _isMissingImageRefreshCandidate(uri, data) &&
        !_isMissingImageRefreshCoolingDown(uri);
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
        localCacheData,
        _invalidEventCacheTimestamps[localCacheKey],
      )) {
        _eventCache.remove(localCacheKey);
        _invalidEventCacheTimestamps.remove(localCacheKey);
      } else if (_isExpiredMissingImageRefreshPreview(uri, localCacheData)) {
        _eventCache.remove(localCacheKey);
      } else {
        return localCacheData;
      }
    }

    final longLivedCacheKey = _eventCacheKey(timeline, event, uri);
    final longLivedCacheData = _longLivedEventCache.remove(longLivedCacheKey);
    final invalidTimestamp = _longLivedInvalidEventCacheTimestamps.remove(
      longLivedCacheKey,
    );
    if (longLivedCacheData == null) {
      return null;
    }

    if (_isExpiredInvalidPreview(longLivedCacheData, invalidTimestamp)) {
      return null;
    }

    if (_isExpiredMissingImageRefreshPreview(uri, longLivedCacheData)) {
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

  void _logImageRefreshSkipped(UrlPreviewData failedData, String reason) {
    Log.d(
      'URL preview image refresh skipped '
      'host=${_safePreviewHost(failedData.uri)} reason=$reason',
      category: LogCategory.media,
      source: 'url-preview',
    );
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
    UrlPreviewData? original,
    UrlPreviewData? sanitized,
  ) {
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
    var title = _firstString(response, ['og:title', 'twitter:title', 'title']);
    var siteName =
        _firstString(response, [
          'og:site_name',
          'twitter:site',
          'site_name',
          'siteName',
        ]) ??
        inferUrlPreviewSource(url);
    var imageUrl = _firstImageString(response);
    var description = trimUrlPreviewDescription(
      _firstString(response, [
        'og:description',
        'twitter:description',
        'description',
      ]),
    );

    var type = _firstString(response, ["og:image:type", "twitter:image:type"]);
    if (type != null) {
      if (Mime.displayableImageTypes.contains(type) == false) {
        imageUrl = null;
      }
    }

    ImageProvider? image;
    Uri? imageUri;
    var droppedThirdPartyImage = false;
    if (imageUrl != null) {
      final parsedImageUri = Uri.parse(imageUrl);
      if (parsedImageUri.scheme == "mxc") {
        // The homeserver already downloaded the origin's image into its own
        // media repository, so this renders through the homeserver's
        // media/thumbnail endpoint and the third party never sees the client.
        try {
          image = MatrixMxcImage(parsedImageUri, client, doThumbnail: false);
          imageUri = parsedImageUri;
        } catch (exception, stack) {
          Log.onError(exception, stack);
          Log.w("Failed to get mxc image");
        }
      } else if (parsedImageUri.scheme == "http" ||
          parsedImageUri.scheme == "https") {
        // The homeserver handed us a URL STRING, not bytes. Rendering it makes
        // the CLIENT open a connection to fbcdn/tiktokcdn/Instagram, which
        // discloses the user's IP, TLS fingerprint and default User-Agent to
        // that CDN - including for a preview shown inside an end-to-end
        // encrypted room. (An earlier comment here claimed the opposite; it
        // was wrong, and this is the regression it caused.)
        //
        // There is no Matrix endpoint that proxies an arbitrary third-party
        // URL, so an image the homeserver did not give us as `mxc://` cannot
        // be routed through it. Dropping the image is the correct fallback and
        // is the pre-regression behaviour.
        droppedThirdPartyImage = true;
        Log.d(
          'URL preview dropped a third-party image URL that is not homeserver '
          'media host=${_safePreviewHost(url)} '
          'image_host=${_safePreviewHost(parsedImageUri)} '
          'volatile=${isVolatileUrlPreviewImageUri(parsedImageUri)}',
          category: LogCategory.media,
          source: 'url-preview',
        );
      }
    }

    final postingAccount = normalizeUrlPreviewPostingAccount(
      _firstString(response, [
        'author_name',
        'author',
        'article:author',
        'profile:username',
        'twitter:creator',
        'posting_account',
        'postingAccount',
      ]),
    );

    final publishedAt = _parsePublishedDate(
      _firstString(response, [
        'article:published_time',
        'og:updated_time',
        'published_time',
        'published_at',
        'publishedAt',
      ]),
    );

    final stats =
        _firstString(response, ['stats', 'stats_line', 'statsLine']) ??
        buildUrlPreviewStatsLine(
          likes: _parseIntValue(
            _firstValue(response, [
              'likes',
              'like_count',
              'og:likes',
              'likeCount',
            ]),
          ),
          comments: _parseIntValue(
            _firstValue(response, [
              'comments',
              'comment_count',
              'og:comments',
              'commentCount',
            ]),
          ),
          publishedAt: publishedAt,
        );

    final imageWidth = _parseIntValue(
      _firstValue(response, [
        'og:image:width',
        'twitter:image:width',
        'image:width',
        'image_width',
        'imageWidth',
      ]),
    );
    final imageHeight = _parseIntValue(
      _firstValue(response, [
        'og:image:height',
        'twitter:image:height',
        'image:height',
        'image_height',
        'imageHeight',
      ]),
    );

    if (title == null && description == null && image == null) {
      return null;
    }

    final previewUrl = _previewUriFromResponse(response, url);

    return UrlPreviewData(
      previewUrl,
      siteName: siteName,
      title: title,
      image: image,
      imageUri: imageUri,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      description: description,
      postingAccount: postingAccount,
      stats: stats,
      // Armed when a third-party image URL was dropped just above. It is what
      // `_isMissingImageRefreshCandidate` reads, so for a provider host this
      // is a CANDIDATE for a later direct-fetch refresh - not a standing
      // permission. `_refreshMissingDurableImage` still checks
      // `preferences.shouldAllowDirectUrlPreviewFallback` for the room's
      // encryption state before that refresh fires; without the room, this
      // flag alone says nothing about whether the client may make the
      // request. For every other host the card simply renders without one.
      volatileImageOmitted: droppedThirdPartyImage,
    );
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

  static const List<String> _imageResponseKeys = [
    'og:image:secure_url',
    'og:image:url',
    'og:image',
    'twitter:image',
    'twitter:image:src',
    'image_url',
    'imageUrl',
    'image',
  ];

  /// Picks the image candidate that can be fetched from the homeserver.
  ///
  /// `/_matrix/media/*/preview_url` rewrites `og:image` to an `mxc://` URI,
  /// but a response can carry several image keys and the earlier ones
  /// (`og:image:secure_url`, `twitter:image`) may still be the origin's own
  /// https URL. Taking the first key present would then discard an `mxc://` we
  /// could have routed through the homeserver, so scan every candidate for one
  /// before falling back to the first value.
  String? _firstImageString(Map<String, Object?> response) {
    String? firstCandidate;
    for (final key in _imageResponseKeys) {
      final value = _firstString(response, [key]);
      if (value == null) {
        continue;
      }

      if (Uri.tryParse(value)?.scheme == 'mxc') {
        return value;
      }

      firstCandidate ??= value;
    }

    return firstCandidate;
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
    return host.toLowerCase().replaceFirst(
      RegExp(r'^www\.', caseSensitive: false),
      '',
    );
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
