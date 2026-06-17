import 'package:intergalactic/client/components/activity/sources/spotify/spotify_auth.dart';
import 'package:intergalactic/config/build_config.dart';

String effectiveIntegrationValue({
  String? stored,
  required String bundled,
  String? preserved,
}) {
  for (final value in [stored, bundled, preserved]) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
  }

  return "";
}

SpotifyAuthConfig resolveSpotifyAuthConfig({
  String? storedClientId,
  String? storedRedirectUri,
  String bundledClientId = BuildConfig.SPOTIFY_CLIENT_ID,
  String bundledRedirectUri = BuildConfig.SPOTIFY_REDIRECT_URI,
  String? preservedClientId,
  String? preservedRedirectUri,
}) {
  return SpotifyAuthConfig(
    clientId: effectiveIntegrationValue(
      stored: storedClientId,
      bundled: bundledClientId,
      preserved: preservedClientId,
    ),
    redirectUri: effectiveIntegrationValue(
      stored: storedRedirectUri,
      bundled: bundledRedirectUri,
      preserved: preservedRedirectUri,
    ),
  );
}

String resolveSteamActivityApiBaseUrl({
  String bundled = BuildConfig.STEAM_ACTIVITY_API_BASE_URL,
  String? preserved,
}) {
  return effectiveIntegrationValue(
    bundled: bundled,
    preserved: preserved,
  );
}

String? normalizeGifRelayBaseUrl(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.scheme != "https" && uri.scheme != "http")) {
    return null;
  }

  var path = uri.path;
  while (path.endsWith("/") && path.length > 1) {
    path = path.substring(0, path.length - 1);
  }
  if (path == "/") {
    path = "";
  }

  return uri.replace(path: path, query: null, fragment: null).toString();
}

String? resolveGifRelayBaseUrl({
  String? saved,
  String? bundled = BuildConfig.GIF_API_BASE_URL,
  String? preserved,
}) {
  return normalizeGifRelayBaseUrl(saved) ??
      normalizeGifRelayBaseUrl(bundled) ??
      normalizeGifRelayBaseUrl(preserved);
}
