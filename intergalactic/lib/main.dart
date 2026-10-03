import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

export 'package:intergalactic/config/app_globals.dart' show preferences;

import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/matrix/database/app_group/drift_database_location.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/components/activity/publishers/matrix_activity_presence_publisher.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_bridge.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_intake.dart';
import 'package:intergalactic/client/components/inbound_share/android_inbound_share_stager.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_lifecycle.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_handoff.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_payload.dart';
import 'package:intergalactic/client/components/inbound_share/inbound_share_staging.dart';
import 'package:intergalactic/client/components/inbound_share/ios_inbound_share_intake.dart';
import 'package:intergalactic/client/components/activity/publishers/matrix_activity_room_publisher.dart';
import 'package:intergalactic/client/components/activity/activity_connection_alerts.dart';
import 'package:intergalactic/client/components/activity/activity_service.dart';
import 'package:intergalactic/client/components/activity/activity_settings.dart';
import 'package:intergalactic/client/components/activity/sources/local_media/local_media_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/mock_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_activity_source.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_auth.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_connection_service.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_secure_token_store.dart';
import 'package:intergalactic/client/components/activity/sources/spotify/spotify_token_store.dart';
import 'package:intergalactic/client/components/activity/sources/steam/steam_activity_source.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/client/components/push_notification/android/unified_push_notifier.dart';
import 'package:intergalactic/client/components/push_notification/notification_manager.dart';
import 'package:intergalactic/client/components/push_notification/ios/notification_policy_snapshot.dart';
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_service.dart';
import 'package:intergalactic/client/components/push_notification/web/web_app_badge_manager.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_notification_bridge.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
import 'package:intergalactic/client/components/voip/livekit_connectivity_veto_guard.dart';
import 'package:intergalactic/client/components/voip/call_surface_mode.dart';
import 'package:intergalactic/client/components/voip/mobile_call_popout_controller.dart';
import 'package:intergalactic/client/components/voip/voip_session.dart';
import 'package:intergalactic/client/components/voip/webrtc_default_devices.dart';
import 'package:intergalactic/client/matrix/components/voip_room/external_livekit_receiver_probe_runtime.dart';
import 'package:intergalactic/client/matrix/matrix_e2ee_diagnostics.dart';
import 'package:intergalactic/client/matrix/matrix_session_lifecycle_watcher.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/global_config.dart';
import 'package:intergalactic/config/integration_defaults.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences/preference.dart';
import 'package:intergalactic/config/subplatforms/subplatforms.dart';
import 'package:intergalactic/debug/l10n_debug_lookup.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/diagnostic/diagnostics.dart';
import 'package:intergalactic/generated/intl/messages_all.dart';
import 'package:intergalactic/service/background_service.dart';
import 'package:intergalactic/single_instance.dart';
import 'package:intergalactic/ui/pages/bubble/bubble_page.dart';
import 'package:intergalactic/ui/pages/fatal_error/fatal_error_page.dart';
import 'package:intergalactic/ui/pages/login/login_page.dart';
import 'package:intergalactic/ui/pages/main/main_page.dart';
import 'package:intergalactic/ui/pages/settings/app_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/settings_category_app.dart';
import 'package:intergalactic/ui/pages/settings/settings_navigation.dart';
import 'package:intergalactic/ui/pages/setup/menus/check_for_updates.dart';
import 'package:intergalactic/ui/pages/setup/menus/notification_preview_privacy_setup.dart';
import 'package:intergalactic/ui/pages/setup/menus/url_preview_consent_setup.dart';
import 'package:intergalactic/ui/pages/startup/startup_shell.dart';
import 'package:intergalactic/ui/app_shell.dart';
import 'package:intergalactic/ui/navigation/desktop_navigation_history.dart';
import 'package:intergalactic/ui/organisms/call_view/call.dart';
import 'package:intergalactic/ui/organisms/call_view/desktop_call_popout_host.dart';
import 'package:intergalactic/ui/windows/detached_call_window/detached_call_window_host.dart';
import 'package:intergalactic/ui/windows/notification_companion/notification_companion_host.dart';
import 'package:intergalactic/utils/android_intent_helper.dart';
import 'package:intergalactic/utils/app_icon/app_icon_manager.dart';
import 'package:intergalactic/utils/custom_uri.dart';
import 'package:intergalactic/utils/background_tasks/background_task_manager.dart';
import 'package:intergalactic/utils/database/database_release_trigger.dart';
import 'package:intergalactic/utils/database/releasable_connection.dart';
import 'package:intergalactic/utils/call_popout_controller.dart';
import 'package:intergalactic/utils/database/database_server.dart';
import 'package:intergalactic/utils/emoji/unicode_emoji.dart';
import 'package:intergalactic/utils/event_bus.dart';
import 'package:intergalactic/utils/first_time_setup.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:intergalactic/utils/shortcuts_manager.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/system_wide_shortcuts.dart';
import 'package:intergalactic/utils/update_checker.dart';
import 'package:intergalactic/utils/app_exit.dart';
import 'package:intergalactic/utils/desktop_webview_titlebar.dart';
import 'package:intergalactic/utils/dm_lock_controller.dart';
import 'package:intergalactic/utils/intent_receiver.dart';
import 'package:intergalactic/utils/sqlite_init.dart';
import 'package:intergalactic/utils/window_management.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:image_picker_android/image_picker_android.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:tiamat/config/style/theme_dark_matter.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

final GlobalKey<NavigatorState> navigator = GlobalKey();
FileCache? fileCache;
ShortcutsManager shortcutsManager = ShortcutsManager();
BackgroundTaskManager backgroundTaskManager = BackgroundTaskManager();
CallPopoutController callPopoutController = CallPopoutController(
  diagnosticLogger: _logCallPopoutDiagnostic,
);

void _logCallPopoutDiagnostic(String message) {
  if (message.contains('route=desktop-fallback-session') ||
      message.contains('result=unavailable')) {
    Log.w(message, category: LogCategory.livekit, source: 'call-popout');
    return;
  }

  Log.i(message, category: LogCategory.livekit, source: 'call-popout');
}

DmLockController dmLockController = DmLockController();
ClientManager? clientManager;
ActivityService activityService = ActivityService();
ActivityConnectionAlerts? _activityConnectionAlerts;

ActivityConnectionAlertSimulation get activityConnectionAlertSimulation =>
    _activityConnectionAlerts?.developerSimulation ??
    ActivityConnectionAlertSimulation.none;

