import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences/bool_preference.dart';
import 'package:intergalactic/config/preferences/double_preference.dart';
import 'package:intergalactic/config/preferences/int_preference.dart';
import 'package:intergalactic/config/preferences/preference.dart';
import 'package:intergalactic/config/preferences/string_preference.dart';
import 'package:intergalactic/config/theme_config.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/shortcut_binding.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_amoled.dart';
import 'package:tiamat/config/style/theme_aurora.dart';
import 'package:tiamat/config/style/theme_cosmic_stardust.dart';
import 'package:tiamat/config/style/theme_json_converter.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_dark_matter.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/config/style/theme_token_debug.dart';
import 'package:tiamat/config/style/theme_you.dart';

class Preferences {
  SharedPreferences? _preferences;

  static const String registeredMatrixClients = "registered_matrix_clients";

  static const String _pushGateway = "push_gateway";
  static const String _iosLastPushReconcileVersion =
      "ios_last_push_reconcile_version";
  static const String _androidPushTransportMode = "android_push_transport_mode";
  static const String _androidPushTransportFcm = "fcm";
  static const String _androidPushTransportEmbeddedNtfy = "embedded_ntfy";
  static const String notificationPreviewPrivacyChoicePrivate = "private";
  static const String notificationPreviewPrivacyChoiceRich = "rich";
  static const String notificationPreviewPrivacyChoiceCustom = "custom";
  static const String _notificationPreviewPrivacyChoiceCompleted =
      "notification_preview_privacy_choice_completed";
  static const String _notificationPreviewPrivacyChoiceValue =
      "notification_preview_privacy_choice_value";
  static const String _formatNotificationBody = "format_notification_body";
  static const String _showMediaInNotifications = "show_media_in_notifications";
  static const String _previewUrlInNotifications =
      "preview_urls_in_notification";
  static const String _notificationCompanionShowPreviews =
      "notification_companion_show_previews";
  static const String _fcmKey = "fcm_key";
  static const String _unifiedPushEndpoint = "unified_push_endpoint";
  static const String _embeddedNtfyTopic = "embedded_ntfy_topic";
  // Known Commet-era gateway hosts that should migrate to the current
  // Inter Galactic default unless the user has explicitly configured another
  // gateway. Extend this set when another shipped legacy host is confirmed.
  static const Set<String> _legacyCommetPushGatewayHosts = {"push.commet.chat"};

  static const String _optedInExperiments = "opted_in_experiments";

  static const String _syncedCalendarUrls = "synced_calendar_urls";

  static const String _topLevelSpaceOrder = "top_level_space_order";

  static const String _spaceChildOrder = "space_child_order";

  static const String _favoriteRoomIds = "favorite_room_ids";
  static const String _favoritesBannerImageData = "favorites_banner_image_data";
  static const String _favoritesIconImageData = "favorites_icon_image_data";
  static const String _appTheme = "app_theme";
  static const String _checkForUpdates = "check_for_updates";
  static const String _checkForUpdatesDefaultTrueMigration =
      "check_for_updates_default_true_migrated";
  static const String _lastSeenReleaseNotesVersion =
      "last_seen_release_notes_version";
  static const String _voipNoiseSuppressionEnabled =
      "voip_noise_suppression_enabled";
  static const String _voipNoiseSuppressionHookMode =
      "voip_noise_suppression_hook_mode";
  static const String _voipNoiseSuppressionRnnoiseHook = "rnnoise";
  static const String _voipNoiseSuppressionDeepFilterNetHook =
      "enhanced_deepfilternet";
  static const String _deepFilterNetBaselineMigration =
      "voip_deepfilternet_baseline_migrated";
  static const String gifSearchLastBuildRelayBaseUrlKey =
      "gif_search.last_build_relay_base_url";
  static const String activitySpotifyLastBuildClientIdKey =
      "activity_spotify.last_build_client_id";
  static const String activitySpotifyLastBuildRedirectUriKey =
      "activity_spotify.last_build_redirect_uri";
  static const String activitySteamLastBuildApiBaseUrlKey =
      "activity_steam.last_build_api_base_url";
  static const String _dmLockPinMetadata = "dm_lock_pin_metadata";
  static const String _dmLockRoomIds = "dm_lock_room_ids";

  static const String _urlPreviewInE2EEChat = "use_url_preview_in_e2ee_chat";
  static const String _urlPreviewInE2EEChatConsentCompleted =
      "url_preview_in_e2ee_chat_consent_completed";

  static const String _roomMessageBackgrounds = "room_message_backgrounds";
  static const String _messageBackgroundOpacity = "message_background_opacity";
  static const String _roomMessageBackgroundOpacities =
      "room_message_background_opacities";
  static const String _roomMessageBubbleColors = "room_message_bubble_colors";
  static const String _roomSentMessageBubbleColors =
      "room_sent_message_bubble_colors";
  static const String _roomReceivedMessageBubbleColors =
      "room_received_message_bubble_colors";
  static const String _roomNotificationSoundPaths =
      "room_notification_sound_paths";
  static const String _roomNotificationVolumes = "room_notification_volumes";
  static const String _roomNotificationSnoozes = "room_notification_snoozes";
  static const String _screenShareAudioVolumes =
      "voip_screen_share_audio_volumes";

  static const String _systemHotkey = "system_wide_hotkey";
  static const String _customNavigationShortcuts =
      "custom_navigation_shortcuts";

  static const String _matrixDeviceProfiles = "matrix_device_profiles";
  static const String _webSessionBootstrapState = "web_session_bootstrap_state";
  static const String _accountRecoveryPromptDismissals =
      "account_recovery_prompt_dismissals";

  static final StreamController onSettingChangedController =
      StreamController.broadcast();
  Stream get onSettingChanged => onSettingChangedController.stream;
  bool isInit = false;

  Future<void> init() async {
    _preferences = await SharedPreferences.getInstance();
    Preference.preferences = _preferences;
    await _migrateThemeSelection();
    await _migrateCheckForUpdatesDefault();
    await _migrateLegacyPushGateway();
    await _migrateAndroidPushTransportMode();
    await _migrateUrlPreviewE2EEConsentChoice();
    await _migrateNotificationPreviewPrivacyChoice();
    await _migrateWindowsDeepFilterNetBaseline();
    await _rememberBundledIntegrationDefaults();
    isInit = true;
  }

  Future<void> _rememberBundledIntegrationDefaults() async {
    await _rememberNonEmptyBuildDefault(
      gifSearchLastBuildRelayBaseUrlKey,
      BuildConfig.GIF_API_BASE_URL,
    );
    await _rememberNonEmptyBuildDefault(
      activitySpotifyLastBuildClientIdKey,
      BuildConfig.SPOTIFY_CLIENT_ID,
    );
    await _rememberNonEmptyBuildDefault(
      activitySpotifyLastBuildRedirectUriKey,
      BuildConfig.SPOTIFY_REDIRECT_URI,
    );
    await _rememberNonEmptyBuildDefault(
      activitySteamLastBuildApiBaseUrlKey,
      BuildConfig.STEAM_ACTIVITY_API_BASE_URL,
    );
  }

  Future<void> _rememberNonEmptyBuildDefault(String key, String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    await _preferences!.setString(key, trimmed);
  }

  Future<void> _migrateThemeSelection() async {
    final storedTheme = _preferences?.getString(_appTheme);
    if (storedTheme == null) {
      return;
    }

    final trimmedTheme = storedTheme.trim();
    final customThemeId = customThemeIdFromSelection(trimmedTheme);
    var migratedTheme = customThemeId == null
        ? trimmedTheme
        : customThemeSelectionId(customThemeId);

    if (customThemeId == null) {
      final rawCustomTheme = await ThemeConfig.loadThemeByName(trimmedTheme);
      if (rawCustomTheme != null) {
        final normalizedTheme = _normalizeThemeSelectionId(trimmedTheme);
        if (_shouldMigrateBuiltInCollisionToCustom(normalizedTheme) &&
            normalizedTheme == trimmedTheme) {
          migratedTheme = customThemeSelectionId(trimmedTheme);
        }
      } else {
        migratedTheme = _normalizeThemeSelectionId(trimmedTheme);
      }
    }

    if (migratedTheme != storedTheme) {
      await _preferences!.setString(_appTheme, migratedTheme);
    }
  }

  Future<void> _migrateCheckForUpdatesDefault() async {
    if (_preferences?.getBool(_checkForUpdatesDefaultTrueMigration) == true) {
      return;
    }

    if (_preferences?.getBool(_checkForUpdates) != true) {
      await _preferences!.setBool(_checkForUpdates, true);
    }

    await _preferences!.setBool(_checkForUpdatesDefaultTrueMigration, true);
  }

  Future<void> _migrateWindowsDeepFilterNetBaseline() async {
    final prefs = _preferences;
    if (prefs == null || !PlatformUtils.isWindows) {
      return;
    }

    if (prefs.getBool(_deepFilterNetBaselineMigration) == true) {
      return;
    }

    final existingHookMode = prefs.getString(_voipNoiseSuppressionHookMode);
    if (existingHookMode == null ||
        existingHookMode.trim().isEmpty ||
        existingHookMode == _voipNoiseSuppressionRnnoiseHook) {
      await prefs.setString(
        _voipNoiseSuppressionHookMode,
        _voipNoiseSuppressionDeepFilterNetHook,
      );
    }

    if (!prefs.containsKey(_voipNoiseSuppressionEnabled)) {
      await prefs.setBool(_voipNoiseSuppressionEnabled, true);
    }

    await prefs.setBool(_deepFilterNetBaselineMigration, true);
  }

