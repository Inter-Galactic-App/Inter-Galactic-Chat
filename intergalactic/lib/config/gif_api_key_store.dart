import 'dart:async';

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/integration_defaults.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/config/preferences/string_preference.dart';

class GifApiKeyStore {
  static const String preferenceKey = "gif_search.klipy_api_key";
  static const String relayPreferenceKey = "gif_search.relay_base_url";

  static final NullableStringPreference _apiKeyPreference =
      NullableStringPreference(preferenceKey, defaultValue: null);
  static final NullableStringPreference _relayBaseUrlPreference =
      NullableStringPreference(relayPreferenceKey, defaultValue: null);
  static final NullableStringPreference _lastBuildRelayBaseUrlPreference =
      NullableStringPreference(
    Preferences.gifSearchLastBuildRelayBaseUrlKey,
    defaultValue: null,
  );

  static String? get apiKey => _normalize(_apiKeyPreference.value);

  static bool get hasApiKey => apiKey != null;

  static String? get savedRelayBaseUrl =>
      normalizeGifRelayBaseUrl(_relayBaseUrlPreference.value);

  static String? get bundledRelayBaseUrl =>
      normalizeGifRelayBaseUrl(BuildConfig.GIF_API_BASE_URL);

  static String? get preservedRelayBaseUrl =>
      normalizeGifRelayBaseUrl(_lastBuildRelayBaseUrlPreference.value);

  static String? get relayBaseUrl => resolveGifRelayBaseUrl(
        saved: _relayBaseUrlPreference.value,
        bundled: BuildConfig.GIF_API_BASE_URL,
        preserved: _lastBuildRelayBaseUrlPreference.value,
      );

  static bool get hasSavedRelayBaseUrl => savedRelayBaseUrl != null;

  static bool get hasBundledRelayBaseUrl => bundledRelayBaseUrl != null;

  static bool get hasPreservedRelayBaseUrl => preservedRelayBaseUrl != null;

  static bool get hasRelayBaseUrl => relayBaseUrl != null;

  static bool get hasSearchProvider => hasRelayBaseUrl || hasApiKey;

  static Stream<String?> get onChanged =>
      _apiKeyPreference.onChanged.map(_normalize);

  static Stream<String?> get onRelayChanged =>
      _relayBaseUrlPreference.onChanged.map(normalizeGifRelayBaseUrl);

  static Future<void> setApiKey(String value) async {
    await _apiKeyPreference.set(_normalize(value));
  }

  static Future<void> clearApiKey() async {
    await _apiKeyPreference.set(null);
  }

  static Future<void> setRelayBaseUrl(String value) async {
    final normalized = normalizeGifRelayBaseUrl(value);
    if (normalized == null) {
      throw const FormatException("Enter a valid http or https GIF relay URL.");
    }

    await _relayBaseUrlPreference.set(normalized);
  }

  static Future<void> clearRelayBaseUrl() async {
    await _relayBaseUrlPreference.set(null);
    await _lastBuildRelayBaseUrlPreference.set(null);
  }

  static String get statusLabel {
    final key = apiKey;
    if (key == null) {
      return "No API key saved";
    }

    final suffix = key.length <= 4 ? key : key.substring(key.length - 4);
    return "Saved key ending in $suffix";
  }

  static String get providerStatusLabel {
    final savedRelay = savedRelayBaseUrl;
    if (savedRelay != null) {
      return "Using saved relay $savedRelay";
    }

    final bundledRelay = bundledRelayBaseUrl;
    if (bundledRelay != null) {
      return "Using relay configured for this build";
    }

    final preservedRelay = preservedRelayBaseUrl;
    if (preservedRelay != null) {
      return "Using relay preserved from previous build";
    }

    final key = apiKey;
    if (key != null) {
      return statusLabel;
    }

    return "No relay or API key configured";
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }

    return trimmed;
  }

  static String? normalizeRelayBaseUrl(String? value) =>
      normalizeGifRelayBaseUrl(value);
}