void setActivityConnectionAlertSimulation(
  ActivityConnectionAlertSimulation simulation,
) {
  _activityConnectionAlerts?.setDeveloperSimulation(simulation);
}

SoundboardPlaybackService soundboardPlaybackService =
    SoundboardPlaybackService();
SpotifyTokenStore spotifyTokenStore = SecureSpotifyTokenStore();
SpotifyConnectionService spotifyConnectionService = SpotifyConnectionService(
  authConfigProvider: spotifyAuthConfig,
  tokenStore: spotifyTokenStore,
);

bool isHeadless = false;
bool isBubble = false;
bool _activityServiceConfigured = false;

SpotifyAuthConfig spotifyAuthConfig() => resolveSpotifyAuthConfig(
  storedClientId: preferences.isInit
      ? preferences.activitySpotifyClientId.value
      : null,
  storedRedirectUri: preferences.isInit
      ? preferences.activitySpotifyRedirectUri.value
      : null,
  preservedClientId: preferences.isInit
      ? preferences.activitySpotifyLastBuildClientId.value
      : null,
  preservedRedirectUri: preferences.isInit
      ? preferences.activitySpotifyLastBuildRedirectUri.value
      : null,
);

String steamActivityApiBaseUrl() {
  return resolveSteamActivityApiBaseUrl(
    preserved: preferences.isInit
        ? preferences.activitySteamLastBuildApiBaseUrl.value
        : null,
  );
}

Future<void>? loading;

List<String> commandLineArgs = [];

@pragma('vm:entry-point')
void unifiedPushEntry() {
  runZonedGuarded<Future<void>>(
    () async {
      isHeadless = true;
      Log.prefix = "unified-push";
      WidgetsFlutterBinding.ensureInitialized();
      await Log.initialize();
      MatrixE2eeDiagnostics.installSdkLogBridge();
      Log.installFlutterErrorHandler();
      Log.installPlatformDispatcherErrorHandler();
      await preferences.init();
      await UnifiedPushNotifier().init();
    },
    (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unhandled unified push entrypoint error',
        category: LogCategory.notifications,
        source: 'unified-push',
        flush: true,
      );
    },
    zoneSpecification: Log.spec,
  );
}

@pragma('vm:entry-point')
void onBackgroundNotificationResponse(dynamic details) {
  Log.i(
    "Got a background notification response: $details",
    category: LogCategory.notifications,
    source: 'background-notification-response',
  );
}

@pragma('vm:entry-point')
void bubble() {
  runZonedGuarded<Future<void>>(
    () async {
      Log.prefix = "bubble";
      isBubble = true;
      ensureBindingInit();
      await Log.initialize();
      MatrixE2eeDiagnostics.installSdkLogBridge();
      Log.installFlutterErrorHandler();
      Log.installPlatformDispatcherErrorHandler();
      Log.i(
        'Starting Android notification bubble entrypoint',
        category: LogCategory.notifications,
        source: 'bubble',
      );
      await initNecessary();
      await initGuiRequirements();

      String? initialRoomId;
      String? initialClientId;

      var intent = await getInitialAppIntent();

      if (intent?.extra?.containsKey("bubbleExtra") == true) {
        var uri = CustomURI.parse(intent!.extra!["bubbleExtra"]);

        if (uri is OpenRoomURI) {
          initialClientId = uri.clientId;
          initialRoomId = uri.roomId;
        }
      }

      Log.prefix = "bubble-$initialRoomId";

      var initialTheme = await preferences.resolveTheme();

      runApp(
        MaterialApp(
          title: BuildConfig.app,
          theme: initialTheme,
          navigatorKey: navigator,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) => Provider<ClientManager>(
            create: (context) => clientManager!,
            child: child,
          ),
          home: BubblePage(
            clientManager!,
            initialClientId: initialClientId,
            initialRoom: initialRoomId,
          ),
        ),
      );
    },
    (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unhandled bubble entrypoint error',
        category: LogCategory.notifications,
        source: 'bubble',
        flush: true,
      );
    },
    zoneSpecification: Log.spec,
  );
}

void main(List<String> args) {
  commandLineArgs = args;

  if (ExternalLivekitReceiverProbeRuntime.isInvocation(args)) {
    _runExternalLivekitReceiverProbe(args);
    return;
  }

  if (!UpdateChecker.isWindowsUpdaterInvocation(args) &&
      runDesktopWebViewTitleBarWidget(args)) {
    return;
  }

  final diagnosticsOptions = RuntimeDiagnosticsOptions.fromArgs(args);
  Log.configureRuntimeOptions(diagnosticsOptions);
  runZonedGuarded<Future<void>>(
    () async {
      Log.prefix = "main";
      Log.beginStartupTelemetry();
      ensureBindingInit();
      await Log.initialize(options: diagnosticsOptions);
      MatrixE2eeDiagnostics.installSdkLogBridge();
      Log.installFlutterErrorHandler();
      Log.installPlatformDispatcherErrorHandler();
      if (await UpdateChecker.maybeRunWindowsUpdater(args)) {
        return;
      }

      Log.i(
        'Starting ${BuildConfig.app} ${BuildConfig.VERSION_TAG} '
        'platform=${BuildConfig.PLATFORM} '
        'debugLogs=${diagnosticsOptions.debugLogs} '
        'webrtcStats=${diagnosticsOptions.webrtcStats}',
        source: 'startup',
      );
      await appMain();
    },
    (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unhandled app zone error',
        category: LogCategory.app,
        source: 'run-zoned-guarded',
        flush: true,
      );
    },
    zoneSpecification: Log.spec,
  );
}

void _runExternalLivekitReceiverProbe(List<String> args) {
  final diagnosticsOptions = RuntimeDiagnosticsOptions.fromArgs(args);
  Log.configureRuntimeOptions(diagnosticsOptions);
  runZonedGuarded<Future<void>>(
    () async {
      Log.prefix = "receiver-probe";
      ensureBindingInit();
      await Log.initialize(options: diagnosticsOptions);
      MatrixE2eeDiagnostics.installSdkLogBridge();
      Log.installFlutterErrorHandler();
      Log.installPlatformDispatcherErrorHandler();
      final exitCode = await ExternalLivekitReceiverProbeRuntime.run(args);
      exitApplication(exitCode);
    },
    (error, stackTrace) {
      Log.onError(
        error,
        stackTrace,
        content: 'Unhandled external receiver probe error',
        category: LogCategory.webrtc,
        source: 'external-receiver-probe',
        flush: true,
      );
      exitApplication(1);
    },
    zoneSpecification: Log.spec,
  );
}

