import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_direct_fetch_resolver.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

/// A resolved site icon.
///
/// Public only so a test can construct one and inject it through
/// [UrlPreviewFallbackFetcher.fetchPreview]; the internal fetch path builds it
/// from the same validated bytes as any other preview image.
class UrlPreviewSiteIcon {
  const UrlPreviewSiteIcon({
    required this.provider,
    required this.uri,
    this.width,
    this.height,
  });

  final ImageProvider provider;
  final Uri uri;
  final int? width;
  final int? height;
}

class UrlPreviewFallbackFetcher {
  static const Duration _requestTimeout = Duration(seconds: 4);
  static const int _maxImageBytes = 1024 * 1024 * 2;
  static const String _browserUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36";

  static bool shouldPreferDirectFetch(Uri uri) {
    return _isTikTok(uri) || _isInstagram(uri) || _isReddit(uri);
  }

  static bool isSafeDirectFetchUri(Uri uri) {
    if (!_isHttpUri(uri)) {
      return false;
    }

    final host = _normalizedHost(uri);
    if (host == null) {
      return false;
    }

    if (host == "localhost" ||
        host.endsWith(".localhost") ||
        host == "metadata" ||
        host == "metadata.google.internal" ||
        host.endsWith(".local")) {
      return false;
    }

    return !_isPrivateIpv4Host(host) && !_isPrivateIpv6Host(host);
  }

  /// [providerFetcher] and [siteIconFetcher] are TEST SEAMS and are null in
  /// production. They exist because the site-icon fallback sits behind two real
  /// HTTP fetches, which left its call site unreachable from any test: deleting
  /// the fallback from this method entirely used to leave the suite green
  /// (REVIEW, at the merge of PR #282). They deliberately inject INTO this
  /// method rather than duplicating it, so a test exercises this exact call
  /// site and removing the call turns that test red.
  static Future<UrlPreviewData?> fetchPreview(
    Uri uri, {
    Future<UrlPreviewData?> Function(Uri uri)? providerFetcher,
    Future<UrlPreviewSiteIcon?> Function(Uri uri)? siteIconFetcher,
  }) async {
    if (!_isHttpUri(uri)) {
      return null;
    }

    if (!shouldPreferDirectFetch(uri)) {
      return null;
    }

    if (!isSafeDirectFetchUri(uri)) {
      _logDirectFetchBlocked(uri);
      return null;
    }

    return _withSiteIconFallback(
      uri,
      await (providerFetcher ?? _fetchProviderPreview)(uri),
      siteIconFetcher ?? fetchSiteIcon,
    );
  }

