import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intl/intl.dart';

String? normalizeUrlPreviewText(String? value) {
  if (value == null) return null;

  final normalized = value.replaceAll(RegExp(r"\s+"), " ").trim();
  return normalized.isEmpty ? null : normalized;
}

String? trimUrlPreviewDescription(String? value, {int maxWords = 20}) {
  final normalized = normalizeUrlPreviewText(value);
  if (normalized == null) return null;

  final words = normalized.split(" ");
  if (words.length <= maxWords) {
    return normalized;
  }

  return "${words.take(maxWords).join(" ")}...";
}

String inferUrlPreviewSource(Uri uri) {
  final host = uri.host.replaceFirst(
    RegExp(r"^www\.", caseSensitive: false),
    "",
  );
  if (host.isEmpty) {
    return uri.toString();
  }

  final parts = host.split(".");
  final label = parts.length >= 2 ? parts[parts.length - 2] : parts.first;
  if (label.toLowerCase() == 'tiktok') return 'TikTok';
  final words = label.split(RegExp(r"[-_]+"));
  return words
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(" ");
}

String? normalizeUrlPreviewPostingAccount(String? value) {
  final normalized = normalizeUrlPreviewText(value);
  if (normalized == null) {
    return null;
  }

  final withoutByPrefix = normalized.replaceFirst(
    RegExp(r"^by\s+", caseSensitive: false),
    "",
  );

  // A handle with no name behind it - a bare "@" - is what several providers
  // return when the author is unknown, and TikTok's metadata does it often. It
  // rendered on the card as a stray "@" beside the site name, which is the
  // owner's original 2026-09-03 report. Carrying no name, it is absent rather
  // than short.
  //
  // The test is for any letter or digit in the UNICODE sense, not [A-Za-z0-9]:
  // handles are routinely non-Latin and an ASCII-only check would silently
  // discard them.
  if (!RegExp(r"[\p{L}\p{N}]", unicode: true).hasMatch(withoutByPrefix)) {
    return null;
  }

  return withoutByPrefix;
}

UrlPreviewData? sanitizeUrlPreviewDataForUri(Uri uri, UrlPreviewData? data) {
  if (data == null) {
    return data;
  }

  if (_isBlockedBrowserErrorPreview(data)) {
    return null;
  }

  if (!isTikTokPreviewUri(uri)) {
    return data;
  }

  final postingAccount = normalizeUrlPreviewPostingAccount(data.postingAccount);
  final stats = normalizeUrlPreviewText(data.stats);
  final sanitizedTitle = _isGenericTikTokTitle(data.title)
      ? null
      : normalizeUrlPreviewText(data.title);
  final sanitizedDescription = _isGenericTikTokDescription(data.description)
      ? null
      : normalizeUrlPreviewText(data.description);

  if (sanitizedTitle == data.title &&
      sanitizedDescription == data.description) {
    return data;
  }

  if (postingAccount == null &&
      stats == null &&
      sanitizedTitle == null &&
      sanitizedDescription == null &&
      data.image == null) {
    return null;
  }

  return UrlPreviewData(
    data.uri,
    siteName: data.siteName,
    title: sanitizedTitle,
    description: sanitizedDescription,
    image: data.image,
    imageUri: data.imageUri,
    imageWidth: data.imageWidth,
    imageHeight: data.imageHeight,
    postingAccount: data.postingAccount,
    stats: data.stats,
    volatileImageOmitted: data.volatileImageOmitted,
  );
}

bool isTikTokPreviewUri(Uri uri) {
  return _isTikTokPreviewUri(uri);
}

bool isDurableUrlPreviewImageUri(Uri uri) {
  return !isVolatileUrlPreviewImageUri(uri);
}

bool isVolatileUrlPreviewImageUri(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != "http" && scheme != "https") {
    return false;
  }

  final host = uri.host.toLowerCase();
  if (!_isTransientSocialImageHost(host)) {
    return false;
  }

  return uri.queryParametersAll.keys.any(_isVolatileImageQueryName);
}

String? buildUrlPreviewStatsLine({
  int? likes,
  int? comments,
  DateTime? publishedAt,
}) {
  final compact = NumberFormat.compact();
  final parts = <String>[];

  if (likes != null && likes > 0) {
    parts.add("${compact.format(likes)} likes");
  }

  if (comments != null && comments > 0) {
    parts.add("${compact.format(comments)} comments");
  }

  if (publishedAt != null) {
    parts.add("on ${DateFormat.yMMMMd().format(publishedAt)}");
  }

  if (parts.isEmpty) {
    return null;
  }

  if (parts.length >= 3) {
    return "${parts[0]}, ${parts[1]} ${parts[2]}";
  }

  return parts.join(", ");
}