Future<void> appMain() async {
  Log.prefix = "main";
  Log.recordStartupPhase(StartupPhase.preparing.name);
  try {
    if (BuildConfig.WEB) {
      var info = await DeviceInfoPlugin().deviceInfo;
      if (info is WebBrowserInfo) {
        Layout.browserInfo = info;
      }
    }

    ensureBindingInit();
    configureAndroidPhotoPicker();
    configureLivekitConnectivityVetoGuard();

    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      if (await SingleInstance.startOrConnectToMainInstance(commandLineArgs)) {
        exitApplication(0);
      }
    }

    if (await UpdateChecker.checkForStartupUpdate()) {
      exitApplication(0);
      return;
    }

    Log.installFlutterErrorHandler();
    Log.installPlatformDispatcherErrorHandler();

    isHeadless =
        PlatformUtils.isAndroid &&
        AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState;

    final showStartupShell =
        !isHeadless &&
        (BuildConfig.DESKTOP || PlatformUtils.isAndroid || PlatformUtils.isIOS);
    final startupPhase = ValueNotifier<StartupPhase>(StartupPhase.preparing);
    final startupTheme = ValueNotifier<ThemeData>(ThemeDarkMatter.theme);

    await WindowManagement.prepareDesktopChrome();

    if (showStartupShell) {
      runApp(
        StartupShell(
          phaseListenable: startupPhase,
          themeListenable: startupTheme,
        ),
      );
    }

    loading = initNecessary(
      onStartupPhase: showStartupShell
          ? (phase) => startupPhase.value = phase
          : null,
      onStartupThemeReady: showStartupShell
          ? (theme) => startupTheme.value = theme
          : null,
    );

    if (isHeadless) {
      WidgetsBinding.instance.addObserver(AppStarter());
      await loading;
      return;
    } else {
      await loading;
    }

    await SystemWideShortcuts.init();

    if (showStartupShell) {
      startupPhase.value = StartupPhase.openingInterface;
    }

    await startGui();
  } catch (error, stacktrace) {
    Log.onError(
      error,
      stacktrace,
      content: 'Fatal startup error',
      category: LogCategory.app,
      source: 'startup',
      flush: true,
    );
    ensureBindingInit();
    runApp(FatalErrorPage(error, stacktrace));
  }
}

WidgetsBinding ensureBindingInit() {
  ScaledWidgetsFlutterBinding.ensureInitialized(
    scaleFactor: (deviceSize) {
      return 1;
    },
  );

  return WidgetsFlutterBinding.ensureInitialized();
}

/// Installs the guard that stops a false "no network" verdict from permanently
/// disabling calling on Windows.
///
/// Must run before the first LiveKit join, because `SignalClient.connect` reads
/// `Connectivity()` on every connect. Installed here, next to the other
/// platform-instance override, so both are visible in one place at startup.
void configureLivekitConnectivityVetoGuard() {
  if (!LivekitConnectivityVetoGuard.installIfSupported()) {
    return;
  }

  Log.i(
    'Installed LiveKit connectivity veto guard (BUG-296): a `none` verdict '
    'is now overridden when a routable address exists',
    category: LogCategory.livekit,
    source: 'main',
  );
}

void configureAndroidPhotoPicker() {
  if (!PlatformUtils.isAndroid) {
    return;
  }

  final imagePickerImplementation = ImagePickerPlatform.instance;
  if (imagePickerImplementation is ImagePickerAndroid) {
    imagePickerImplementation.useAndroidPhotoPicker = true;
  }
}

/// Initializes the bare necessities for the app to run in headless mode
Future<void> initNecessary({
  ValueChanged<StartupPhase>? onStartupPhase,
  ValueChanged<ThemeData>? onStartupThemeReady,
}) async {
  _reportStartupPhase(StartupPhase.preferences, onStartupPhase);
  initSqfliteFfi();
  // NSE Phase C: every write to a watched notification preference rewrites
  // the policy snapshot the extension reads, before the write returns. The
  // hook is a no-op off iOS. Installed before init so nothing is missed.
  Preference.afterWrite = NotificationPolicySnapshot.onPreferenceWritten;
  Preference.afterClear = NotificationPolicySnapshot.onPreferencesCleared;
  await preferences.init();
  if (onStartupThemeReady != null) {
    onStartupThemeReady(await preferences.resolveTheme());
  }
  await IosCallAudioSession.configureStartupVoiceProcessing();
  _reportStartupPhase(StartupPhase.localServices, onStartupPhase);
  await initActivityService();
  await NoiseSuppressionService.instance.init(
    enabled: preferences.voipNoiseSuppressionEnabled.value,
    tuningProfile: NoiseSuppressionTuningProfile.fromPreferenceValues(
      presetKey: preferences.voipNoiseSuppressionPreset.value,
      customVadThreshold: preferences.voipNoiseSuppressionVadThreshold.value,
      customSpeechGraceMs: preferences.voipNoiseSuppressionSpeechGraceMs.value,
      customClosedGainPercent:
          preferences.voipNoiseSuppressionClosedGainPercent.value,
      customTransientSensitivityPercent:
          preferences.voipNoiseSuppressionTransientSensitivity.value,
    ),
  );
  await dmLockController.init(preferences);
  _reportStartupPhase(StartupPhase.storage, onStartupPhase);
  await initDatabaseServer();

  fileCache = FileCache.getFileCacheInstance();

  await Future.wait([
    if (fileCache != null) fileCache!.init(),
    GlobalConfig.init(),
  ]);

  _reportStartupPhase(StartupPhase.accounts, onStartupPhase);
  // NSE Phase B: resolve where the account databases live BEFORE any client
  // opens one. On iOS this runs the App Group migration for every account
  // directory on disk; on every other platform it returns at once.
  await DriftDatabaseLocation.prepare();
  clientManager = await ClientManager.init();
  // B3: this launch has read from the resolved location. The launch after a
  // confirmed one deletes the app-private copy.
  await DriftDatabaseLocation.confirmLaunchRead();
  // Phase C: the snapshot exists for every launch with an account, and is
  // gone when there is none.
  await NotificationPolicySnapshot.onAccountsChanged(
    clientCount: clientManager!.clients.length,
  );
  _initializeActivityConnectionAlerts();
  _attachDatabaseReleaseTrigger(clientManager!);
  _reportStartupPhase(StartupPhase.appServices, onStartupPhase);
  soundboardPlaybackService.configure(clientManager!.callManager);
  activityService.refreshSettings();
  clientManager!.onClientAdded.stream.listen((_) {
    activityService.refreshSettings();
  });
  clientManager!.onClientRemoved.stream.listen((_) {
    activityService.refreshSettings();
  });
  Diagnostics.setPostInit();

  shortcutsManager.init();
  await stopEmbeddedPushBackgroundServiceIfDisabled();
  NotificationManager.init();
  initWebPushNotificationBridge();
  initWebAppBadgeManager();
  MatrixSessionLifecycleWatcher().init();

  NeedsPostLoginInit.doPostLoginInit();
}