  /// Last-resort thumbnail: the provider's own site icon.
  ///
  /// Only applied when the preview has NO image of any kind. That condition is
  /// the whole safety property - a site icon can never displace a real
  /// thumbnail, which is what made the earlier blanket fallback unwanted. When
  /// a provider blocks the thumbnail or omits it, the card previously rendered
  /// as text only; this gives it the provider's mark instead.
  ///
  /// Scope is deliberately the provider adapters and nothing else. Fetching an
  /// arbitrary host's icon would re-open exactly the client-side
  /// arbitrary-host fetch that 90f75c96 closed on 2026-05-20; these hosts are
  /// already permitted to be fetched by `shouldPreferDirectFetch`, so this adds
  /// no new host to the reachable set.
  ///
  /// REVIEW 2026-09-09: that was the whole permission check when this was
  /// written, because `shouldPreferDirectFetch` unconditionally permitted a
  /// direct fetch to these hosts. It no longer does - permission is now ALSO
  /// conditional on `preferences.shouldAllowDirectUrlPreviewFallback`, and
  /// THIS METHOD DOES NOT CHECK IT. It is only safe today because its one
  /// caller, `fetchPreview`, is only reached from
  /// `MatrixUrlPreviewComponent._fetchDirectPreview`, which is itself only
  /// called after that consent check has already passed. A new caller of
  /// `fetchPreview` (or of `_withSiteIconFallback` directly) that skips that
  /// check would reopen the exact disclosure a sibling call site
  /// (`MatrixUrlPreviewComponent._withProviderSiteIcon`) was found doing.
  static Future<UrlPreviewData?> _withSiteIconFallback(
    Uri uri,
    UrlPreviewData? data,
    Future<UrlPreviewSiteIcon?> Function(Uri uri) fetchIcon,
  ) async {
    if (data == null || kIsWeb) {
      return data;
    }

    if (!shouldUseSiteIconFallback(data)) {
      return data;
    }

    final icon = await fetchIcon(uri);
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

  /// Whether a preview is eligible for the site-icon fallback.
  ///
  /// The ONLY eligible case is a preview with no image of any kind. This is the
  /// property that keeps the fallback from "taking over": it is structurally
  /// incapable of replacing a real thumbnail, rather than merely ordered after
  /// one.
  ///
  /// Not test-only: MatrixUrlPreviewComponent applies the same predicate to
  /// previews assembled from homeserver metadata, which never reach this
  /// class's own fetch path. It was annotated @visibleForTesting when the
  /// fallback lived only here; the analyzer flagged the production use as soon
  /// as the component started sharing it.
  static bool shouldUseSiteIconFallback(UrlPreviewData? data) {
    return data != null && data.image == null && data.imageUri == null;
  }

  /// Well-known icon paths on the provider's own origin.
  ///
  /// Deliberately does NOT parse the page for `<link rel="icon">`: reaching the
  /// icon that way needs the page fetch that has usually already failed or been
  /// blocked, which is the case this fallback exists for. `apple-touch-icon` is
  /// tried first because it is a large square mark rather than a 16px favicon.
  static Future<UrlPreviewSiteIcon?> fetchSiteIcon(Uri uri) async {
    final origin = Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    for (final path in const [
      '/apple-touch-icon.png',
      '/apple-touch-icon-precomposed.png',
      '/favicon.ico',
    ]) {
      final icon = await _fetchImage(
        origin.resolve(path).toString(),
        baseUri: origin,
      );
      if (icon != null) {
        return UrlPreviewSiteIcon(
          provider: icon.provider,
          uri: icon.uri,
          width: icon.width,
          height: icon.height,
        );
      }
    }

    return null;
  }

  static Future<UrlPreviewData?> _fetchProviderPreview(Uri uri) async {
    try {
      if (_isTikTok(uri)) {
        final tiktok = kIsWeb
            ? await _fetchTikTokPreviewWeb(uri)
            : await _fetchTikTokPreview(uri);
        if (tiktok != null) {
          return tiktok;
        }
      }

      if (kIsWeb) {
        return null;
      }

      if (_isInstagram(uri)) {
        final instagram = await _fetchInstagramPreview(uri);
        if (instagram != null) {
          return instagram;
        }
      }

      if (_isReddit(uri)) {
        final reddit = await _fetchRedditPreview(uri);
        if (reddit != null) {
          return reddit;
        }
      }

      return await _fetchGenericPreview(uri);
    } catch (error) {
      _logOptionalFetchFailure(uri, 'direct URL preview fallback', error);
      return null;
    }
  }

  static Future<UrlPreviewData?> _fetchTikTokPreviewWeb(Uri uri) async {
    final oEmbed = await _fetchJson(
      Uri.https("www.tiktok.com", "/oembed", {"url": uri.toString()}),
      accept: "application/json",
    );

    // `oEmbed["thumbnail_url"]` is deliberately NOT read here. See the image
    // block below for why this path yields no image on web.

    final title = normalizeUrlPreviewText(_stringValue(oEmbed?["title"]));

    final authorUniqueId = normalizeUrlPreviewText(
      _stringValue(oEmbed?["author_unique_id"]),
    );
    final authorHandle = authorUniqueId == null
        ? null
        : authorUniqueId.startsWith("@")
        ? authorUniqueId
        : "@$authorUniqueId";
    final authorName = normalizeUrlPreviewText(
      _stringValue(oEmbed?["author_name"]),
    );
    final postingAccount = normalizeUrlPreviewPostingAccount(
      _firstNonEmpty([
        if (authorName != null && authorHandle != null)
          "$authorName ($authorHandle)",
        authorHandle,
        authorName,
        _extractTikTokUsername(uri),
      ]),
    );

    // NO IMAGE FROM THIS PATH ON WEB, deliberately, and it is the same rule
    // the server path already enforces.
    //
    // This used to be `NetworkImage(oEmbed["thumbnail_url"])`, which handed the
    // browser a TikTok CDN URL to fetch directly. Two things were wrong with
    // that, and only one of them is about privacy:
    //
    // 1. `MatrixUrlPreviewComponent._safeTikTokWebFallbackImage` ALREADY
    //    refuses exactly these hosts - tiktok, tiktokcdn, byteoversea,
    //    ibyteimg, ibytedtos - when the SERVER supplies the image on web,
    //    because TikTok serves non-image anti-bot payloads from those CDN URLs
    //    in a browser and they explode as ImageCodecException. This path
    //    produced an image the neighbouring rule would have rejected.
    // 2. Every other platform reaches its thumbnail through `_fetchImage`,
    //    which downloads the bytes under `_maxImageBytes` and validates them
    //    before wrapping them in a `MemoryImage`. A bare `NetworkImage` is
    //    fetched by the renderer, so it is subject to neither the cap nor the
    //    validation, and the request goes straight from the viewer's browser
    //    to the provider CDN.
    //
    // The byte-fetching route is not available here - a cross-origin image
    // fetch is blocked on web the same way the oEmbed request is - so there is
    // no validated form of this image to substitute. The preview service
    // supplies web thumbnails instead; see the server fallback in
    // `_buildPreviewData`, which is the path `_safeTikTokWebFallbackImage`
    // guards.
    //
    // Width and height are still reported: they describe the ORIGINAL media
    // and are used for layout, so they stay useful when the server supplies
    // the image.
    const ImageProvider? image = null;
    final imageWidth = _positiveIntValue(oEmbed?["thumbnail_width"]);
    final imageHeight = _positiveIntValue(oEmbed?["thumbnail_height"]);

    if (title == null && postingAccount == null && image == null) {
      return null;
    }

    return UrlPreviewData(
      uri,
      siteName: "TikTok",
      title: title,
      description: null,
      image: image,
      // Null for the same reason as [image], and it has to move WITH it:
      // `shouldUseSiteIconFallback` requires BOTH to be null before it will
      // offer the site icon. Nulling the provider alone would leave a card
      // that has no image and is also ineligible for the fallback - strictly
      // worse than either outcome.
      imageUri: null,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      postingAccount: postingAccount,
      stats: null,
    );
  }

  static Future<UrlPreviewData?> _fetchTikTokPreview(Uri uri) async {
    final oEmbed = await _fetchJson(
      Uri.https("www.tiktok.com", "/oembed", {"url": uri.toString()}),
      accept: "application/json",
    );
    final document = await _fetchDocument(uri);
    final metadata = document != null
        ? _extractMetaTags(document)
        : <String, String>{};

    final image = await _fetchImage(
      _firstNonEmpty([
        _stringValue(oEmbed?["thumbnail_url"]),
        metadata["og:image:secure_url"],
        metadata["og:image:url"],
        metadata["og:image"],
        metadata["twitter:image"],
        metadata["twitter:image:src"],
      ]),
      baseUri: uri,
      width:
          _positiveIntValue(oEmbed?["thumbnail_width"]) ??
          _extractInt(document?.outerHtml, [RegExp(r'"thumbnailWidth":(\d+)')]),
      height:
          _positiveIntValue(oEmbed?["thumbnail_height"]) ??
          _extractInt(document?.outerHtml, [
            RegExp(r'"thumbnailHeight":(\d+)'),
          ]),
    );

    final title = normalizeUrlPreviewText(
      _firstNonEmpty([
        _stringValue(oEmbed?["title"]),
        metadata["og:title"],
        metadata["twitter:title"],
        document?.querySelector("title")?.text,
        "TikTok video",
      ]),
    );

    final authorUniqueId = normalizeUrlPreviewText(
      _stringValue(oEmbed?["author_unique_id"]),
    );
    final authorHandle = authorUniqueId == null
        ? null
        : authorUniqueId.startsWith("@")
        ? authorUniqueId
        : "@$authorUniqueId";
    final authorName = normalizeUrlPreviewText(
      _stringValue(oEmbed?["author_name"]),
    );
    final postingAccount = normalizeUrlPreviewPostingAccount(
      _firstNonEmpty([
        if (authorName != null && authorHandle != null)
          "$authorName ($authorHandle)",
        authorHandle,
        authorName,
        _extractMatch(document?.outerHtml, [
          RegExp(r'"uniqueId":"([^"]+)"'),
          RegExp(r'"authorName":"([^"]+)"'),
        ]),
        _extractTikTokUsername(uri),
      ]),
    );

    final description = trimUrlPreviewDescription(
      _firstNonEmpty([
        _extractTikTokDescription(document, metadata, title),
        _stringValue(oEmbed?["title"]),
      ]),
    );

    final publishedAt = _parseDate(
      _firstNonEmpty([
        metadata["article:published_time"],
        _extractMatch(document?.outerHtml, [
          RegExp(r'"createTime":"?(\d{10,13})"?'),
        ]),
      ]),
    );

    final stats = buildUrlPreviewStatsLine(
      likes: _extractInt(document?.outerHtml, [
        RegExp(r'"diggCount":(\d+)'),
        RegExp(r'"likeCount":(\d+)'),
      ]),
      comments: _extractInt(document?.outerHtml, [
        RegExp(r'"commentCount":(\d+)'),
      ]),
      publishedAt: publishedAt,
    );

    if (title == null && description == null && image == null) {
      return null;
    }

    return UrlPreviewData(
      uri,
      siteName:
          normalizeUrlPreviewText(
            _firstNonEmpty([
              _stringValue(oEmbed?["provider_name"]),
              metadata["og:site_name"],
            ]),
          ) ??
          "TikTok",
      title: title,
      description: description,
      image: image?.provider,
      imageUri: image?.uri,
      imageWidth: image?.width,
      imageHeight: image?.height,
      postingAccount: postingAccount,
      stats: stats,
    );
  }

  static Future<UrlPreviewData?> _fetchInstagramPreview(Uri uri) async {
    final permalink = _parseInstagramPermalink(uri);
    final oEmbed = await _fetchJson(
      Uri.https("www.instagram.com", "/api/v1/oembed/", {
        "url": uri.toString(),
      }),
      accept: "application/json",
    );
    final document = await _fetchDocument(uri);
    final metadata = document != null
        ? _extractMetaTags(document)
        : <String, String>{};
    final htmlSources = await _fetchInstagramHtmlSources(uri, permalink);
    final textSources = <String?>[document?.outerHtml, ...htmlSources];
    final imageCandidates = <String?>[
      _stringValue(oEmbed?["thumbnail_url"]),
      metadata["og:image:secure_url"],
      metadata["og:image:url"],
      metadata["og:image"],
      metadata["twitter:image"],
      metadata["twitter:image:src"],
      for (final html in htmlSources) ..._extractInstagramImageCandidates(html),
    ];

    final image = await _fetchImage(
      _firstNonEmpty(imageCandidates),
      baseUri: uri,
      width:
          _positiveIntValue(oEmbed?["thumbnail_width"]) ??
          _toPositiveInt(metadata["og:image:width"]),
      height:
          _positiveIntValue(oEmbed?["thumbnail_height"]) ??
          _toPositiveInt(metadata["og:image:height"]),
    );

    final title = _fallbackInstagramTitle(uri);

    final postingAccount = normalizeUrlPreviewPostingAccount(
      _firstNonEmpty([
        _stringValue(oEmbed?["author_name"]),
        _extractMatch(metadata["og:title"], [
          RegExp(r"^([^:]+?) on Instagram"),
        ]),
        metadata["profile:username"],
        metadata["twitter:creator"],
        for (final source in textSources)
          _extractMatch(source, [
            RegExp(r'"owner"\s*:\s*\{[\s\S]*?"username"\s*:\s*"([^"]+)"'),
            RegExp(r'"username"\s*:\s*"([^"]+)"\s*,\s*"full_name"'),
          ]),
      ]),
    );

    final descriptionSource = _firstNonEmpty([
      _stringValue(oEmbed?["title"]),
      metadata["og:description"],
      metadata["twitter:description"],
      for (final source in textSources)
        _extractMatch(source, [
          RegExp(
            r'"edge_media_to_caption"[\s\S]*?"text"\s*:\s*"((?:\\.|[^"])*)"',
          ),
          RegExp(r'"caption":"((?:\\.|[^"])*)"'),
          RegExp(r'"accessibility_caption":"((?:\\.|[^"])*)"'),
        ])?.replaceAll(r"\/", "/"),
    ]);

    final stats = _buildStatsFromFreeText(
      descriptionSource,
      publishedAt: _parseDate(metadata["article:published_time"]),
    );

    if (descriptionSource == null && image == null && postingAccount == null) {
      return null;
    }

    return UrlPreviewData(
      uri,
      siteName:
          normalizeUrlPreviewText(metadata["og:site_name"]) ?? "Instagram",
      title: title,
      description: trimUrlPreviewDescription(descriptionSource),
      image: image?.provider,
      imageUri: image?.uri,
      imageWidth: image?.width,
      imageHeight: image?.height,
      postingAccount: postingAccount,
      stats: stats,
    );
  }

  static Future<UrlPreviewData?> _fetchRedditPreview(Uri uri) async {
    final oEmbed = await _fetchJson(
      Uri.https("www.reddit.com", "/oembed", {"url": uri.toString()}),
      accept: "application/json",
    );
    final post = await _fetchRedditPost(uri);

    final canonicalUri =
        _resolveUrl(
          _stringValue(post?["permalink"]) != null
              ? "https://www.reddit.com${post!["permalink"]}"
              : null,
          uri,
        ) ??
        uri;

    final image = await _fetchImage(
      _firstNonEmpty([
        _pickRedditImageUrl(post),
        _stringValue(oEmbed?["thumbnail_url"]),
      ]),
      baseUri: canonicalUri,
      width:
          _pickRedditImageDimension(post, "width") ??
          _positiveIntValue(oEmbed?["thumbnail_width"]),
      height:
          _pickRedditImageDimension(post, "height") ??
          _positiveIntValue(oEmbed?["thumbnail_height"]),
      userAgent: "matrix-bot/1.0",
    );

    final subreddit = _normalizeSubreddit(
      _stringValue(post?["subreddit_name_prefixed"]) ??
          _stringValue(post?["subreddit"]),
    );
    final author = _stringValue(post?["author"]);
    final postingAccount = _firstNonEmpty([
      if (subreddit != null && author != null) "$subreddit • u/$author",
      subreddit,
      if (author != null) "u/$author",
      _stringValue(oEmbed?["author_name"]),
    ]);

    final publishedAt = _parseDate(post?["created_utc"]?.toString());
    final stats = buildUrlPreviewStatsLine(
      likes:
          _toPositiveInt(post?["ups"]?.toString()) ??
          _toPositiveInt(post?["score"]?.toString()),
      comments: _toPositiveInt(post?["num_comments"]?.toString()),
      publishedAt: publishedAt,
    );

    final title = normalizeUrlPreviewText(
      _stringValue(post?["title"]) ?? _stringValue(oEmbed?["title"]),
    );
    final description = trimUrlPreviewDescription(
      _firstNonEmpty([_stringValue(post?["selftext"]), title]),
    );

    if (title == null && description == null && image == null) {
      return null;
    }

    return UrlPreviewData(
      canonicalUri,
      siteName:
          normalizeUrlPreviewText(_stringValue(oEmbed?["provider_name"])) ??
          "Reddit",
      title: title,
      description: description,
      image: image?.provider,
      imageUri: image?.uri,
      imageWidth: image?.width,
      imageHeight: image?.height,
      postingAccount: postingAccount,
      stats: stats,
    );
  }

  static Future<UrlPreviewData?> _fetchGenericPreview(Uri uri) async {
    final document = await _fetchDocument(uri);
    if (document == null) {
      return null;
    }

    final metadata = _extractMetaTags(document);
    final canonicalUrl =
        _resolveUrl(
          _firstNonEmpty([metadata["og:url"], _extractCanonicalLink(document)]),
          uri,
        ) ??
        uri;

    final image = await _fetchImage(
      _firstNonEmpty([
        metadata["og:image:secure_url"],
        metadata["og:image:url"],
        metadata["og:image"],
        metadata["twitter:image"],
        metadata["twitter:image:src"],
      ]),
      baseUri: canonicalUrl,
      width:
          _toPositiveInt(metadata["og:image:width"]) ??
          _toPositiveInt(metadata["twitter:image:width"]),
      height:
          _toPositiveInt(metadata["og:image:height"]) ??
          _toPositiveInt(metadata["twitter:image:height"]),
    );

    final title = normalizeUrlPreviewText(
      _firstNonEmpty([
        metadata["og:title"],
        metadata["twitter:title"],
        document.querySelector("title")?.text,
      ]),
    );

    final description = trimUrlPreviewDescription(
      _firstNonEmpty([
        metadata["og:description"],
        metadata["twitter:description"],
        metadata["description"],
        _extractJsonLdValue(document, "description"),
      ]),
    );

    final postingAccount = normalizeUrlPreviewPostingAccount(
      _firstNonEmpty([
        metadata["twitter:creator"],
        metadata["profile:username"],
        metadata["author"],
        metadata["article:author"],
      ]),
    );

    if (title == null && description == null && image == null) {
      return null;
    }

    return UrlPreviewData(
      canonicalUrl,
      siteName:
          normalizeUrlPreviewText(
            _firstNonEmpty([
              metadata["og:site_name"],
              metadata["twitter:site"],
            ]),
          ) ??
          inferUrlPreviewSource(canonicalUrl),
      title: title,
      description: description,
      image: image?.provider,
      imageUri: image?.uri,
      imageWidth: image?.width,
      imageHeight: image?.height,
      postingAccount: postingAccount,
      stats: _buildStatsFromFreeText(
        _firstNonEmpty([
          metadata["og:description"],
          metadata["twitter:description"],
          metadata["description"],
        ]),
        publishedAt: _parseDate(
          _firstNonEmpty([
            metadata["article:published_time"],
            metadata["og:updated_time"],
          ]),
        ),
      ),
    );
  }

  static Future<dom.Document?> _fetchDocument(Uri uri) async {
    try {
      final response = await _fetchResponse(uri, headers: _browserHeaders());
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }

      return html_parser.parse(response.body);
    } catch (error) {
      _logOptionalFetchFailure(uri, 'preview document', error);
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _fetchJson(
    Uri uri, {
    required String accept,
  }) async {
    try {
      final response = await _fetchResponse(
        uri,
        headers: _browserHeaders(accept: accept),
      );
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (error) {
      _logOptionalFetchFailure(uri, 'preview JSON', error);
    }

    return null;
  }

  static Future<_FetchedPreviewImage?> _fetchImage(
    String? imageUrl, {
    required Uri baseUri,
    int? width,
    int? height,
    String? userAgent,
  }) async {
    final resolved = _resolveUrl(imageUrl, baseUri);
    if (resolved == null || !_isHttpUri(resolved)) {
      return null;
    }
    if (!isSafeDirectFetchUri(resolved)) {
      _logDirectFetchBlocked(resolved);
      return null;
    }

    http.Client? client;
    try {
      client = http.Client();
      final fetch = await _sendSafeGet(
        client,
        resolved,
        headers: _browserHeaders(
          accept:
              "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
          userAgent: userAgent,
        ),
      );
      if (fetch == null) {
        return null;
      }

      final response = fetch.response;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final contentType = response.headers["content-type"] ?? "";
      if (!contentType.startsWith("image/")) {
        return null;
      }

      final contentLength = response.contentLength;
      if (contentLength != null &&
          (contentLength <= 0 || contentLength > _maxImageBytes)) {
        return null;
      }

      final bytesBuilder = BytesBuilder(copy: false);
      var receivedBytes = 0;
      await for (final chunk in response.stream) {
        receivedBytes += chunk.length;
        if (receivedBytes > _maxImageBytes) {
          throw StateError('Preview image exceeded the byte limit');
        }
        bytesBuilder.add(chunk);
      }
      final bytes = bytesBuilder.takeBytes();
      if (bytes.isEmpty || bytes.length > _maxImageBytes) {
        return null;
      }

      final dimensions = await _decodeImageDimensions(bytes);
      return _FetchedPreviewImage(
        provider: MemoryImage(bytes),
        uri: fetch.uri,
        width: width ?? dimensions?.$1,
        height: height ?? dimensions?.$2,
      );
    } catch (error) {
      _logOptionalFetchFailure(resolved, 'preview image', error);
      return null;
    } finally {
      client?.close();
    }
  }

  static void _logOptionalFetchFailure(
    Uri uri,
    String operation,
    Object error,
  ) {
    Log.d(
      'Optional URL preview $operation failed for host ${uri.host}: '
      '${error.runtimeType}',
      category: LogCategory.media,
      source: 'url-preview',
    );
  }

  static Future<http.Response?> _fetchResponse(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    http.Client? client;
    try {
      client = http.Client();
      final fetch = await _sendSafeGet(client, uri, headers: headers);
      if (fetch == null) {
        return null;
      }

      return await http.Response.fromStream(fetch.response);
    } finally {
      client?.close();
    }
  }

  static Future<({Uri uri, http.StreamedResponse response})?> _sendSafeGet(
    http.Client client,
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    var currentUri = uri;

    for (var redirects = 0; redirects <= 5; redirects += 1) {
      if (!isSafeDirectFetchUri(currentUri)) {
        _logDirectFetchBlocked(currentUri);
        return null;
      }

      if (!await isDirectFetchDnsSafe(currentUri)) {
        _logDirectFetchBlocked(currentUri);
        return null;
      }

      final request = http.Request("GET", currentUri)
        ..headers.addAll(headers)
        ..followRedirects = false;
      final response = await client.send(request).timeout(_requestTimeout);

      if (!_isRedirectStatus(response.statusCode)) {
        return (uri: currentUri, response: response);
      }

      final location = response.headers["location"];
      await response.stream.drain<void>();
      final redirectUri = _resolveUrl(location, currentUri);
      if (redirectUri == null) {
        return null;
      }

      if (!isSafeDirectFetchUri(redirectUri)) {
        _logDirectFetchBlocked(redirectUri);
        return null;
      }

      currentUri = redirectUri;
    }

    return null;
  }

  static bool _isRedirectStatus(int statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 303 ||
        statusCode == 307 ||
        statusCode == 308;
  }

  static Map<String, String> _extractMetaTags(dom.Document document) {
    final metadata = <String, String>{};

    for (final meta in document.getElementsByTagName("meta")) {
      final key = _firstNonEmpty([
        meta.attributes["property"],
        meta.attributes["name"],
        meta.attributes["itemprop"],
      ])?.toLowerCase();
      final content = normalizeUrlPreviewText(meta.attributes["content"]);

      if (key != null && content != null && !metadata.containsKey(key)) {
        metadata[key] = content;
      }
    }

    return metadata;
  }

  static String? _extractCanonicalLink(dom.Document document) {
    final canonical = document.querySelector('link[rel="canonical"]');
    return canonical?.attributes["href"];
  }

  static String? _extractJsonLdValue(dom.Document document, String key) {
    for (final script in document.querySelectorAll(
      'script[type="application/ld+json"]',
    )) {
      final raw = script.text.trim();
      if (raw.isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(raw);
        final result = _findJsonLdValue(decoded, key);
        if (result != null) {
          return result;
        }
      } catch (_) {
        continue;
      }
    }

    return null;
  }

  static String? _findJsonLdValue(dynamic value, String key) {
    if (value is Map<String, dynamic>) {
      final direct = normalizeUrlPreviewText(_stringValue(value[key]));
      if (direct != null) {
        return direct;
      }

      for (final child in value.values) {
        final nested = _findJsonLdValue(child, key);
        if (nested != null) {
          return nested;
        }
      }
    }

    if (value is List) {
      for (final child in value) {
        final nested = _findJsonLdValue(child, key);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  static String? _extractTikTokDescription(
    dom.Document? document,
    Map<String, String> metadata,
    String? title,
  ) {
    return _firstNonEmpty([
      metadata["og:description"],
      metadata["twitter:description"],
      _extractMatch(document?.outerHtml, [
        RegExp(r'"desc":"((?:\\.|[^"])*)"'),
      ])?.replaceAll(r"\/", "/"),
      title,
    ]);
  }

  static String? _buildStatsFromFreeText(
    String? value, {
    DateTime? publishedAt,
  }) {
    final likes = _extractInt(value, [
      RegExp(r"(\d[\d.,]*\s*[KMBkmb]?)\s+likes?", caseSensitive: false),
    ], allowCompactSuffixes: true);
    final comments = _extractInt(value, [
      RegExp(r"(\d[\d.,]*\s*[KMBkmb]?)\s+comments?", caseSensitive: false),
    ], allowCompactSuffixes: true);
    return buildUrlPreviewStatsLine(
      likes: likes,
      comments: comments,
      publishedAt: publishedAt,
    );
  }

  static int? _extractInt(
    String? value,
    List<RegExp> patterns, {
    bool allowCompactSuffixes = false,
  }) {
    if (value == null) {
      return null;
    }

    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final raw = match?.group(1);
      if (raw == null) {
        continue;
      }

      final parsed = allowCompactSuffixes
          ? _parseCompactNumber(raw)
          : int.tryParse(raw);
      if (parsed != null) {
        return parsed;
      }
    }

    return null;
  }

  static String? _extractMatch(String? value, List<RegExp> patterns) {
    if (value == null) {
      return null;
    }

    for (final pattern in patterns) {
      final match = pattern.firstMatch(value);
      final result = normalizeUrlPreviewText(match?.group(1));
      if (result != null) {
        return result;
      }
    }

    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null) {
      return null;
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final epoch = int.tryParse(trimmed);
    if (epoch != null) {
      if (trimmed.length >= 13) {
        return DateTime.fromMillisecondsSinceEpoch(epoch);
      }

      return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
    }

    return DateTime.tryParse(trimmed);
  }

  static int? _parseCompactNumber(String value) {
    final normalized = value.replaceAll(",", "").trim();
    final match = RegExp(
      r"^(\d+(?:\.\d+)?)\s*([KMBkmb])?$",
    ).firstMatch(normalized);
    if (match == null) {
      return int.tryParse(normalized);
    }

    final amount = double.tryParse(match.group(1) ?? "");
    if (amount == null) {
      return null;
    }

    final suffix = (match.group(2) ?? "").toUpperCase();
    final multiplier = switch (suffix) {
      "K" => 1000,
      "M" => 1000000,
      "B" => 1000000000,
      _ => 1,
    };

    return (amount * multiplier).round();
  }

  static Uri? _resolveUrl(String? value, Uri baseUri) {
    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      return Uri.parse(value).hasScheme
          ? Uri.parse(value)
          : baseUri.resolve(value);
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _browserHeaders({
    String? accept,
    String? userAgent,
  }) {
    final headers = <String, String>{
      "User-Agent": userAgent ?? _browserUserAgent,
      "Accept-Language": "en-US,en;q=0.9",
      "Accept":
          accept ??
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    };

    return headers;
  }

  static bool _isTikTok(Uri uri) {
    final host = uri.host.replaceFirst(
      RegExp(r"^www\.", caseSensitive: false),
      "",
    );
    return host == "tiktok.com" || host.endsWith(".tiktok.com");
  }

  static bool _isInstagram(Uri uri) {
    final host = uri.host.replaceFirst(
      RegExp(r"^www\.", caseSensitive: false),
      "",
    );
    return host == "instagram.com" || host.endsWith(".instagram.com");
  }

  static bool _isReddit(Uri uri) {
    final host = uri.host.replaceFirst(
      RegExp(r"^www\.", caseSensitive: false),
      "",
    );
    return host == "redd.it" ||
        host == "reddit.com" ||
        host.endsWith(".reddit.com");
  }

  static bool _isHttpUri(Uri uri) {
    return uri.scheme == "http" || uri.scheme == "https";
  }

  static String? _normalizedHost(Uri uri) {
    var host = uri.host.trim().toLowerCase();
    if (host.isEmpty) {
      return null;
    }

    if (host.startsWith("[") && host.endsWith("]") && host.length > 2) {
      host = host.substring(1, host.length - 1);
    }

    final zoneIndex = host.indexOf("%");
    if (zoneIndex > 0) {
      host = host.substring(0, zoneIndex);
    }

    return host;
  }

  static bool _isPrivateIpv4Host(String host) {
    final parts = host.split(".");
    if (parts.length != 4) {
      return false;
    }

    final octets = <int>[];
    for (final part in parts) {
      if (!RegExp(r"^\d+$").hasMatch(part)) {
        return false;
      }

      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return false;
      }
      octets.add(octet);
    }

    final first = octets[0];
    final second = octets[1];
    final third = octets[2];

    return first == 0 ||
        first == 10 ||
        first == 127 ||
        (first == 100 && second >= 64 && second <= 127) ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168) ||
        (first == 192 && second == 0) ||
        (first == 192 && second == 0 && third == 2) ||
        (first == 198 && (second == 18 || second == 19)) ||
        (first == 198 && second == 51 && third == 100) ||
        (first == 203 && second == 0 && third == 113) ||
        first >= 224;
  }

  static bool _isPrivateIpv6Host(String host) {
    if (!host.contains(":")) {
      return false;
    }

    if (host == "::" ||
        host == "::1" ||
        host == "0:0:0:0:0:0:0:0" ||
        host == "0:0:0:0:0:0:0:1") {
      return true;
    }

    if (host.contains(".")) {
      final ipv4Tail = host.substring(host.lastIndexOf(":") + 1);
      if (_isPrivateIpv4Host(ipv4Tail)) {
        return true;
      }
    }

    final firstHextet = host
        .split(":")
        .firstWhere((part) => part.isNotEmpty, orElse: () => "0");
    final first = int.tryParse(firstHextet, radix: 16);
    if (first == null) {
      return false;
    }

    return (first & 0xfe00) == 0xfc00 ||
        (first & 0xffc0) == 0xfe80 ||
        (first & 0xff00) == 0xff00;
  }

  static void _logDirectFetchBlocked(Uri uri) {
    Log.d(
      'Blocked direct URL preview fallback for host ${uri.host}',
      category: LogCategory.media,
      source: 'url-preview',
    );
  }

  static String? _extractTikTokUsername(Uri uri) {
    final match = RegExp(r"/(@[^/]+)/").firstMatch(uri.path);
    return match?.group(1);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = normalizeUrlPreviewText(value);
      if (normalized != null) {
        return normalized;
      }
    }

    return null;
  }

  static String? _stringValue(Object? value) {
    return value is String ? value : null;
  }

  static int? _toPositiveInt(String? value) {
    if (value == null) {
      return null;
    }

    final parsed = int.tryParse(value);
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static int? _positiveIntValue(Object? value) {
    if (value is num && value > 0) {
      return value.round();
    }

    if (value is String) {
      return _toPositiveInt(value);
    }

    return null;
  }

  static String _fallbackInstagramTitle(Uri uri) {
    final path = uri.path.toLowerCase();
    if (path.startsWith("/reel/") || path.startsWith("/reels/")) {
      return "Instagram reel";
    }
    if (path.startsWith("/tv/")) {
      return "Instagram video";
    }
    return "Instagram post";
  }

  static ({String kind, String shortcode})? _parseInstagramPermalink(Uri uri) {
    final match = RegExp(r"^/(p|reel|reels|tv)/([^/?#]+)").firstMatch(uri.path);
    if (match?.groupCount != 2) {
      return null;
    }

    final kind = match!.group(1);
    final shortcode = match.group(2);
    if (kind == null || shortcode == null) {
      return null;
    }

    return (kind: kind, shortcode: shortcode);
  }

  static Future<List<String>> _fetchInstagramHtmlSources(
    Uri uri,
    ({String kind, String shortcode})? permalink,
  ) async {
    final htmlSources = <String>{};
    final mainHtml = await _fetchHtml(uri);
    if (mainHtml != null) {
      htmlSources.add(mainHtml);
    }

    if (permalink != null) {
      for (final embedUri in [
        Uri.parse(
          "https://www.instagram.com/${permalink.kind}/${permalink.shortcode}/embed/captioned/",
        ),
        Uri.parse(
          "https://www.instagram.com/${permalink.kind}/${permalink.shortcode}/embed/",
        ),
      ]) {
        final html = await _fetchHtml(embedUri);
        if (html != null) {
          htmlSources.add(html);
        }
      }
    }

    return htmlSources.toList();
  }

  static Future<String?> _fetchHtml(Uri uri) async {
    try {
      final response = await _fetchResponse(uri, headers: _browserHeaders());
      if (response == null ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        return null;
      }

      return response.body;
    } catch (_) {
      return null;
    }
  }

  static List<String> _extractInstagramImageCandidates(String html) {
    final candidates = <String>{};
    final patterns = [
      RegExp(
        r'"(?:display_url|thumbnail_src|thumbnail_url|display_src|image_url|video_poster_url|poster_url|thumbnail_url_with_fallback)":"((?:\\.|[^"\\])+?)"',
        caseSensitive: false,
      ),
      RegExp(
        r'"src":"((?:https?:)?\\\/\\\/[^"]+?\.(?:jpg|jpeg|png|webp)(?:\\u[0-9a-fA-F]{4}|\\\/|[^"])*)"',
        caseSensitive: false,
      ),
    ];

    for (final pattern in patterns) {
      for (final match in pattern.allMatches(html)) {
        final raw = match.group(1);
        if (raw == null) {
          continue;
        }

        final decoded = _decodeInstagramEscapedUrl(raw);
        if (decoded != null && decoded.startsWith("http")) {
          candidates.add(decoded);
        }

        if (candidates.length >= 12) {
          return candidates.toList();
        }
      }
    }

    return candidates.toList();
  }

  static String? _decodeInstagramEscapedUrl(String value) {
    final normalized = value
        .replaceAll(r"\u0026", "&")
        .replaceAll(r"\u002F", "/")
        .replaceAll(r"\/", "/")
        .replaceAll(r'\"', '"')
        .trim();

    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith("//")) {
      return "https:$normalized";
    }

    return normalized;
  }

  static Future<Map<String, dynamic>?> _fetchRedditPost(Uri uri) async {
    final jsonUri = _buildRedditJsonUri(uri);

    try {
      final response = await http
          .get(
            jsonUri,
            headers: _browserHeaders(
              accept: "application/json",
              userAgent: "matrix-bot/1.0",
            ),
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) {
        return null;
      }

      final root = decoded.first;
      if (root is! Map<String, dynamic>) {
        return null;
      }

      final data = root["data"];
      if (data is! Map<String, dynamic>) {
        return null;
      }

      final children = data["children"];
      if (children is! List || children.isEmpty) {
        return null;
      }

      final child = children.first;
      if (child is! Map<String, dynamic>) {
        return null;
      }

      final post = child["data"];
      return post is Map<String, dynamic> ? post : null;
    } catch (_) {
      return null;
    }
  }

  static Uri _buildRedditJsonUri(Uri uri) {
    final host = uri.host.replaceFirst(
      RegExp(r"^www\.", caseSensitive: false),
      "",
    );
    if (host == "redd.it") {
      final postId = uri.pathSegments
          .where((segment) => segment.isNotEmpty)
          .join();
      return Uri.parse(
        "https://www.reddit.com/comments/$postId.json?raw_json=1",
      );
    }

    final path = uri.path.replaceFirst(RegExp(r"/+$"), "");
    return Uri.parse("https://www.reddit.com$path.json?raw_json=1");
  }

  static String? _pickRedditImageUrl(Map<String, dynamic>? post) {
    if (post == null) {
      return null;
    }

    final preview = post["preview"];
    if (preview is Map<String, dynamic>) {
      final images = preview["images"];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map<String, dynamic>) {
          final source = first["source"];
          if (source is Map<String, dynamic>) {
            final candidate = _sanitizeRedditImageUrl(
              _stringValue(source["url"]),
            );
            if (candidate != null) {
              return candidate;
            }
          }
        }
      }

      final redditVideoPreview = preview["reddit_video_preview"];
      if (redditVideoPreview is Map<String, dynamic>) {
        final thumbnail = _sanitizeRedditImageUrl(
          _stringValue(redditVideoPreview["thumbnail_url"]),
        );
        if (thumbnail != null) {
          return thumbnail;
        }
      }
    }

    final mediaMetadata = post["media_metadata"];
    if (mediaMetadata is Map<String, dynamic>) {
      for (final value in mediaMetadata.values) {
        if (value is! Map<String, dynamic>) {
          continue;
        }

        final source = value["s"];
        if (source is! Map<String, dynamic>) {
          continue;
        }

        final candidate = _sanitizeRedditImageUrl(
          _stringValue(source["u"]) ?? _stringValue(source["gif"]),
        );
        if (candidate != null) {
          return candidate;
        }
      }
    }

    final crossPostList = post["crosspost_parent_list"];
    if (crossPostList is List) {
      for (final item in crossPostList) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final candidate = _pickRedditImageUrl(item);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    for (final key in ["url_overridden_by_dest", "url", "thumbnail"]) {
      final candidate = _sanitizeRedditImageUrl(_stringValue(post[key]));
      if (candidate != null) {
        return candidate;
      }
    }

    return null;
  }

  static int? _pickRedditImageDimension(
    Map<String, dynamic>? post,
    String axis,
  ) {
    if (post == null) {
      return null;
    }

    final preview = post["preview"];
    if (preview is Map<String, dynamic>) {
      final images = preview["images"];
      if (images is List && images.isNotEmpty) {
        final first = images.first;
        if (first is Map<String, dynamic>) {
          final source = first["source"];
          if (source is Map<String, dynamic>) {
            final value = source[axis];
            if (value is num && value > 0) {
              return value.round();
            }
          }
        }
      }

      final redditVideoPreview = preview["reddit_video_preview"];
      if (redditVideoPreview is Map<String, dynamic>) {
        final value = redditVideoPreview[axis];
        if (value is num && value > 0) {
          return value.round();
        }
      }
    }

    final mediaMetadata = post["media_metadata"];
    if (mediaMetadata is Map<String, dynamic>) {
      for (final value in mediaMetadata.values) {
        if (value is! Map<String, dynamic>) {
          continue;
        }

        final source = value["s"];
        if (source is! Map<String, dynamic>) {
          continue;
        }

        final candidate = source[axis == "width" ? "x" : "y"];
        if (candidate is num && candidate > 0) {
          return candidate.round();
        }
      }
    }

    final crossPostList = post["crosspost_parent_list"];
    if (crossPostList is List) {
      for (final item in crossPostList) {
        if (item is! Map<String, dynamic>) {
          continue;
        }

        final candidate = _pickRedditImageDimension(item, axis);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    final fallback = post["thumbnail_$axis"];
    if (fallback is num && fallback > 0) {
      return fallback.round();
    }

    return null;
  }

  static String? _sanitizeRedditImageUrl(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim();
    final lower = normalized.toLowerCase();
    if (lower.isEmpty ||
        lower == "self" ||
        lower == "default" ||
        lower == "spoiler" ||
        lower == "nsfw" ||
        lower == "image") {
      return null;
    }

    final decoded = normalized.replaceAll("&amp;", "&");
    if (!decoded.startsWith("http")) {
      return null;
    }

    final uri = Uri.tryParse(decoded);
    if (uri == null) {
      return null;
    }

    if (uri.host.toLowerCase().contains("redditstatic.com")) {
      return null;
    }

    return decoded;
  }

  static String? _normalizeSubreddit(String? subreddit) {
    if (subreddit == null) {
      return null;
    }

    return subreddit.startsWith("r/") ? subreddit : "r/$subreddit";
  }

  static Future<(int, int)?> _decodeImageDimensions(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final dimensions = (image.width, image.height);
      image.dispose();
      codec.dispose();
      return dimensions;
    } catch (_) {
      return null;
    }
  }
}

class _FetchedPreviewImage {
  const _FetchedPreviewImage({
    required this.provider,
    required this.uri,
    this.width,
    this.height,
  });

  final ImageProvider provider;
  final Uri uri;
  final int? width;
  final int? height;
}