  Future<void> _migrateLegacyPushGateway() async {
    if (!(PlatformUtils.isAndroid || PlatformUtils.isWeb)) {
      return;
    }

    final storedGateway = _preferences?.getString(_pushGateway);
    if (storedGateway == null || storedGateway.isEmpty) {
      return;
    }

    if (!_isLegacyCommetPushGateway(storedGateway)) {
      return;
    }

    if (_shouldReplaceStoredPushGateway(storedGateway)) {
      await _preferences!.setString(
        _pushGateway,
        BuildConfig.androidPushGatewayHost,
      );
    }
  }

  Future<void> _migrateAndroidPushTransportMode() async {
    if (!PlatformUtils.isAndroid) {
      return;
    }

    final expectedTransport = BuildConfig.ENABLE_GOOGLE_SERVICES
        ? _androidPushTransportFcm
        : _androidPushTransportEmbeddedNtfy;
    final storedTransport = _preferences?.getString(_androidPushTransportMode);

    if (storedTransport == expectedTransport) {
      return;
    }

    if (_shouldReplaceStoredPushGateway(
      _preferences?.getString(_pushGateway),
    )) {
      await _preferences!.setString(
        _pushGateway,
        BuildConfig.androidPushGatewayHost,
      );
    }

    // Keep alternate transport credentials during migration. The active
    // notifier refreshes its own token/topic after startup, and retaining the
    // inactive values avoids orphaning subscriptions if the user or build
    // switches back before the new transport is confirmed working.
    await _preferences!.setString(_androidPushTransportMode, expectedTransport);
  }

  Future<void> _migrateNotificationPreviewPrivacyChoice() async {
    final prefs = _preferences;
    if (prefs == null) {
      return;
    }

    if (prefs.getBool(_notificationPreviewPrivacyChoiceCompleted) == true) {
      return;
    }

    final hasConfiguredPreviewPreferences = <String>{
      _formatNotificationBody,
      _showMediaInNotifications,
      _previewUrlInNotifications,
      _notificationCompanionShowPreviews,
    }.any(prefs.containsKey);

    final hasExistingAccountState = prefs.containsKey(registeredMatrixClients);

    if (!hasConfiguredPreviewPreferences && !hasExistingAccountState) {
      return;
    }

    await prefs.setString(
      _notificationPreviewPrivacyChoiceValue,
      hasConfiguredPreviewPreferences
          ? notificationPreviewPrivacyChoiceCustom
          : notificationPreviewPrivacyChoiceRich,
    );
    await prefs.setBool(_notificationPreviewPrivacyChoiceCompleted, true);
  }

  Future<void> _migrateUrlPreviewE2EEConsentChoice() async {
    final prefs = _preferences;
    if (prefs == null) {
      return;
    }

    if (prefs.getBool(_urlPreviewInE2EEChatConsentCompleted) == true) {
      return;
    }

    final hasExistingUrlPreviewPreference = prefs.containsKey(
      _urlPreviewInE2EEChat,
    );
    final hasExistingAccountState = prefs.containsKey(registeredMatrixClients);

    if (!hasExistingUrlPreviewPreference && !hasExistingAccountState) {
      return;
    }

    if (!hasExistingUrlPreviewPreference) {
      await prefs.setBool(_urlPreviewInE2EEChat, true);
    }

    await prefs.setBool(_urlPreviewInE2EEChatConsentCompleted, true);
  }