void _reportStartupPhase(
  StartupPhase phase,
  ValueChanged<StartupPhase>? callback,
) {
  Log.recordStartupPhase(phase.name);
  callback?.call(phase);
}

/// B5: release the account databases before suspension and re-establish them
/// on resume. See `DatabaseReleaseTrigger` for the condition and the order.
///
/// "Live background execution" is any call session, in any state short of
/// gone: Flutter reports `paused` while a call runs under the audio background
/// mode, and releasing then would close the database under the call.
DatabaseReleaseTrigger? _databaseReleaseTrigger;

void _attachDatabaseReleaseTrigger(ClientManager manager) {
  if (_databaseReleaseTrigger != null) {
    return;
  }

  // iOS only, and deliberately so. The mechanism is platform-neutral, but
  // the reason for it is not: 0xdead10cc is an iOS termination, and iOS is
  // the platform where the process is frozen shortly after `paused`. On
  // Android `paused` fires on every app switch while the process keeps
  // running, so this trigger would stop foreground sync and drop the
  // database on every backgrounding - a cost paid for a failure Android does
  // not have, on the platform that backgrounds most often. Desktop never
  // reports `paused` at all. The trigger itself keeps no conditional; the
  // decision lives here, where the other platform decisions are.
  if (!PlatformUtils.isIOS) {
    return;
  }

  List<MatrixClient> matrixClients() =>
      manager.clients.whereType<MatrixClient>().toList(growable: false);

  final trigger = DatabaseReleaseTrigger(
    databases: () => ReleasableConnection.live,
    suspendSync: () async {
      for (final client in matrixClients()) {
        await client.suspendSyncForDatabaseRelease();
      }
    },
    resumeSync: () {
      for (final client in matrixClients()) {
        client.resumeSyncAfterDatabaseRelease();
      }
    },
    hasLiveBackgroundExecution: () =>
        manager.callManager.currentSessions.isNotEmpty,
  );
  _databaseReleaseTrigger = trigger;
  trigger.attach();
}

void _initializeActivityConnectionAlerts() {
  final manager = clientManager;
  if (manager == null || _activityConnectionAlerts != null) {
    return;
  }

  final alerts = ActivityConnectionAlerts(
    alertManager: manager.alertManager,
    openActivitySettings: _openActivitySettings,
  );
  _activityConnectionAlerts = alerts;

  alerts.updateSpotifyStatus(spotifyConnectionService.status);
  spotifyConnectionService.onStatusChanged.listen(alerts.updateSpotifyStatus);

  final steamSource = activityService.sources
      .whereType<SteamActivitySource>()
      .firstOrNull;
  if (steamSource == null) {
    return;
  }

  alerts.updateSteamConnectionIssue(steamSource.connectionIssue);
  steamSource.onConnectionIssueChanged.listen(
    alerts.updateSteamConnectionIssue,
  );
}

void _openActivitySettings(BuildContext context) {
  unawaited(
    SettingsNavigation.show(
      context,
      const AppSettingsPage(initialTabId: SettingsCategoryApp.tabIdActivity),
    ),
  );
}

Future<void> initActivityService() async {
  if (BuildConfig.MOBILE && !BuildConfig.IOS && !BuildConfig.ANDROID) {
    return;
  }

  activityService.configure(
    settingsProvider: () => ActivitySettings.fromPreferences(preferences),
  );
  unawaited(spotifyConnectionService.refreshStatus());

  if (!_activityServiceConfigured) {
    if (BuildConfig.IOS) {
      activityService.registerSource(
        LocalMediaActivitySource(
          enabled: () => preferences.activityShowLocalMediaControls.value,
        ),
      );
    }

    final enableSpotifyActivity =
        !BuildConfig.MOBILE || BuildConfig.IOS || BuildConfig.ANDROID;

    if (!BuildConfig.MOBILE) {
      activityService.registerSource(
        MockActivitySource.music(
          enabled: () => preferences.activityMockSourceEnabled.value,
        ),
      );
    }

    if (enableSpotifyActivity) {
      activityService.registerSource(
        SpotifyActivitySource(
          authConfigProvider: spotifyAuthConfig,
          tokenStore: spotifyTokenStore,
          enabled: () => preferences.activityShowSpotify.value,
        ),
      );
    }

    if (!BuildConfig.MOBILE) {
      activityService.registerSource(
        SteamActivitySource(
          summaryEndpoint: steamActivityApiBaseUrl,
          steamId: () => preferences.activitySteamId.value,
          enabled: () => preferences.activityShowGame.value,
        ),
      );
    }

    activityService.registerPublisher(
      MatrixActivityPresencePublisher.forClientManager(() => clientManager),
    );

    // Rich, structured activity into active call rooms so remote participants
    // render it on their tiles; presence text (above) stays the fallback for
    // non-Inter-Galactic clients.
    activityService.registerPublisher(
      MatrixActivityRoomPublisher.forClientManager(() => clientManager),
    );

    preferences.onSettingChanged.listen((_) {
      for (final source in activityService.sources) {
        if (source is MockActivitySource) {
          source.notifySettingsChanged();
        }
        if (source is SpotifyActivitySource) {
          source.notifySettingsChanged();
        }
        if (source is SteamActivitySource) {
          source.notifySettingsChanged();
        }
        if (source is LocalMediaActivitySource) {
          source.notifySettingsChanged();
        }
      }
      activityService.refreshSettings();
    });
    _activityServiceConfigured = true;
  }

  await activityService.start();
}