int urlPreviewCompletenessScore(UrlPreviewData? data) {
  if (data == null) return 0;

  var score = 0;
  if (normalizeUrlPreviewText(data.siteName) != null) score += 2;
  if (normalizeUrlPreviewText(data.postingAccount) != null) score += 2;
  if (normalizeUrlPreviewText(data.stats) != null) score += 2;
  if (normalizeUrlPreviewText(data.title) != null) score += 1;
  if (normalizeUrlPreviewText(data.description) != null) score += 2;
  if (data.image != null) score += 2;
  return score;
}

UrlPreviewData? mergeUrlPreviewData(
  UrlPreviewData? primary,
  UrlPreviewData? secondary, {
  bool preferSecondary = false,
}) {
  if (primary == null) return secondary;
  if (secondary == null) return primary;

  final base = preferSecondary ? secondary : primary;
  final fallback = preferSecondary ? primary : secondary;

  return base.copyWith(
    uri: base.uri,
    siteName: base.siteName ?? fallback.siteName,
    title: base.title ?? fallback.title,
    description: base.description ?? fallback.description,
    image: base.image ?? fallback.image,
    imageUri: base.imageUri ?? fallback.imageUri,
    imageWidth: base.imageWidth ?? fallback.imageWidth,
    imageHeight: base.imageHeight ?? fallback.imageHeight,
    postingAccount: base.postingAccount ?? fallback.postingAccount,
    stats: base.stats ?? fallback.stats,
    volatileImageOmitted:
        base.volatileImageOmitted || fallback.volatileImageOmitted,
  );
}

bool _isTikTokPreviewUri(Uri uri) {
  final host = uri.host
      .replaceFirst(RegExp(r"^www\.", caseSensitive: false), "")
      .toLowerCase();
  return host == "tiktok.com" || host.endsWith(".tiktok.com");
}

bool _isTransientSocialImageHost(String host) {
  return host.contains("tiktokcdn") ||
      host.contains("byteoversea") ||
      host.contains("ibyteimg") ||
      host.contains("ibytedtos") ||
      host == "cdninstagram.com" ||
      host.endsWith(".cdninstagram.com") ||
      host == "fbcdn.net" ||
      host.endsWith(".fbcdn.net") ||
      host.startsWith("scontent-") &&
          (host.contains(".cdninstagram.com") || host.contains(".fbcdn.net"));
}

bool _isVolatileImageQueryName(String name) {
  final normalized = name.toLowerCase().replaceAll("-", "_");
  return normalized == "x_signature" ||
      normalized == "x_expires" ||
      normalized == "signature" ||
      normalized == "sig" ||
      normalized == "expires" ||
      normalized == "oh" ||
      normalized == "oe" ||
      normalized == "edm" ||
      normalized == "ccb" ||
      normalized == "stp" ||
      normalized == "idc" ||
      normalized == "shp" ||
      normalized == "shcp" ||
      normalized.startsWith("_nc_");
}

bool _isBlockedBrowserErrorPreview(UrlPreviewData data) {
  final siteName = _normalizedComparisonText(data.siteName);
  final title = _normalizedComparisonText(data.title);
  final description = _normalizedComparisonText(data.description);
  final previewFields = <String?>[siteName, title, description];

  final hasExplicitBrowserBlockSignal = previewFields.any(
    (value) =>
        value != null &&
        (value.contains("err_blocked_by_response") ||
            value.contains("blocked by response") ||
            value.contains("refused to connect")),
  );
  if (hasExplicitBrowserBlockSignal) {
    return true;
  }

  final titleLooksLikeBlockedShell =
      title != null && RegExp(r"^[0-9a-f-]{8,}\s+is blocked$").hasMatch(title);
  final descriptionLooksLikeBlockedShell =
      description != null && description.contains("refused to connect");

  return titleLooksLikeBlockedShell && descriptionLooksLikeBlockedShell;
}

bool _isGenericTikTokTitle(String? value) {
  final normalized = _normalizedComparisonText(value);
  if (normalized == null) {
    return false;
  }

  return normalized == "make your day" ||
      normalized == "tiktok - make your day" ||
      normalized == "tiktok | make your day" ||
      normalized == "tiktok";
}

bool _isGenericTikTokDescription(String? value) {
  final normalized = _normalizedComparisonText(value);
  if (normalized == null) {
    return false;
  }

  if (_isGenericTikTokTitle(normalized)) {
    return true;
  }

  return normalized.contains("trends start here") ||
      normalized.contains("on a device or on the web") ||
      normalized.contains(
        "watch and discover millions of personalized short videos",
      ) ||
      normalized.contains("discover videos, music and livestreams") ||
      normalized.contains("create your own with easy-to-use tools") ||
      normalized.contains("global video community");
}

String? _normalizedComparisonText(String? value) {
  return normalizeUrlPreviewText(value)?.toLowerCase();
}