  String _normalizePushGatewayHost(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return trimmed;
    }

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.host.isNotEmpty) {
      return parsed.host.toLowerCase();
    }

    return trimmed
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .toLowerCase();
  }

  bool _isLegacyCommetPushGateway(String value) {
    return _legacyCommetPushGatewayHosts.contains(
      _normalizePushGatewayHost(value),
    );
  }

  bool _shouldReplaceStoredPushGateway(String? value) {
    if (value == null || value.trim().isEmpty) {
      return true;
    }

    if (_isLegacyCommetPushGateway(value)) {
      return true;
    }

    return _normalizePushGatewayHost(value) ==
        _normalizePushGatewayHost(BuildConfig.androidPushGatewayHost);
  }

  List<String>? getRegisteredMatrixClients() {
    if (_preferences!.containsKey(registeredMatrixClients)) {
      return _preferences!.getStringList(registeredMatrixClients);
    }

    return null;
  }

  Future<void> setRegisteredMatrixClients(List<String> names) async {
    final sanitized = <String>[];
    for (final name in names) {
      if (name.isEmpty || sanitized.contains(name)) {
        continue;
      }
      sanitized.add(name);
    }

    await _preferences!.setStringList(registeredMatrixClients, sanitized);
  }

  void addRegisteredMatrixClient(String name) {
    final names = List<String>.from(
      getRegisteredMatrixClients() ?? const <String>[],
      growable: true,
    );
    if (!names.contains(name)) {
      names.add(name);
    }

    unawaited(setRegisteredMatrixClients(names));
  }

  void removeRegisteredMatrixClient(String name) {
    final names = List<String>.from(
      getRegisteredMatrixClients() ?? const <String>[],
      growable: true,
    )..removeWhere((entry) => entry == name);

    unawaited(setRegisteredMatrixClients(names));
  }

  String _knockedRoomsKey(String clientId) => 'knocked_room_ids.$clientId';

  /// Room ids [clientId] has an outstanding knock on. Persisted so the
  /// resulting invite can be auto-accepted even across an app restart and
  /// regardless of sync timing. Scoped per client so one account's prune does
  /// not clear another account's outstanding knock.
  List<String> getKnockedRoomIds(String clientId) {
    return _preferences!.getStringList(_knockedRoomsKey(clientId)) ??
        const <String>[];
  }

  Future<void> setKnockedRoomIds(
    String clientId,
    Iterable<String> roomIds,
  ) async {
    final sanitized = <String>[];
    for (final roomId in roomIds) {
      if (roomId.isEmpty || sanitized.contains(roomId)) {
        continue;
      }
      sanitized.add(roomId);
    }

    final key = _knockedRoomsKey(clientId);
    if (sanitized.isEmpty) {
      await _preferences!.remove(key);
    } else {
      await _preferences!.setStringList(key, sanitized);
    }
  }

  Future<void> addKnockedRoomId(String clientId, String roomId) async {
    if (roomId.isEmpty) {
      return;
    }
    final roomIds = List<String>.from(getKnockedRoomIds(clientId));
    if (roomIds.contains(roomId)) {
      return;
    }
    roomIds.add(roomId);
    await setKnockedRoomIds(clientId, roomIds);
  }

  Future<void> removeKnockedRoomId(String clientId, String roomId) async {
    final roomIds = List<String>.from(getKnockedRoomIds(clientId))
      ..removeWhere((entry) => entry == roomId);
    await setKnockedRoomIds(clientId, roomIds);
  }

  Map<String, dynamic> _normalizeJsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return {};
  }

  Map<String, dynamic> getMatrixDeviceProfiles() {
    final raw = _preferences!.getString(_matrixDeviceProfiles);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> setMatrixDeviceProfile(
    String key,
    Map<String, dynamic> profile,
  ) async {
    final profiles = getMatrixDeviceProfiles();
    profiles[key] = profile;
    await _preferences!.setString(_matrixDeviceProfiles, jsonEncode(profiles));
  }

  Map<String, dynamic>? getMatrixDeviceProfile(String key) {
    final profiles = getMatrixDeviceProfiles();
    final profile = profiles[key];
    if (profile == null) {
      return null;
    }

    final normalized = _normalizeJsonMap(profile);
    return normalized.isEmpty ? null : normalized;
  }

  List<Map<String, dynamic>> getMatrixDeviceProfilesForHomeserver(
    String homeserver,
  ) {
    final normalizedHomeserver = homeserver.toLowerCase();
    return getMatrixDeviceProfiles().values
        .map((entry) => _normalizeJsonMap(entry))
        .where(
          (entry) =>
              (entry['homeserver'] as String?)?.toLowerCase() ==
              normalizedHomeserver,
        )
        .toList();
  }

  Future<void> removeMatrixDeviceProfilesForClient(String clientName) async {
    final profiles = getMatrixDeviceProfiles();
    final keysToRemove = <String>[];

    for (final entry in profiles.entries) {
      final profile = _normalizeJsonMap(entry.value);
      if (profile['clientName'] == clientName) {
        keysToRemove.add(entry.key);
      }
    }

    if (keysToRemove.isEmpty) {
      return;
    }

    for (final key in keysToRemove) {
      profiles.remove(key);
    }

    await _preferences!.setString(_matrixDeviceProfiles, jsonEncode(profiles));
  }

  Map<String, dynamic>? getWebSessionBootstrapState() {
    final raw = _preferences!.getString(_webSessionBootstrapState);
    if (raw == null || raw.isEmpty) {
      return null;
    }

    try {
      final normalized = _normalizeJsonMap(jsonDecode(raw));
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  Future<void> setWebSessionBootstrapState(Map<String, dynamic> state) async {
    await _preferences!.setString(_webSessionBootstrapState, jsonEncode(state));
  }

  Future<void> clearWebSessionBootstrapState() async {
    await _preferences!.remove(_webSessionBootstrapState);
  }

  Map<String, dynamic> getAccountRecoveryPromptDismissals() {
    final raw = _preferences!.getString(_accountRecoveryPromptDismissals);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  bool isAccountRecoveryPromptDismissed(String promptKey) {
    if (promptKey.trim().isEmpty) {
      return false;
    }
    return getAccountRecoveryPromptDismissals().containsKey(promptKey);
  }

  Future<void> setAccountRecoveryPromptDismissed(
    String promptKey,
    bool dismissed,
  ) async {
    if (promptKey.trim().isEmpty) {
      return;
    }

    final dismissals = getAccountRecoveryPromptDismissals();
    if (dismissed) {
      dismissals[promptKey] = {
        'dismissed_at': DateTime.now().toUtc().toIso8601String(),
      };
    } else {
      dismissals.remove(promptKey);
    }

    if (dismissals.isEmpty) {
      await _preferences!.remove(_accountRecoveryPromptDismissals);
    } else {
      await _preferences!.setString(
        _accountRecoveryPromptDismissals,
        jsonEncode(dismissals),
      );
    }
  }

  Future<ThemeData> resolveTheme({Brightness? overrideBrightness}) async {
    if (overrideBrightness == null && shouldFollowSystemTheme.value) {
      overrideBrightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
    }

    // Custom selections are namespaced so future built-ins can reuse readable
    // IDs without taking over an existing user-created theme.
    // Bundled themes are stored by ID prefix "bundled:<name>" and loaded from
    // the app asset bundle rather than the custom-themes directory.
    final rawThemeId = theme.value.trim();
    final customThemeId = customThemeIdFromSelection(rawThemeId);
    if (customThemeId != null) {
      final customTheme = await _resolveCustomTheme(customThemeId);
      if (customTheme != null) {
        return customTheme;
      }
    }

    if (customThemeId == null && !_isBuiltInThemeId(rawThemeId)) {
      final customTheme = await _resolveCustomTheme(rawThemeId);
      if (customTheme != null) {
        return customTheme;
      }
    }

    final themeId = _normalizeThemeSelectionId(rawThemeId);

    if (themeId.startsWith('bundled:')) {
      final assetName = _bundledThemeAssetName(themeId);
      if (assetName != null) {
        try {
          final raw = await rootBundle.loadString(
            'assets/themes/$assetName.json',
          );
          final json = const JsonDecoder().convert(raw);
          if (json is Map<String, dynamic>) {
            final themeData = await ThemeJsonConverter.fromJson(json, null);
            if (themeData != null) return themeData;
          }
        } catch (_) {
          // Fall through to built-in defaults if asset is missing.
        }
      }
    }

    if (!_isBuiltInThemeId(themeId)) {
      final customTheme = await _resolveCustomTheme(themeId);
      if (customTheme != null) {
        return customTheme;
      }
    }

    if (themeId == "theme_token_debug") {
      return ThemeTokenDebug.theme;
    }

    if (overrideBrightness == null && shouldFollowSystemColors.value) {
      if (themeId == "dark_matter" ||
          themeId == "dark" ||
          themeId == "aurora" ||
          themeId == "cosmic_stardust") {
        overrideBrightness = Brightness.dark;
      }

      if (themeId == "light") {
        overrideBrightness = Brightness.light;
      }
    }

    if (overrideBrightness != null && shouldFollowSystemColors.value) {
      return ThemeYou.theme(overrideBrightness);
    }

    if (overrideBrightness == Brightness.dark) {
      return switch (themeId) {
        "dark_matter" => ThemeDarkMatter.theme,
        "dark" => ThemeDark.theme,
        "amoled" => ThemeAmoled.theme,
        "aurora" => ThemeAurora.theme,
        "cosmic_stardust" => ThemeCosmicStardust.theme,
        "theme_token_debug" => ThemeTokenDebug.theme,
        _ => ThemeDarkMatter.theme,
      };
    }

    if (overrideBrightness == Brightness.light) {
      return ThemeLight.theme;
    }

    return switch (themeId) {
      "light" => ThemeLight.theme,
      "dark_matter" => ThemeDarkMatter.theme,
      "dark" => ThemeDark.theme,
      "amoled" => ThemeAmoled.theme,
      "aurora" => ThemeAurora.theme,
      "cosmic_stardust" => ThemeCosmicStardust.theme,
      "theme_token_debug" => ThemeTokenDebug.theme,
      _ => ThemeDarkMatter.theme,
    };
  }

  static const String _customThemeSelectionPrefix = 'custom:';

  static String customThemeSelectionId(String themeId) {
    return '$_customThemeSelectionPrefix${themeId.trim()}';
  }

  static String? customThemeIdFromSelection(String themeId) {
    final trimmed = themeId.trim();
    if (!trimmed.startsWith(_customThemeSelectionPrefix)) {
      return null;
    }

    final customThemeId = trimmed.substring(_customThemeSelectionPrefix.length);
    return customThemeId.isEmpty ? null : customThemeId;
  }

  Future<ThemeData?> _resolveCustomTheme(String themeId) async {
    final customTheme = await ThemeConfig.loadThemeByName(themeId);
    if (customTheme == null) {
      return null;
    }

    final customThemeFile = !PlatformUtils.isWeb
        ? await ThemeConfig.getThemeByName(themeId)
        : null;
    return ThemeJsonConverter.fromJson(customTheme.json, customThemeFile);
  }

  static String _normalizeThemeSelectionId(String themeId) {
    final trimmed = themeId.trim();
    final customThemeId = customThemeIdFromSelection(trimmed);
    if (customThemeId != null) {
      return customThemeSelectionId(customThemeId);
    }

    final rawId = trimmed.startsWith('bundled:')
        ? trimmed.substring('bundled:'.length)
        : trimmed;
    final normalized = rawId.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

    return switch (normalized) {
      'classic_light' || 'sol' || 'light' => 'light',
      'dark_matter' => 'dark_matter',
      'classic_dark' || 'nebula' || 'dark' => 'dark',
      'arnoled' || 'amoled' || 'eclipse' => 'amoled',
      'aurora' => 'aurora',
      'cosmic_stardust' => 'cosmic_stardust',
      'theme_token_debug' ||
      'token_debug' ||
      'debug_tokens' => 'theme_token_debug',
      'jedi' || 'light_side' || 'grand_master' => 'bundled:jedi',
      'sith' || 'dark_side' || 'dark_lord' => 'bundled:sith',
      _ => trimmed,
    };
  }

  static bool _isBuiltInThemeId(String themeId) {
    return switch (themeId) {
      'light' ||
      'dark_matter' ||
      'dark' ||
      'amoled' ||
      'aurora' ||
      'cosmic_stardust' ||
      'theme_token_debug' => true,
      _ => false,
    };
  }

  static bool isBuiltInThemeSelectionId(String themeId) {
    return _isBuiltInThemeId(_normalizeThemeSelectionId(themeId));
  }

  static bool matchesCustomThemeSelection(
    String activeThemeId,
    String themeId,
  ) {
    final trimmedThemeId = themeId.trim();
    return activeThemeId == customThemeSelectionId(trimmedThemeId) ||
        (activeThemeId == trimmedThemeId && !_isBuiltInThemeId(trimmedThemeId));
  }

  static bool _shouldMigrateBuiltInCollisionToCustom(String themeId) {
    return switch (themeId) {
      'dark_matter' || 'cosmic_stardust' => true,
      _ => false,
    };
  }

  static String _normalizeBundledThemeId(String themeId) {
    return _normalizeThemeSelectionId(themeId);
  }

  static String? _bundledThemeAssetName(String themeId) {
    final normalizedThemeId = _normalizeBundledThemeId(themeId);
    if (!normalizedThemeId.startsWith('bundled:')) {
      return null;
    }

    final assetName = normalizedThemeId.substring('bundled:'.length);
    if (assetName == 'jedi' || assetName == 'sith') {
      return assetName;
    }

    return null;
  }

  Future<void> clear() async {
    await _preferences!.clear();
  }

  Future<void> setPushGateway(String value) async {
    await _preferences!.setString(_pushGateway, value);
  }

  String get pushGateway {
    const defaultGateway = BuildConfig.androidPushGatewayHost;

    final storedGateway = _preferences!.getString(_pushGateway);
    if (storedGateway == null || storedGateway.trim().isEmpty) {
      return defaultGateway;
    }

    if ((PlatformUtils.isAndroid || PlatformUtils.isWeb) &&
        _isLegacyCommetPushGateway(storedGateway)) {
      return BuildConfig.androidPushGatewayHost;
    }

    return storedGateway;
  }

  /// The app `VERSION_TAG` for which the iOS APNs pusher was last successfully
  /// reconciled with the homeserver. Used to force a one-time pusher refresh
  /// after an app update, because iOS can rotate the APNs device token on
  /// update and leave the previously registered pusher pointing at a dead
  /// token until the user manually refreshes notifications.
  String? get iosLastPushReconcileVersion =>
      _preferences?.getString(_iosLastPushReconcileVersion);

  Future<void> setIosLastPushReconcileVersion(String value) async {
    await _preferences!.setString(_iosLastPushReconcileVersion, value);
  }

  Future<void> setExperimentEnabled(String experiment, bool value) async {
    var experiments =
        _preferences?.getStringList(_optedInExperiments) ??
        List.empty(growable: true);

    if (value) {
      if (experiments.contains(experiment) == false) {
        experiments.add(experiment);
      }
    } else {
      experiments.removeWhere((e) => e == experiment);
    }

    await _preferences!.setStringList(_optedInExperiments, experiments);
  }

  bool isExperimentEnabled(String experiment) {
    return _preferences
            ?.getStringList(_optedInExperiments)
            ?.contains(experiment) ==
        true;
  }

  Map<String, dynamic> getCalendarSources(String roomId) {
    var content = _preferences!.getString(_syncedCalendarUrls + ".${roomId}");
    if (content != null) {
      return jsonDecode(content);
    } else {
      return {};
    }
  }

  Future<void> setCalendarSources(String roomId, Map<String, dynamic> sources) {
    return _preferences!.setString(
      _syncedCalendarUrls + ".${roomId}",
      jsonEncode(sources),
    );
  }

  String getSpaceChildOrderKey(String spaceId) {
    return "$_spaceChildOrder.$spaceId";
  }

  List<String> getTopLevelSpaceOrder() {
    return _preferences?.getStringList(_topLevelSpaceOrder) ?? const [];
  }

  Future<void> setTopLevelSpaceOrder(List<String> spaceIds) async {
    await _preferences!.setStringList(_topLevelSpaceOrder, spaceIds);
    onSettingChangedController.add(null);
  }

  List<String> getSpaceChildOrder(String spaceId) {
    return _preferences?.getStringList(getSpaceChildOrderKey(spaceId)) ??
        const [];
  }

  Future<void> setSpaceChildOrder(String spaceId, List<String> childIds) async {
    await _preferences!.setStringList(getSpaceChildOrderKey(spaceId), childIds);
    onSettingChangedController.add(null);
  }

  static const String _sidebarRoomOrder = "sidebar_room_order";

  List<String> getSidebarRoomOrder() {
    return _preferences?.getStringList(_sidebarRoomOrder) ?? const [];
  }

  Future<void> setSidebarRoomOrder(List<String> roomIds) async {
    await _preferences!.setStringList(_sidebarRoomOrder, roomIds);
    onSettingChangedController.add(null);
  }

  List<String> getFavoriteRoomIds() {
    return _preferences?.getStringList(_favoriteRoomIds) ?? const [];
  }

  bool isRoomFavorite(String roomId, {String? legacyRoomId}) {
    final favorites = getFavoriteRoomIds();
    return favorites.contains(roomId) ||
        (legacyRoomId != null && favorites.contains(legacyRoomId));
  }

  Future<void> setRoomFavorite(
    String roomId,
    bool favorite, {
    String? legacyRoomId,
  }) async {
    final favorites = List<String>.from(getFavoriteRoomIds(), growable: true);
    final legacyIds = {
      if (legacyRoomId != null && legacyRoomId != roomId) legacyRoomId,
    };

    if (favorite) {
      favorites.removeWhere(legacyIds.contains);
      if (!favorites.contains(roomId)) {
        favorites.add(roomId);
      }
    } else {
      favorites.removeWhere((id) => id == roomId || legacyIds.contains(id));
    }

    await _preferences!.setStringList(_favoriteRoomIds, favorites);
    onSettingChangedController.add(null);
  }

  Future<void> setFavoriteRoomOrder(List<String> roomIds) async {
    final current = getFavoriteRoomIds();
    final currentSet = current.toSet();
    final seen = <String>{};
    final ordered = <String>[
      for (final id in roomIds)
        if (currentSet.contains(id) && seen.add(id)) id,
      for (final id in current)
        if (seen.add(id)) id,
    ];

    await _preferences!.setStringList(_favoriteRoomIds, ordered);
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> getDmLockPinMetadata() {
    final raw = _preferences?.getString(_dmLockPinMetadata);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> setDmLockPinMetadata(Map<String, dynamic> value) async {
    await _preferences!.setString(_dmLockPinMetadata, jsonEncode(value));
    onSettingChangedController.add(null);
  }

  List<String> getDmLockRoomIds() {
    return _preferences?.getStringList(_dmLockRoomIds) ?? const [];
  }

  Future<void> setDmLockRoomIds(List<String> roomIds) async {
    await _preferences!.setStringList(_dmLockRoomIds, roomIds);
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> getRoomMessageBackgrounds() {
    final raw = _preferences!.getString(_roomMessageBackgrounds);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  String? getRoomMessageBackgroundPath(String roomLocalId) {
    final value = getRoomMessageBackgrounds()[roomLocalId];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<void> setRoomMessageBackgroundPath(
    String roomLocalId,
    String? path,
  ) async {
    final backgrounds = getRoomMessageBackgrounds();
    if (path == null || path.trim().isEmpty) {
      backgrounds.remove(roomLocalId);
    } else {
      backgrounds[roomLocalId] = path;
    }

    await _preferences!.setString(
      _roomMessageBackgrounds,
      jsonEncode(backgrounds),
    );
    onSettingChangedController.add(null);
  }

  double getDefaultMessageBackgroundOpacity() {
    final stored = _preferences!.getDouble(_messageBackgroundOpacity);
    if (stored != null) {
      return stored.clamp(0.0, 1.0).toDouble();
    }

    return bubbleMessages.value ? 1.0 : 0.45;
  }

  Future<void> setDefaultMessageBackgroundOpacity(double value) async {
    await _preferences!.setDouble(
      _messageBackgroundOpacity,
      value.clamp(0.0, 1.0).toDouble(),
    );
    onSettingChangedController.add(null);
  }

  Future<void> clearDefaultMessageBackgroundOpacity() async {
    await _preferences!.remove(_messageBackgroundOpacity);
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> getRoomMessageBackgroundOpacities() {
    final raw = _preferences!.getString(_roomMessageBackgroundOpacities);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  double? getRoomMessageBackgroundOpacity(String roomLocalId) {
    final value = getRoomMessageBackgroundOpacities()[roomLocalId];
    if (value is num) {
      return value.clamp(0.0, 1.0).toDouble();
    }
    if (value is String) {
      final parsed = double.tryParse(value);
      return parsed?.clamp(0.0, 1.0).toDouble();
    }
    return null;
  }

  double getEffectiveMessageBackgroundOpacity(String roomLocalId) {
    return getRoomMessageBackgroundOpacity(roomLocalId) ??
        getDefaultMessageBackgroundOpacity();
  }

  Future<void> setRoomMessageBackgroundOpacity(
    String roomLocalId,
    double? value,
  ) async {
    final opacities = getRoomMessageBackgroundOpacities();
    if (value == null) {
      opacities.remove(roomLocalId);
    } else {
      opacities[roomLocalId] = value.clamp(0.0, 1.0).toDouble();
    }

    await _preferences!.setString(
      _roomMessageBackgroundOpacities,
      jsonEncode(opacities),
    );
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> getRoomMessageBubbleColors() {
    final raw = _preferences!.getString(_roomMessageBubbleColors);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  String? getRoomMessageBubbleColor(String roomLocalId) {
    final value = getRoomMessageBubbleColors()[roomLocalId];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Map<String, dynamic> _getRoomMessageBubbleColorMap(String key) {
    final raw = _preferences!.getString(key);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  String? _getRoomMessageBubbleColorValue(String key, String roomLocalId) {
    final value = _getRoomMessageBubbleColorMap(key)[roomLocalId];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<void> _setRoomMessageBubbleColorValue(
    String key,
    String roomLocalId,
    String? hexColor,
  ) async {
    final colors = _getRoomMessageBubbleColorMap(key);
    if (hexColor == null || hexColor.trim().isEmpty) {
      colors.remove(roomLocalId);
    } else {
      colors[roomLocalId] = hexColor;
    }

    await _preferences!.setString(key, jsonEncode(colors));
    onSettingChangedController.add(null);
  }

  String? getRoomSentMessageBubbleColor(String roomLocalId) {
    return _getRoomMessageBubbleColorValue(
      _roomSentMessageBubbleColors,
      roomLocalId,
    );
  }

  String? getRoomReceivedMessageBubbleColor(String roomLocalId) {
    return _getRoomMessageBubbleColorValue(
      _roomReceivedMessageBubbleColors,
      roomLocalId,
    );
  }

  String? getEffectiveSentMessageBubbleColor(String? roomLocalId) {
    if (roomLocalId != null) {
      final roomColor =
          getRoomSentMessageBubbleColor(roomLocalId) ??
          getRoomMessageBubbleColor(roomLocalId);
      if (roomColor != null) {
        return roomColor;
      }
    }
    return sentMessageBubbleColor.value ?? messageBubbleColor.value;
  }

  String? getEffectiveReceivedMessageBubbleColor(String? roomLocalId) {
    if (roomLocalId != null) {
      final roomColor =
          getRoomReceivedMessageBubbleColor(roomLocalId) ??
          getRoomMessageBubbleColor(roomLocalId);
      if (roomColor != null) {
        return roomColor;
      }
    }
    return receivedMessageBubbleColor.value ?? messageBubbleColor.value;
  }

  Future<void> setRoomMessageBubbleColor(
    String roomLocalId,
    String? hexColor,
  ) async {
    final colors = getRoomMessageBubbleColors();
    if (hexColor == null || hexColor.trim().isEmpty) {
      colors.remove(roomLocalId);
    } else {
      colors[roomLocalId] = hexColor;
    }

    await _preferences!.setString(_roomMessageBubbleColors, jsonEncode(colors));
    onSettingChangedController.add(null);
  }

  Future<void> setRoomSentMessageBubbleColor(
    String roomLocalId,
    String? hexColor,
  ) async {
    await _setRoomMessageBubbleColorValue(
      _roomSentMessageBubbleColors,
      roomLocalId,
      hexColor,
    );
  }

  Future<void> setRoomReceivedMessageBubbleColor(
    String roomLocalId,
    String? hexColor,
  ) async {
    await _setRoomMessageBubbleColorValue(
      _roomReceivedMessageBubbleColors,
      roomLocalId,
      hexColor,
    );
  }

  Map<String, dynamic> getRoomNotificationSoundPaths() {
    final raw = _preferences!.getString(_roomNotificationSoundPaths);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  String? getRoomNotificationSoundPath(String roomLocalId) {
    final value = getRoomNotificationSoundPaths()[roomLocalId];
    return value is String && value.trim().isNotEmpty ? value : null;
  }

  Future<void> setRoomNotificationSoundPath(
    String roomLocalId,
    String? soundPath,
  ) async {
    final sounds = getRoomNotificationSoundPaths();
    if (soundPath == null || soundPath.trim().isEmpty) {
      sounds.remove(roomLocalId);
    } else {
      sounds[roomLocalId] = soundPath;
    }

    await _preferences!.setString(
      _roomNotificationSoundPaths,
      jsonEncode(sounds),
    );
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> getRoomNotificationVolumes() {
    final raw = _preferences!.getString(_roomNotificationVolumes);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  double? getRoomNotificationVolume(String roomLocalId) {
    final value = getRoomNotificationVolumes()[roomLocalId];
    if (value is num) {
      return value.toDouble().clamp(0, 150).toDouble();
    }

    return null;
  }

  double getEffectiveRoomNotificationVolume(String? roomLocalId) {
    if (roomLocalId == null) {
      return notificationsVolume.value;
    }

    return getRoomNotificationVolume(roomLocalId) ?? notificationsVolume.value;
  }

  Future<void> setRoomNotificationVolume(
    String roomLocalId,
    double? volume,
  ) async {
    final volumes = getRoomNotificationVolumes();
    if (volume == null) {
      volumes.remove(roomLocalId);
    } else {
      volumes[roomLocalId] = volume.clamp(0, 150).toDouble();
    }

    await _preferences!.setString(
      _roomNotificationVolumes,
      jsonEncode(volumes),
    );
    onSettingChangedController.add(null);
  }

  Map<String, dynamic> _getRoomNotificationSnoozeData() {
    final raw = _preferences!.getString(_roomNotificationSnoozes);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  Future<void> _setRoomNotificationSnoozeData(
    Map<String, dynamic> snoozes,
  ) async {
    if (snoozes.isEmpty) {
      await _preferences!.remove(_roomNotificationSnoozes);
    } else {
      await _preferences!.setString(
        _roomNotificationSnoozes,
        jsonEncode(snoozes),
      );
    }
    onSettingChangedController.add(null);
  }

  Map<String, RoomNotificationSnooze> getRoomNotificationSnoozes({
    DateTime? now,
    bool includeExpired = false,
  }) {
    final currentTime = now ?? DateTime.now();
    final values = <String, RoomNotificationSnooze>{};
    final data = _getRoomNotificationSnoozeData();

    for (final entry in data.entries) {
      final snooze = RoomNotificationSnooze.fromJson(entry.value);
      if (snooze == null) {
        continue;
      }
      if (!includeExpired && !snooze.isActive(currentTime)) {
        continue;
      }

      values[entry.key] = snooze;
    }

    return values;
  }

  RoomNotificationSnooze? getRoomNotificationSnooze({
    required String clientId,
    required String roomId,
    DateTime? now,
  }) {
    final key = roomNotificationSnoozeKey(clientId: clientId, roomId: roomId);
    return getRoomNotificationSnoozes(now: now)[key];
  }

  bool isRoomNotificationSnoozed({
    required String clientId,
    required String roomId,
    DateTime? now,
  }) {
    return getRoomNotificationSnooze(
          clientId: clientId,
          roomId: roomId,
          now: now,
        ) !=
        null;
  }

  Future<void> setRoomNotificationSnooze({
    required String clientId,
    required String roomId,
    required Duration duration,
    String source = 'settings',
    DateTime? now,
  }) async {
    final currentTime = now ?? DateTime.now();
    await setRoomNotificationSnoozeUntil(
      clientId: clientId,
      roomId: roomId,
      snoozedUntil: currentTime.add(duration),
      createdAt: currentTime,
      source: source,
    );
  }

  Future<void> setRoomNotificationSnoozeUntil({
    required String clientId,
    required String roomId,
    required DateTime snoozedUntil,
    DateTime? createdAt,
    String source = 'settings',
  }) async {
    final data = _getRoomNotificationSnoozeData();
    final currentTime = createdAt ?? DateTime.now();
    final key = roomNotificationSnoozeKey(clientId: clientId, roomId: roomId);
    data[key] = RoomNotificationSnooze(
      clientId: clientId,
      roomId: roomId,
      snoozedUntil: snoozedUntil,
      createdAt: currentTime,
      source: source,
    ).toJson();

    await _setRoomNotificationSnoozeData(data);
  }

  Future<void> clearRoomNotificationSnooze({
    required String clientId,
    required String roomId,
  }) async {
    final data = _getRoomNotificationSnoozeData();
    data.remove(roomNotificationSnoozeKey(clientId: clientId, roomId: roomId));
    await _setRoomNotificationSnoozeData(data);
  }

  Future<void> pruneExpiredRoomNotificationSnoozes({DateTime? now}) async {
    final currentTime = now ?? DateTime.now();
    final data = _getRoomNotificationSnoozeData();
    var changed = false;

    for (final entry in data.entries.toList(growable: false)) {
      final snooze = RoomNotificationSnooze.fromJson(entry.value);
      if (snooze == null || !snooze.isActive(currentTime)) {
        data.remove(entry.key);
        changed = true;
      }
    }

    if (changed) {
      await _setRoomNotificationSnoozeData(data);
    }
  }

  bool get shouldShowNotificationPreviewPrivacyChoice {
    return notificationPreviewPrivacyChoiceCompleted.value == false;
  }

  bool get usePrivateNotificationPreviews {
    return notificationPreviewPrivacyChoiceValue.value ==
        notificationPreviewPrivacyChoicePrivate;
  }

  bool get shouldShowUrlPreviewE2EEConsentChoice {
    return urlPreviewInE2EEChatConsentCompleted.value == false;
  }

  bool get shouldAllowUrlPreviewInE2EEChat {
    return urlPreviewInE2EEChatConsentCompleted.value &&
        urlPreviewInE2EEChat.value;
  }

  Future<void> applyUrlPreviewE2EEConsentChoice({required bool allow}) async {
    await urlPreviewInE2EEChat.set(allow);
    await urlPreviewInE2EEChatConsentCompleted.set(true);
  }

  Future<void> applyNotificationPreviewPrivacyChoice(String value) async {
    if (value != notificationPreviewPrivacyChoicePrivate &&
        value != notificationPreviewPrivacyChoiceRich &&
        value != notificationPreviewPrivacyChoiceCustom) {
      throw ArgumentError.value(
        value,
        'value',
        'Expected notification preview privacy choice value',
      );
    }

    await notificationPreviewPrivacyChoiceValue.set(value);

    if (value == notificationPreviewPrivacyChoicePrivate) {
      await formatNotificationBody.set(false);
      await showMediaInNotifications.set(false);
      await previewUrlInNotifications.set(false);
      await notificationCompanionShowPreviews.set(false);
    } else if (value == notificationPreviewPrivacyChoiceRich) {
      await formatNotificationBody.set(true);
      await showMediaInNotifications.set(true);
      await previewUrlInNotifications.set(true);
      await notificationCompanionShowPreviews.set(true);
    }

    await notificationPreviewPrivacyChoiceCompleted.set(true);
  }

  static String screenShareAudioVolumeKey({
    required String roomLocalId,
    required String streamUserId,
  }) {
    return '$roomLocalId|$streamUserId|screenshareAudio';
  }

  static double clampScreenShareAudioVolume(double volume) {
    return volume.clamp(0.0, 2.0).toDouble();
  }

  static const double defaultVoipSpeakerVolume = 125.0;
  static const double maxVoipSpeakerVolume = 200.0;

  static double voipSpeakerVolumeToLocalPlayback(double volumePercent) {
    return (volumePercent / 100.0)
        .clamp(0.0, maxVoipSpeakerVolume / 100.0)
        .toDouble();
  }

  Map<String, dynamic> getScreenShareAudioVolumes() {
    final raw = _preferences!.getString(_screenShareAudioVolumes);
    if (raw == null || raw.isEmpty) {
      return {};
    }

    try {
      return _normalizeJsonMap(jsonDecode(raw));
    } catch (_) {
      return {};
    }
  }

  double? getScreenShareAudioVolume({
    required String roomLocalId,
    required String streamUserId,
  }) {
    final key = screenShareAudioVolumeKey(
      roomLocalId: roomLocalId,
      streamUserId: streamUserId,
    );
    final value = getScreenShareAudioVolumes()[key];
    if (value is num) {
      return clampScreenShareAudioVolume(value.toDouble());
    }

    return null;
  }

  Future<void> setScreenShareAudioVolume({
    required String roomLocalId,
    required String streamUserId,
    required double volume,
  }) async {
    final volumes = getScreenShareAudioVolumes();
    final key = screenShareAudioVolumeKey(
      roomLocalId: roomLocalId,
      streamUserId: streamUserId,
    );
    volumes[key] = clampScreenShareAudioVolume(volume);

    await _preferences!.setString(
      _screenShareAudioVolumes,
      jsonEncode(volumes),
    );
    onSettingChangedController.add(null);
  }

  Future<void> removeScreenShareAudioVolume({
    required String roomLocalId,
    required String streamUserId,
  }) async {
    final volumes = getScreenShareAudioVolumes();
    final key = screenShareAudioVolumeKey(
      roomLocalId: roomLocalId,
      streamUserId: streamUserId,
    );
    volumes.remove(key);

    await _preferences!.setString(
      _screenShareAudioVolumes,
      jsonEncode(volumes),
    );
    onSettingChangedController.add(null);
  }

  String getHotkeyId(String name) {
    return _systemHotkey + ".$name";
  }

  Future<void> setSystemHotkey(String name, HotKey? key) async {
    await setSystemShortcutBinding(name, ShortcutBinding.fromHotKey(key));
  }

  Future<void> setSystemShortcutBinding(
    String name,
    ShortcutBinding? binding,
  ) async {
    var k = getHotkeyId(name);

    if (binding == null) {
      await _preferences!.remove(k);
    } else {
      await _preferences!.setString(k, jsonEncode(binding.toJson()));
    }
  }

  HotKey? getSystemHotkey(String name) {
    return getSystemShortcutBinding(name)?.hotKey;
  }

  ShortcutBinding? getSystemShortcutBinding(String name) {
    var item = _preferences!.getString(getHotkeyId(name));
    if (item == null) return null;

    try {
      final decoded = jsonDecode(item);
      if (decoded is! Map) {
        return null;
      }
      return ShortcutBinding.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  List<Map<String, dynamic>> getCustomNavigationShortcuts() {
    final raw = _preferences!.getString(_customNavigationShortcuts);
    if (raw == null || raw.isEmpty) {
      return const [];
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }

      return decoded
          .map(_normalizeJsonMap)
          .where((entry) => entry.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<void> setCustomNavigationShortcuts(
    List<Map<String, dynamic>> shortcuts,
  ) async {
    if (shortcuts.isEmpty) {
      await _preferences!.remove(_customNavigationShortcuts);
    } else {
      await _preferences!.setString(
        _customNavigationShortcuts,
        jsonEncode(shortcuts),
      );
    }
    onSettingChangedController.add(null);
  }

  BoolPreference shouldFollowSystemTheme = BoolPreference(
    "should_follow_system_theme",
    defaultValue: false,
  );

  BoolPreference shouldFollowSystemColors = BoolPreference(
    "should_follow_system_colors",
    defaultValue: false,
  );

  BoolPreference minimizeOnClose = BoolPreference(
    "minimize_on_close",
    defaultValue: false,
  );

  BoolPreference developerMode = BoolPreference(
    "developer_mode",
    defaultValue: false,
  );

  BoolPreference hideDeveloperSettings = BoolPreference(
    "hide_developer_settings",
    defaultValue: false,
  );

  bool get developerUiVisible =>
      developerMode.value && !hideDeveloperSettings.value;

  BoolPreference showTimelineDiagnostics = BoolPreference(
    "show_timeline_diagnostics",
    defaultValue: false,
  );

  BoolPreference iPhonePwaInstallNoticeSeen = BoolPreference(
    "iphone_pwa_install_notice_seen",
    defaultValue: false,
  );

  BoolPreference debugTranslations = BoolPreference(
    "enable_translations_debug",
    defaultValue: false,
  );

  // Keep the legacy storage key so existing installs preserve the user's GIF search setting.
  BoolPreference gifSearchEnabled = BoolPreference(
    "enable_tenor_gif_search",
    defaultValue: true,
  );

  NullableStringPreference gifSearchLastBuildRelayBaseUrl =
      NullableStringPreference(
        gifSearchLastBuildRelayBaseUrlKey,
        defaultValue: null,
      );

  //Workaround for: https://github.com/commetchat/commet/issues/202
  BoolPreference stickerCompatibilityMode = BoolPreference(
    "sticker_compatibility_mode",
    defaultValue: true,
  );

  BoolPreference useFallbackTurnServer = BoolPreference(
    "use_fallback_turn_server",
    defaultValue: false,
  );

  // New installs require an explicit encrypted-room preview choice before
  // fetching. Migration preserves earlier installs that relied on the old
  // enabled-by-default behavior.
  BoolPreference urlPreviewInE2EEChat = BoolPreference(
    _urlPreviewInE2EEChat,
    defaultValue: false,
  );

  BoolPreference urlPreviewInE2EEChatConsentCompleted = BoolPreference(
    _urlPreviewInE2EEChatConsentCompleted,
    defaultValue: false,
  );

  StringPreference matrixKeySharingPolicy = StringPreference(
    "matrix_key_sharing_policy",
    defaultValue: "cross_verified_if_enabled",
  );

  BoolPreference messageEffectsEnabled = BoolPreference(
    "message_effects_enabled",
    defaultValue: true,
  );

  BoolPreference automaticMessageEffectsEnabled = BoolPreference(
    "automatic_message_effects_enabled",
    defaultValue: false,
  );

  BoolPreference bubbleMessages = BoolPreference(
    "bubble_messages",
    defaultValue: false,
  );

  BoolPreference alignSentMessagesRight = BoolPreference(
    "align_sent_messages_right",
    defaultValue: false,
  );

  BoolPreference showRoomAvatars = BoolPreference(
    "show_room_avatars",
    defaultValue: true,
  );

  BoolPreference usePlaceholderRoomAvatars = BoolPreference(
    "use_placeholder_room_avatars",
    defaultValue: false,
  );

  BoolPreference previewMediaInPublicRooms = BoolPreference(
    "preview_media_in_public_rooms",
    defaultValue: true,
  );

  BoolPreference previewMediaInPrivateRooms = BoolPreference(
    "preview_media_in_private_rooms",
    defaultValue: true,
  );

  BoolPreference removePhotoMetadataBeforeSending = BoolPreference(
    "remove_photo_metadata_before_sending",
    defaultValue: true,
  );

  BoolPreference showMediaInNotifications = BoolPreference(
    _showMediaInNotifications,
    defaultValue: true,
  );

  BoolPreference formatNotificationBody = BoolPreference(
    _formatNotificationBody,
    defaultValue: true,
  );

  BoolPreference previewUrlInNotifications = BoolPreference(
    _previewUrlInNotifications,
    defaultValue: true,
  );

  BoolPreference notificationPreviewPrivacyChoiceCompleted = BoolPreference(
    _notificationPreviewPrivacyChoiceCompleted,
    defaultValue: false,
  );

  StringPreference notificationPreviewPrivacyChoiceValue = StringPreference(
    _notificationPreviewPrivacyChoiceValue,
    defaultValue: notificationPreviewPrivacyChoicePrivate,
  );

  BoolPreference useLegacyNotificationHandler = BoolPreference(
    "use_legacy_notification_handler",
    defaultValue: false,
  );

  BoolPreference askBeforeDeletingMessageEnabled = BoolPreference(
    "ask_before_deleting_message_enabled",
    defaultValue: true,
  );

  BoolPreference silenceNotifications = BoolPreference(
    "silence_notifications_when_other_device_active",
    defaultValue: true,
  );

  BoolPreference disableTextCursorManagement = BoolPreference(
    "disable_text_cursor_management",
    defaultValue: false,
  );

  BoolPreference composerBracketTyping = BoolPreference(
    "composer_bracket_typing",
    defaultValue: false,
  );

  BoolPreference hideRoomSidePanel = BoolPreference(
    "hide_room_side_panel",
    defaultValue: false,
  );

  BoolPreference desktopSmallWindowMode = BoolPreference(
    "desktop_small_window_mode",
    defaultValue: false,
  );

  BoolPreference showRoomPreviewsInSpaceSidebar = BoolPreference(
    "show_room_previews_in_space_sidebar",
    defaultValue: true,
  );

  BoolPreference autoFocusMessageTextBox = BoolPreference(
    "auto_focus_message_textbox",
    defaultGetter: () => Layout.mobile ? false : true,
    defaultValue: false,
  );

  BoolPreference automaticallyOpenSpace = BoolPreference(
    "open_space_on_room_navigation",
    defaultValue: true,
  );

  BoolPreference autoRotateImages = BoolPreference(
    "lightbox_rotate_images",
    defaultValue: false,
  );

  BoolPreference autoRotateVideos = BoolPreference(
    "lightbox_rotate_videos",
    defaultValue: false,
  );

  BoolPreference autoSaveUploadedStories = BoolPreference(
    "auto_save_uploaded_stories",
    defaultValue: false,
  );

  BoolPreference autoSaveCapturedMedia = BoolPreference(
    "auto_save_captured_media",
    defaultValue: false,
  );

  DoublePreference textScale = DoublePreference(
    "text_scale",
    defaultValue: 1.0,
  );

  StringPreference accessibilityContrast = StringPreference(
    "accessibility.contrast",
    defaultValue: "system",
  );

  StringPreference accessibilityColor = StringPreference(
    "accessibility.color",
    defaultValue: "system",
  );

  StringPreference accessibilityMotion = StringPreference(
    "accessibility.motion",
    defaultValue: "system",
  );

  StringPreference accessibilityTextSize = StringPreference(
    "accessibility.text_size",
    defaultValue: "system",
  );

  StringPreference accessibilityDifferentiateWithoutColor = StringPreference(
    "accessibility.differentiate_without_color",
    defaultValue: "system",
  );

  StringPreference accessibilityUnderlineLinks = StringPreference(
    "accessibility.underline_links",
    defaultValue: "system",
  );

  StringPreference accessibilityStrongFocusIndicators = StringPreference(
    "accessibility.strong_focus_indicators",
    defaultValue: "system",
  );

  StringPreference accessibilityShowOnOffLabels = StringPreference(
    "accessibility.show_on_off_labels",
    defaultValue: "system",
  );

  StringPreference accessibilityBoldText = StringPreference(
    "accessibility.bold_text",
    defaultValue: "system",
  );

  StringPreference accessibilityReduceTransparency = StringPreference(
    "accessibility.reduce_transparency",
    defaultValue: "system",
  );

  StringPreference accessibilityIncreaseUiSeparation = StringPreference(
    "accessibility.increase_ui_separation",
    defaultValue: "system",
  );

  StringPreference accessibilityPauseAnimatedMedia = StringPreference(
    "accessibility.pause_animated_media",
    defaultValue: "system",
  );

  StringPreference accessibilityLargerTouchTargets = StringPreference(
    "accessibility.larger_touch_targets",
    defaultValue: "system",
  );

  StringPreference accessibilityPersistentActionLabels = StringPreference(
    "accessibility.persistent_action_labels",
    defaultValue: "system",
  );

  BoolPreference doSimulcast = BoolPreference(
    "livekit_use_simulcast",
    defaultValue: true,
  );

  StringPreference screenShareQualityProfile = StringPreference(
    "livekit_screenshare_quality_profile",
    defaultValue: "smooth",
  );

  BoolPreference streamAdvancedOverride = BoolPreference(
    "livekit_screenshare_advanced_override",
    defaultValue: false,
  );

  BoolPreference streamHardwareEncodingFirst = BoolPreference(
    "livekit_screenshare_hardware_encoding_first",
    defaultValue: false,
    defaultGetter: () => PlatformUtils.isWindows,
  );

  BoolPreference streamGpuPipelineTestMode = BoolPreference(
    "livekit_screenshare_gpu_pipeline_test_mode",
    defaultValue: false,
  );

  BoolPreference streamAdaptiveFallbackEnabled = BoolPreference(
    "livekit_screenshare_adaptive_fallback_enabled",
    defaultValue: false,
  );

  BoolPreference showCallStreamStats = BoolPreference(
    "show_call_stream_stats",
    defaultValue: false,
  );

  BoolPreference callStreamStatsOverlayVisible = BoolPreference(
    "call_stream_stats_overlay_visible",
    defaultValue: true,
  );

  BoolPreference offlineDemoLoginEnabled = BoolPreference(
    "offline_demo_login_enabled",
    defaultValue: false,
  );

  BoolPreference onboardingCompleted = BoolPreference(
    "onboarding.completed",
    defaultValue: false,
  );

  IntPreference onboardingVersion = IntPreference(
    "onboarding.version",
    defaultValue: 0,
  );

  NullableStringPreference onboardingCompletedAt = NullableStringPreference(
    "onboarding.completedAt",
    defaultValue: null,
  );

  BoolPreference enableNotifications = BoolPreference(
    "notifications_enabled",
    defaultValue: true,
  );

  StringPreference notificationMode = StringPreference(
    "notification_mode",
    defaultValue: "all",
  );

  BoolPreference suppressNotificationWhenRoomFocused = BoolPreference(
    "suppress_notification_when_room_focused",
    defaultValue: true,
  );

  BoolPreference notificationCompanionEnabled = BoolPreference(
    "notification_companion_enabled",
    defaultValue: false,
  );

  BoolPreference notificationCompanionShowPreviews = BoolPreference(
    _notificationCompanionShowPreviews,
    defaultValue: true,
  );

  BoolPreference notificationCompanionHidePreviewsWhileScreenSharing =
      BoolPreference(
        "notification_companion_hide_previews_while_screen_sharing",
        defaultValue: true,
      );

  BoolPreference notificationCompanionReducedMotion = BoolPreference(
    "notification_companion_reduced_motion",
    defaultValue: false,
  );

  BoolPreference notificationCompanionClickToOpen = BoolPreference(
    "notification_companion_click_to_open",
    defaultValue: true,
  );

  StringPreference notificationCompanionAvatarVariant = StringPreference(
    "notification_companion_avatar_variant",
    defaultValue: "app_icon_light_avatar",
  );

  DoublePreference notificationCompanionWindowX = DoublePreference(
    "notification_companion_window_x",
    defaultValue: 42.0,
  );

  DoublePreference notificationCompanionWindowY = DoublePreference(
    "notification_companion_window_y",
    defaultValue: 84.0,
  );

  DoublePreference notificationsVolume = DoublePreference(
    "notifications_volume",
    defaultValue: 90.0,
  );

  DoublePreference soundboardVolume = DoublePreference(
    "soundboard_volume",
    defaultValue: 100.0,
  );

  NullableStringPreference customNotificationSoundPath =
      NullableStringPreference(
        "custom_notification_sound_path",
        defaultValue: null,
      );

  NullableStringPreference customRingtoneSoundPath = NullableStringPreference(
    "custom_ringtone_sound_path",
    defaultValue: null,
  );

  NullableStringPreference messageBackgroundImagePath =
      NullableStringPreference(
        "message_background_image_path",
        defaultValue: null,
      );

  NullableStringPreference favoritesBannerImageData = NullableStringPreference(
    _favoritesBannerImageData,
    defaultValue: null,
  );

  NullableStringPreference favoritesIconImageData = NullableStringPreference(
    _favoritesIconImageData,
    defaultValue: null,
  );

  NullableStringPreference messageBubbleColor = NullableStringPreference(
    "message_bubble_color",
    defaultValue: null,
  );

  NullableStringPreference sentMessageBubbleColor = NullableStringPreference(
    "sent_message_bubble_color",
    defaultValue: null,
  );

  NullableStringPreference receivedMessageBubbleColor =
      NullableStringPreference(
        "received_message_bubble_color",
        defaultValue: null,
      );

  DoublePreference streamBitrate = DoublePreference(
    "screenshare_bitrate_mbps",
    defaultValue: 2.5,
  );

  DoublePreference streamFramerate = DoublePreference(
    "screenshare_fps",
    defaultValue: 30,
  );

  StringPreference streamCodec = StringPreference(
    "livekit_screenshare_codec",
    defaultValue: "vp8",
  );

  StringPreference streamResolution = StringPreference(
    "livekit_screenshare_resolution",
    defaultValue: "1280x720",
  );

  DoublePreference appScale = DoublePreference("app_scale", defaultValue: 1.0);

  DoublePreference emojiPickerHeight = DoublePreference(
    "emoji_picker_height",
    defaultValue: 300,
  );

  DoublePreference customOnscreenKeyboardViewOffset = DoublePreference(
    "custom_onscreen_keyboard_view_offset",
    defaultValue: 0.0,
  );

  StringPreference proxyUrl = StringPreference(
    "proxy_url",
    defaultValue: "proxy.ourgalaxy.space",
  );

  StringPreference fallbackTurnServer = StringPreference(
    "fallback_turn_server",
    defaultValue: "stun:turn.matrix.org",
  );

  StringPreference theme = StringPreference(
    _appTheme,
    defaultValue: "dark_matter",
  );

  StringPreference appIconMode = StringPreference(
    "app_icon_mode",
    defaultValue: "system",
  );

  NullableBoolPreference unifiedPushEnabled = NullableBoolPreference(
    "unified_push_enabled",
    defaultValue: null,
  );

  NullableBoolPreference checkForUpdates = NullableBoolPreference(
    _checkForUpdates,
    defaultValue: true,
  );

  NullableStringPreference lastSeenReleaseNotesVersion =
      NullableStringPreference(
        _lastSeenReleaseNotesVersion,
        defaultValue: null,
      );

  NullableStringPreference layoutOverride = NullableStringPreference(
    "layout_override",
    defaultValue: null,
  );

  NullableStringPreference voipDefaultAudioInput = NullableStringPreference(
    "voip_default_audio_input",
    defaultValue: null,
  );

  NullableStringPreference voipDefaultAudioOutput = NullableStringPreference(
    "voip_default_audio_output",
    defaultValue: null,
  );

  NullableStringPreference voipDefaultVideoInput = NullableStringPreference(
    "voip_default_video_input",
    defaultValue: null,
  );

  DoublePreference voipMicrophoneVolume = DoublePreference(
    "voip_microphone_volume",
    defaultValue: 100.0,
  );

  DoublePreference voipSpeakerVolume = DoublePreference(
    "voip_speaker_volume",
    defaultValue: defaultVoipSpeakerVolume,
  );

  BoolPreference voipPushToTalkEnabled = BoolPreference(
    "voip_push_to_talk_enabled",
    defaultValue: false,
  );

  /// Whether Windows may attenuate other applications' audio while Inter
  /// Galactic call audio is active. Off by default, so calls do not quietly
  /// turn down whatever else the user is listening to. Windows-only; see
  /// `client/components/voip/audio/windows_call_audio_ducking.dart`.
  BoolPreference voipLowerOtherAppVolumes = BoolPreference(
    "voip_lower_other_app_volumes",
    defaultValue: false,
  );

  BoolPreference voipNoiseSuppressionEnabled = BoolPreference(
    _voipNoiseSuppressionEnabled,
    defaultValue: true,
  );

  BoolPreference voipNoiseSuppressionCompatibilityMode = BoolPreference(
    "voip_noise_suppression_compatibility_mode",
    defaultValue: false,
  );

  StringPreference voipNoiseSuppressionPreset = StringPreference(
    "voip_noise_suppression_preset",
    defaultValue: "balanced",
  );

  DoublePreference voipNoiseSuppressionVadThreshold = DoublePreference(
    "voip_noise_suppression_vad_threshold",
    defaultValue: 0.92,
  );

  DoublePreference voipNoiseSuppressionSpeechGraceMs = DoublePreference(
    "voip_noise_suppression_speech_grace_ms",
    defaultValue: 120.0,
  );

  DoublePreference voipNoiseSuppressionClosedGainPercent = DoublePreference(
    "voip_noise_suppression_closed_gain_percent",
    defaultValue: 1.5,
  );

  DoublePreference voipNoiseSuppressionTransientSensitivity = DoublePreference(
    "voip_noise_suppression_transient_sensitivity",
    defaultValue: 65.0,
  );

  BoolPreference voipNoiseSuppressionDeepFilterNetTransientSuppression =
      BoolPreference(
        "voip_noise_suppression_deepfilternet_transient_suppression",
        defaultValue: false,
      );

  BoolPreference voipNoiseSuppressionDeepFilterNetHushSuppression =
      BoolPreference(
        "voip_noise_suppression_deepfilternet_hush_suppression",
        defaultValue: false,
      );

  BoolPreference voipAudioCaptureDebugOverride = BoolPreference(
    "voip_audio_capture_debug_override",
    defaultValue: false,
  );

  // When enabled on iOS, calls use Apple's native voice-processing audio unit
  // (AVAudioSession `.voiceChat` + WebRTC voice processing) for AEC/NS instead
  // of the historical full bypass. Default off: enabling voice processing was
  // the source of the BUG-168 `setVoiceProcessingEnabled` call-entry crash, so
  // this stays opt-in until device crash-soak validation clears it for default.
  BoolPreference voipIosNativeVoiceProcessing = BoolPreference(
    "voip_ios_native_voice_processing",
    defaultValue: false,
  );

  BoolPreference voipAudioCaptureEchoCancellation = BoolPreference(
    "voip_audio_capture_echo_cancellation",
    defaultValue: true,
  );

  BoolPreference voipAudioCaptureNoiseSuppression = BoolPreference(
    "voip_audio_capture_noise_suppression",
    defaultValue: true,
  );

  /// Only consulted under `developerMode` + `voipAudioCaptureDebugOverride`.
  /// Kept in step with the production default so flipping the override on does
  /// not silently change the capture chain.
  BoolPreference voipAudioCaptureAutoGainControl = BoolPreference(
    "voip_audio_capture_auto_gain_control",
    defaultValue: true,
  );

  BoolPreference voipAudioCaptureHighPassFilter = BoolPreference(
    "voip_audio_capture_high_pass_filter",
    defaultValue: false,
  );

  BoolPreference voipAudioCaptureTypingNoiseDetection = BoolPreference(
    "voip_audio_capture_typing_noise_detection",
    defaultValue: true,
  );

  BoolPreference voipAudioCaptureRequestReferenceFormat = BoolPreference(
    "voip_audio_capture_request_reference_format",
    defaultValue: true,
  );

  BoolPreference voipAudioCaptureVolumeConstraint = BoolPreference(
    "voip_audio_capture_volume_constraint",
    defaultValue: true,
  );

  /// Development-only receiver-side participant loudness measurement.
  ///
  /// Measurement and diagnostics only: it never changes playback gain, the
  /// manual per-user volume override, or any sender-side processing. Off by
  /// default; the diagnostic view is developer-gated on top of this flag.
  BoolPreference voipRemoteParticipantLoudnessMeasurement = BoolPreference(
    "voip_remote_participant_loudness_measurement",
    defaultValue: false,
  );

  StringPreference voipNoiseSuppressionHookMode = StringPreference(
    _voipNoiseSuppressionHookMode,
    defaultValue: _voipNoiseSuppressionDeepFilterNetHook,
  );

  StringPreference voipAudioCaptureTapOrderScenario = StringPreference(
    "voip_audio_capture_tap_order_scenario",
    defaultValue: "manual",
  );

  BoolPreference activityShowLocally = BoolPreference(
    "activity_show_locally",
    defaultValue: false,
  );

  BoolPreference activityShowLocalMediaControls = BoolPreference(
    "activity_show_local_media_controls",
    defaultValue: false,
  );

  BoolPreference activityPublishBasicStatus = BoolPreference(
    "activity_publish_basic_status",
    defaultValue: false,
  );

  BoolPreference activityPublishRich = BoolPreference(
    "activity_publish_rich",
    defaultValue: false,
  );

  BoolPreference activityShowSpotify = BoolPreference(
    "activity_show_spotify",
    defaultValue: false,
  );

  NullableStringPreference activitySpotifyClientId = NullableStringPreference(
    "activity_spotify_client_id",
    defaultValue: null,
  );

  NullableStringPreference activitySpotifyRedirectUri =
      NullableStringPreference(
        "activity_spotify_redirect_uri",
        defaultValue: null,
      );

  NullableStringPreference activitySpotifyLastBuildClientId =
      NullableStringPreference(
        activitySpotifyLastBuildClientIdKey,
        defaultValue: null,
      );

  NullableStringPreference activitySpotifyLastBuildRedirectUri =
      NullableStringPreference(
        activitySpotifyLastBuildRedirectUriKey,
        defaultValue: null,
      );

  BoolPreference activityShowGame = BoolPreference(
    "activity_show_game",
    defaultValue: false,
  );

  NullableStringPreference activitySteamId = NullableStringPreference(
    "activity_steam_id",
    defaultValue: null,
  );

  NullableStringPreference activitySteamLastBuildApiBaseUrl =
      NullableStringPreference(
        activitySteamLastBuildApiBaseUrlKey,
        defaultValue: null,
      );

  BoolPreference activityHideCurrent = BoolPreference(
    "activity_hide_current",
    defaultValue: false,
  );

  BoolPreference activityMockSourceEnabled = BoolPreference(
    "activity_mock_source_enabled",
    defaultValue: false,
  );

  NullableStringPreference filterClient = NullableStringPreference(
    "filter_client_id",
    defaultValue: null,
  );

  NullableStringPreference fcmKey = NullableStringPreference(
    _fcmKey,
    defaultValue: null,
  );

  NullableStringPreference unifiedPushEndpoint = NullableStringPreference(
    _unifiedPushEndpoint,
    defaultValue: null,
  );

  NullableStringPreference embeddedNtfyTopic = NullableStringPreference(
    _embeddedNtfyTopic,
    defaultValue: null,
  );

  NullableStringPreference webPushPermissionState = NullableStringPreference(
    "web_push_permission_state",
    defaultValue: null,
  );

  NullableStringPreference webPushSubscription = NullableStringPreference(
    "web_push_subscription",
    defaultValue: null,
  );

  NullableStringPreference lastDownloadLocation = NullableStringPreference(
    "last_download_location",
    defaultValue: null,
  );

  NullableStringPreference calendarDefaultView = NullableStringPreference(
    "calendar_default_view",
    defaultValue: null,
  );
}