/// Initializes everything that is needed to run in GUI mode
Future<void> initGuiRequirements() async {
  isHeadless = false;

  MediaKit.ensureInitialized();

  var locale = PlatformDispatcher.instance.locale;

  await UnicodeEmojis.load();
  if (preferences.debugTranslations.value) {
    await initializeMessagesDebug();
  } else {
    await initializeMessages(locale.languageCode);
  }
  await initializeDateFormatting(locale.languageCode);

  tiamat.getAppScale = () {
    return preferences.appScale.value;
  };

  Intl.defaultLocale = locale.languageCode;
}

/// Initializes gui requirements and launches the gui
Future<bool> _dispatchAndroidInboundShare(dynamic intent) async {
  final parsed = AndroidInboundShareBridge.tryParse(intent);
  if (parsed == null) return false;
  Log.i(
    'inbound_share event=android_intent_parsed result=accepted '
    'has_text=${parsed.text?.trim().isNotEmpty ?? false} '
    'stream_count=${parsed.streams.length} '
    'stream_hash=${_androidInboundShareStreamHash(parsed.streams)}',
  );
  InboundSharePayload? payload;
  try {
    const AndroidInboundShareStagingPlatform staging =
        MethodChannelAndroidInboundShareStaging();
    try {
      final snapshot = await staging.grantSnapshot(parsed.streams);
      Log.i(
        'inbound_share event=android_grant_snapshot '
        '${snapshot?.toLogFields() ?? 'result=unavailable reason=no_snapshot'}',
      );
    } on PlatformException catch (error) {
      Log.w(
        'inbound_share event=android_grant_snapshot result=unavailable reason=${error.code}',
      );
    } on FormatException {
      Log.w('inbound_share event=android_grant_snapshot result=invalid');
    } catch (error) {
      // The snapshot is diagnostic only. A missing handler on an older native
      // side arrives as MissingPluginException, and nothing about that should
      // be able to abort the share this block exists only to describe.
      Log.w(
        'inbound_share event=android_grant_snapshot result=unavailable '
        'reason=${error.runtimeType}',
      );
    }
    payload =
        AndroidInboundShareIntake.textPayload(parsed) ??
        await AndroidInboundShareStager(
          staging,
          onDiscard: _discardAndroidInboundShareSession,
        ).stage(parsed);
  } on PlatformException catch (error) {
    // The native staging boundary is outside the app zone. Treat a rejected
    // provider read as a failed share, rather than allowing it to surface as an
    // unhandled asynchronous error that leaves the app looking crashed.
    //
    // `code` alone is always `share_stage_failed` here, so logging only that
    // said nothing a rebuild could act on. `details` carries native's per-item
    // `kind`/`read_grant`/`uri_hash`, which is the part that distinguishes a
    // revoked grant from a replayed intent from a size refusal.
    Log.w(
      'inbound_share event=android_payload_staged result=error '
      'reason=${error.code} stream_count=${parsed.streams.length} '
      'stream_hash=${_androidInboundShareStreamHash(parsed.streams)} '
      'message=${error.message ?? 'none'} '
      'detail=${error.details ?? 'none'}',
    );
    EventBus.emitInboundShareFailure(
      androidInboundShareFailureFromDetails(error.details),
    );
    return true;
  }
  if (payload == null) {
    Log.w('inbound_share event=android_payload_staged result=rejected');
    // Reached when the stager refuses native's response outright - a count
    // mismatch, a mixed session token, an unusable entry. The user shared
    // something and is owed an answer either way.
    EventBus.emitInboundShareFailure(InboundShareFailure.unreadable);
    return false;
  }
  EventBus.emitInboundSharePayload(payload);
  Log.i(
    'inbound_share event=event_bus_emitted origin=android '
    'item_count=${payload.itemCount} '
    'has_staging_token=${payload.stagingToken != null}',
  );
  return true;
}

/// Stable fingerprint of an inbound share's stream URIs, safe to export.
///
/// Two share events that report the same hash carried the *same* content URIs.
/// That is the one observation that separates a genuinely new share from the
/// platform bridge re-emitting the activity's existing intent on re-attach -
/// and a re-emitted intent's URI grants were consumed by the share before it,
/// so it fails at the provider read while looking like a fresh delivery.
///
/// Hashed rather than logged raw: a content URI names a provider and a row id,
/// and for a gallery share that is a pointer to the user's media.
String _androidInboundShareStreamHash(List<Uri> streams) {
  if (streams.isEmpty) return 'none';
  return sha256
      .convert(utf8.encode(streams.map((uri) => uri.toString()).join('\u0000')))
      .toString()
      .substring(0, 12);
}

/// Deletes an Android staging session this side refused.
///
/// Native cleans up only when the whole `stageContentUris` request throws. A
/// response the stager then rejects - wrong length, mixed session tokens, an
/// unusable entry - would otherwise keep up to the full session budget in
/// `<cacheDir>/inbound-share/<token>` with nothing left to release it.
Future<void> _discardAndroidInboundShareSession(String sessionToken) async {
  try {
    final root = await const MethodChannelInboundShareStagingRootProvider()
        .resolve();
    final staging = InboundShareStaging(root);
    await staging.release(await staging.claimExistingSession(sessionToken));
  } catch (error, stackTrace) {
    // Best effort: the share is already being dropped, so a failed cleanup must
    // not turn into a second failure path for the user.
    Log.onError(
      error,
      stackTrace,
      content: 'Failed to discard a rejected inbound-share staging session',
    );
  }
}

const _iosInboundShareChannel = MethodChannel(
  'chat.intergalactic.app/inbound_share',
);

/// Reads a reserved session and hands the payload to the review flow.
///
/// This deliberately does **not** settle the native reservation. Acknowledging
/// here would mean acknowledging an in-memory emission, so a process death
/// between this point and `MainPage`'s `InboundShareLifecycle.admit` would
/// leave a session marked accepted that nothing would ever pick up. The
/// acknowledge/reject now happens on the admission outcome instead. REVIEW,
/// 2026-08-02.
///
/// A manifest that cannot be read at all *is* settled here, because that is a
/// verdict rather than a hiccup: the payload never reaches admission, so
/// nothing downstream would ever report on it.
Future<void> _dispatchIosInboundShareToken(Object? token) async {
  if (token is! String) return;
  try {
    final payload = await IosInboundShareIntake(
      const MethodChannelInboundShareStagingRootProvider(),
    ).readToken(token);
    if (payload != null) {
      // Diagnostics for the inbound-share device matrix. Native NSLog lines go
      // to the device console and never reach the in-app log export, so the
      // item shape is recorded here where an exported log can show it. Counts
      // and kinds only - no filenames, no body text, no room id.
      final files = payload.items
          .where((i) => i.kind == InboundShareItemKind.file)
          .length;
      Log.i(
        'iOS inbound share read '
        'items=${payload.items.length} files=$files '
        'hasBody=${payload.body != null} '
        'preselected=${payload.preselectedRoomId != null}',
        category: LogCategory.media,
        source: 'inbound-share',
      );
      EventBus.emitInboundSharePayload(payload);
      return;
    }
    // Absent, malformed, or an unreadable schema. Retrying reproduces the same
    // answer, so clean up rather than stranding the bytes.
    await const MethodChannelInboundShareHandoff().reject(token);
  } catch (_) {
    // The App Group is a native boundary. Leave a failed or incomplete session
    // unreviewed rather than crashing the host or creating a direct send path.
    // Deliberately no reject here - the reservation lapsing is what makes a
    // transient failure retryable.
  }
}

bool _iosInboundShareDraining = false;
bool _iosInboundShareDrainRequested = false;

/// Drains every session the iOS Share Extension has staged, one drain at a time.
///
/// Startup and `onResume` both start a drain, and both are detached, so two can
/// otherwise be in flight at once and reserve the same session - which delivers
/// one share to review twice. A request arriving during a drain is coalesced
/// into one more pass rather than dropped, so a session staged mid-drain is
/// still picked up.
Future<void> _drainPendingIosInboundShares() async {
  if (_iosInboundShareDraining) {
    _iosInboundShareDrainRequested = true;
    return;
  }
  _iosInboundShareDraining = true;
  try {
    do {
      _iosInboundShareDrainRequested = false;
      await _drainPendingIosInboundSharesOnce();
    } while (_iosInboundShareDrainRequested);
  } finally {
    _iosInboundShareDraining = false;
  }
}

/// Pulls staged sessions until native has none left.
///
/// Pull is the only delivery mechanism. The extension does not launch the host
/// (REVIEW blocked the unsupported responder-chain `openURL:` route on
/// 2026-08-02), so staged sessions are discovered when the app is next opened
/// or resumed. Native claims one session per call, atomically, and returns null
/// when none are left - so this drains in a loop rather than pulling once,
/// which would miss the second of two shares staged while backgrounded.
Future<void> _drainPendingIosInboundSharesOnce() async {
  // Bounded so a misbehaving native side cannot spin here. Native claims with
  // O_EXCL, so in practice each call returns a distinct session or null.
  for (var i = 0; i < 20; i++) {
    try {
      final token = await _iosInboundShareChannel.invokeMethod<String>(
        'consumePendingInboundShare',
      );
      if (token == null) return;
      await _dispatchIosInboundShareToken(token);
    } on PlatformException {
      // The iOS handler is unavailable only before native registration or on a
      // platform failure; neither condition can safely produce a review payload.
      return;
    }
  }
}

AppLifecycleListener? _iosInboundShareLifecycle;

void _configureIosInboundShareHandoff() {
  // A share staged while the app was backgrounded is only visible on resume,
  // so the drain runs there as well as at startup.
  _iosInboundShareLifecycle ??= AppLifecycleListener(
    onResume: () => unawaited(_drainPendingIosInboundShares()),
  );
  unawaited(_drainPendingIosInboundShares());
}

Future<void> startGui() async {
  String? initialRoomId;
  String? initialClientId;

  await initGuiRequirements();

  if (PlatformUtils.isIOS) {
    _configureIosInboundShareHandoff();
  }

  var webOpenRoom = getInitialWebOpenRoom();
  if (webOpenRoom.$2 != null) {
    initialClientId = webOpenRoom.$1;
    initialRoomId = webOpenRoom.$2;
  }

  if (PlatformUtils.isAndroid) {
    enableEdgeToEdge();

    var initialIntent = await getInitialAppIntent();
    appReceivedIntentStream.listen((event) async {
      Log.i('inbound_share event=android_intent_received origin=warm');
      if (await _dispatchAndroidInboundShare(event)) return;
      var uri = AndroidIntentHelper.getUriFromIntent(event);
      if (uri is OpenRoomURI) {
        EventBus.openRoom.add((uri.roomId, uri.clientId));
      }
    });

    if (initialIntent != null) {
      Log.i('inbound_share event=android_intent_received origin=cold');
    }

    if (!await _dispatchAndroidInboundShare(initialIntent)) {
      var uri = AndroidIntentHelper.getUriFromIntent(initialIntent);
      if (uri is OpenRoomURI) {
        initialClientId = uri.clientId;
        initialRoomId = uri.roomId;
      }
    }
  }

  double scale = preferences.appScale.value;

  ScaledWidgetsFlutterBinding.instance.scaleFactor = (deviceSize) {
    return scale;
  };

  var initialTheme = await preferences.resolveTheme();

  if (preferences.checkForUpdates.value == null &&
      UpdateChecker.shouldCheckForUpdates) {
    FirstTimeSetup.registerPostLoginSetup(UpdateCheckerSetup());
  }

  if (preferences.shouldShowNotificationPreviewPrivacyChoice) {
    FirstTimeSetup.registerPostLoginSetup(NotificationPreviewPrivacySetup());
  }

  if (preferences.shouldShowUrlPreviewE2EEConsentChoice) {
    FirstTimeSetup.registerPostLoginSetup(UrlPreviewConsentSetup());
  }

  runApp(
    App(
      clientManager: clientManager!,
      initialTheme: initialTheme,
      initialClientId: initialClientId,
      initialRoom: initialRoomId,
    ),
  );

  AppIconManager.instance.init();
  UpdateChecker.startPeriodicChecks();

  WindowManagement.init().then((_) {
    Subplatforms.init();
  });
}

(String?, String?) getInitialWebOpenRoom() {
  var queryParameters = Uri.base.queryParameters;
  return (queryParameters["client_id"], queryParameters["room_id"]);
}

void enableEdgeToEdge() async {
  var theme = await preferences.resolveTheme();
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.edgeToEdge,
  ); // Enable Edge-to-Edge on Android 10+
  SystemChrome.setSystemUIOverlayStyle(
    SystemUiOverlayStyle(
      systemNavigationBarColor:
          Colors.transparent, // Setting a transparent navigation bar color
      systemNavigationBarContrastEnforced: true, // Default
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
    ),
  );
}

bool _detachedCallWindowSupportLogged = false;

void _logDetachedCallWindowSupportOnce() {
  if (_detachedCallWindowSupportLogged) {
    return;
  }

  _detachedCallWindowSupportLogged = true;
  final message =
      'detached_call_window event=support_check '
      'platform=${BuildConfig.platformDisplay} '
      'native_define=${BuildConfig.ENABLE_NATIVE_DETACHED_CALL_WINDOWS} '
      'platform_supported=$isDetachedCallWindowPlatformSupported '
      'flutter_windowing=$isDetachedCallWindowingEnabled '
      'forced_windowing=$wasDetachedCallWindowingForced '
      'supported=$supportsDetachedCallWindows '
      'reason=$detachedCallWindowSupportReason';
  if (supportsDetachedCallWindows && !wasDetachedCallWindowingForced) {
    Log.i(
      message,
      category: LogCategory.livekit,
      source: 'detached-call-window',
    );
  } else {
    Log.w(
      message,
      category: LogCategory.livekit,
      source: 'detached-call-window',
    );
  }
}

class App extends StatelessWidget {
  const App({
    super.key,
    required this.clientManager,
    this.initialTheme,
    this.initialRoom,
    this.initialClientId,
  });
  final ThemeData? initialTheme;
  final ClientManager clientManager;

  final String? initialRoom;
  final String? initialClientId;

  @override
  Widget build(BuildContext context) {
    _logDetachedCallWindowSupportOnce();
    Widget home = AppView(
      clientManager: clientManager,
      initialClientId: initialClientId,
      initialRoom: initialRoom,
    );

    if (supportsDetachedCallWindows) {
      home = DetachedCallWindowHost(
        callManager: clientManager.callManager,
        child: home,
      );
    }

    if (supportsNotificationCompanionOverlay) {
      home = NotificationCompanionHost(child: home);
    }

    return IntergalacticAppShell(
      preferences: preferences,
      clientManager: clientManager,
      initialTheme: initialTheme,
      navigatorKey: navigator,
      home: home,
    );
  }
}

class AppView extends StatefulWidget {
  const AppView({
    required this.clientManager,
    super.key,
    this.initialClientId,
    this.initialRoom,
  });
  final ClientManager clientManager;
  final String? initialRoom;
  final String? initialClientId;

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  StreamSubscription? _onClientRemovedSubscription;
  StreamSubscription? _onClientAddedSubscription;
  bool? _lastShowMain;
  StreamSubscription? _mobileCallPopoutSubscription;
  StreamSubscription? _mobileCallPopoutActionSubscription;
  StreamSubscription? _mobileCallSessionsSubscription;
  MobileCallPopoutPresentationState _mobileCallPopoutState =
      MobileCallPopoutController.presentationState;

  @override
  void initState() {
    super.initState();
    _onClientRemovedSubscription = widget.clientManager.onClientRemoved.stream
        .listen((_) {
          if (!widget.clientManager.isLoggedIn()) {
            navigator.currentState?.popUntil((route) => route.isFirst);
          }
          if (!mounted) return;
          setState(() {});
        });
    _onClientAddedSubscription = widget.clientManager.onClientAdded.stream
        .listen((_) {
          if (!mounted) return;
          setState(() {});
        });
    if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
      _mobileCallPopoutSubscription = MobileCallPopoutController
          .presentationStateChanges
          .listen(_handleMobileCallPopoutState);
      _mobileCallPopoutActionSubscription = MobileCallPopoutController
          .actionRequests
          .listen((action) => unawaited(_handleMobileCallPopoutAction(action)));
      _mobileCallSessionsSubscription = widget
          .clientManager
          .callManager
          .currentSessions
          .onListUpdated
          .listen((_) {
            if (!mounted || !_usesMobileCallOnlySurface) {
              return;
            }
            setState(() {});
          });
      unawaited(MobileCallPopoutController.refreshPresentationState());
    }
  }

  @override
  void dispose() {
    _onClientRemovedSubscription?.cancel();
    _onClientAddedSubscription?.cancel();
    _mobileCallPopoutSubscription?.cancel();
    _mobileCallPopoutActionSubscription?.cancel();
    _mobileCallSessionsSubscription?.cancel();
    unawaited(soundboardPlaybackService.dispose());
    super.dispose();
  }

  void _handleMobileCallPopoutState(MobileCallPopoutPresentationState state) {
    if (!mounted) {
      return;
    }
    _syncMobileCallPopoutPlaceholderState(
      previous: _mobileCallPopoutState,
      next: state,
    );
    setState(() {
      _mobileCallPopoutState = state;
    });
  }

  void _syncMobileCallPopoutPlaceholderState({
    required MobileCallPopoutPresentationState previous,
    required MobileCallPopoutPresentationState next,
  }) {
    final previousSessionId = previous.sessionId;
    final nextSessionId = next.sessionId;
    final previousShowsPlaceholder = _mobileStateShowsRoomPlaceholder(previous);
    final nextShowsPlaceholder = _mobileStateShowsRoomPlaceholder(next);

    if (previousShowsPlaceholder &&
        (!nextShowsPlaceholder || previousSessionId != nextSessionId) &&
        previousSessionId != null) {
      callPopoutController.restoreSession(previousSessionId);
    }

    if (nextShowsPlaceholder && nextSessionId != null) {
      callPopoutController.popOutSession(nextSessionId);
    }
  }

  bool _mobileStateShowsRoomPlaceholder(
    MobileCallPopoutPresentationState state,
  ) {
    if (PlatformUtils.isIOS) {
      // Native iOS AVKit PiP currently consumes the existing WebRTC track. Keep
      // the in-room CallWidget mounted so LiveKit continues producing frames.
      return state.isResizedPopout;
    }
    return state.surfaceMode.showsRoomPlaceholder;
  }

  Future<void> _handleMobileCallPopoutAction(
    MobileCallPopoutAction action,
  ) async {
    final session = _mobileCallPopoutSession(
      widget.clientManager.isLoggedIn(),
      requireCallOnlySurface: false,
    );
    if (session == null) {
      return;
    }

    switch (action) {
      case MobileCallPopoutAction.returnToCall:
        callPopoutController.restoreSession(session.sessionId);
        EventBus.openRoom.add((session.roomId, session.client.identifier));
        break;
      case MobileCallPopoutAction.hangUp:
        try {
          await session.hangUpCall();
          callPopoutController.clearForSession(session.sessionId);
          unawaited(
            MobileCallPopoutController.exitPictureInPicture(reason: 'hang_up'),
          );
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to hang up mobile picture-in-picture call',
            category: LogCategory.livekit,
            source: 'mobile-call-popout',
          );
        }
        break;
      case MobileCallPopoutAction.close:
        callPopoutController.restoreSession(session.sessionId);
        await MobileCallPopoutController.exitPictureInPicture(reason: 'close');
        break;
      case MobileCallPopoutAction.fullScreen:
        callPopoutController.restoreSession(session.sessionId);
        await MobileCallPopoutController.exitPictureInPicture(
          reason: 'fullscreen',
        );
        EventBus.openRoom.add((session.roomId, session.client.identifier));
        break;
      case MobileCallPopoutAction.muteMicrophone:
        try {
          await session.setMicrophoneMute(!session.isMicrophoneMuted);
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content:
                'Failed to toggle mobile picture-in-picture microphone state',
            category: LogCategory.livekit,
            source: 'mobile-call-popout',
          );
        } finally {
          await _updateMobilePictureInPictureControls(session);
        }
        break;
      case MobileCallPopoutAction.toggleCamera:
        try {
          if (session.isCameraEnabled) {
            await session.stopCamera();
          } else {
            final camera = await WebrtcDefaultDevices.getDefaultCamera();
            await session.setCamera(camera);
          }
        } catch (error, stackTrace) {
          Log.onError(
            error,
            stackTrace,
            content: 'Failed to toggle mobile picture-in-picture camera state',
            category: LogCategory.livekit,
            source: 'mobile-call-popout',
          );
        } finally {
          await _updateMobilePictureInPictureControls(session);
        }
        break;
    }
  }

  Future<void> _updateMobilePictureInPictureControls(VoipSession session) {
    return MobileCallPopoutController.updatePictureInPictureControls(
      sessionId: session.sessionId,
      controlsState: MobileCallPictureInPictureControlsState(
        isMicrophoneMuted: session.isMicrophoneMuted,
        isCameraEnabled: session.isCameraEnabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showMain = widget.clientManager.isLoggedIn();
    _syncDesktopNavigationHistoryForAuthState(showMain);

    final content = showMain
        ? MainPage(
            widget.clientManager,
            initialClientId: widget.initialClientId,
            initialRoom: widget.initialRoom,
          )
        : LoginPage(
            onSuccess: (_) {
              if (!mounted) return;
              setState(() {});
            },
          );

    final mobileCallPopoutSession = _mobileCallPopoutSession(showMain);
    if (mobileCallPopoutSession != null) {
      return _MobileCallPopoutSurface(
        session: mobileCallPopoutSession,
        presentationState: _mobileCallPopoutState,
      );
    }

    final iosNativePiPKeepAliveSession = _iosNativePiPKeepAliveSession(
      showMain,
    );
    final routedContent = iosNativePiPKeepAliveSession == null
        ? content
        : Stack(
            clipBehavior: Clip.none,
            children: [
              content,
              _IOSNativePiPKeepAliveSurface(
                session: iosNativePiPKeepAliveSession,
              ),
            ],
          );

    if (!showMain || !BuildConfig.DESKTOP) {
      return routedContent;
    }

    return Stack(
      children: [
        routedContent,
        DesktopCallPopoutHost(widget.clientManager.callManager),
      ],
    );
  }

  void _syncDesktopNavigationHistoryForAuthState(bool showMain) {
    if (_lastShowMain == showMain) {
      return;
    }

    _lastShowMain = showMain;
    if (showMain) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      DesktopNavigationHistoryController.instance.reset();
    });
  }

  VoipSession? _mobileCallPopoutSession(
    bool showMain, {
    bool requireCallOnlySurface = true,
  }) {
    if (!showMain ||
        (!PlatformUtils.isAndroid && !PlatformUtils.isIOS) ||
        (requireCallOnlySurface && !_usesMobileCallOnlySurface)) {
      return null;
    }

    final sessions = widget.clientManager.callManager.currentSessions
        .where(_isMobilePopoutEligibleSession)
        .toList(growable: false);
    if (sessions.isEmpty) {
      return null;
    }

    final targetSessionId =
        MobileCallPopoutController.targetSessionId ??
        _mobileCallPopoutState.sessionId;
    if (targetSessionId != null) {
      for (final session in sessions) {
        if (session.sessionId == targetSessionId) {
          return session;
        }
      }
    }

    return sessions.first;
  }

  bool _isMobilePopoutEligibleSession(VoipSession session) {
    return switch (session.state) {
      VoipState.incoming ||
      VoipState.outgoing ||
      VoipState.connecting ||
      VoipState.connected => true,
      _ => false,
    };
  }

  bool get _usesMobileCallOnlySurface {
    if (PlatformUtils.isIOS) {
      // iOS AVKit owns the PiP window separately. Replacing the Flutter root
      // would make the in-app surface become the PiP surface too.
      return _mobileCallPopoutState.isResizedPopout;
    }

    return _mobileCallPopoutState.usesCallOnlySurface;
  }

  VoipSession? _iosNativePiPKeepAliveSession(bool showMain) {
    if (!PlatformUtils.isIOS || !_mobileCallPopoutState.isPictureInPicture) {
      return null;
    }

    return _mobileCallPopoutSession(showMain, requireCallOnlySurface: false);
  }
}

class _IOSNativePiPKeepAliveSurface extends StatelessWidget {
  const _IOSNativePiPKeepAliveSurface({required this.session});

  final VoipSession session;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      bottom: 0,
      width: 96,
      height: 54,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: Opacity(
            opacity: 0.01,
            child: ClipRect(
              child: TickerMode(
                enabled: false,
                child: RepaintBoundary(
                  child: CallWidget(
                    session,
                    showSessionPopoutButton: false,
                    transparentBackground: true,
                    suppressControls: true,
                    surfaceMode: CallSurfaceMode.pictureInPicture,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileCallPopoutSurface extends StatelessWidget {
  const _MobileCallPopoutSurface({
    required this.session,
    required this.presentationState,
  });

  final VoipSession session;
  final MobileCallPopoutPresentationState presentationState;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: CallWidget(
        session,
        showSessionPopoutButton: false,
        transparentBackground: true,
        surfaceMode: presentationState.surfaceMode,
        suppressControls: false,
      ),
    );
  }
}

class AppStarter with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.detached) return;
    if (loading != null) {
      await loading;
    }

    if (isHeadless) {
      startGui();
    }

    super.didChangeAppLifecycleState(state);
  }
}
