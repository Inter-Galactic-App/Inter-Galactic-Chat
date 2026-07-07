import 'dart:async';

export 'package:intergalactic/config/app_globals.dart' show preferences;

import 'package:intergalactic/cache/file_cache.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/activity/publishers/matrix_activity_presence_publisher.dart';
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
import 'package:intergalactic/client/components/voip/audio/ios_call_audio_session.dart';
import 'package:intergalactic/client/components/soundboard/soundboard_playback_service.dart';
import 'package:intergalactic/client/components/push_notification/web/web_app_badge_manager.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_notification_bridge.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
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
  try {
    if (BuildConfig.WEB) {
      var info = await DeviceInfoPlugin().deviceInfo;
      if (info is WebBrowserInfo) {
        Layout.browserInfo = info;
      }
    }

    ensureBindingInit();
    configureAndroidPhotoPicker();

    if (PlatformUtils.isLinux || PlatformUtils.isWindows) {
      if (await SingleInstance.tryConnectToMainInstance(commandLineArgs)) {
        exitApplication(0);
      } else {
        SingleInstance.becomeMainInstance();
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
  onStartupPhase?.call(StartupPhase.preferences);
  initSqfliteFfi();
  await preferences.init();
  if (onStartupThemeReady != null) {
    onStartupThemeReady(await preferences.resolveTheme());
  }
  await IosCallAudioSession.configureStartupVoiceProcessingBypass();
  onStartupPhase?.call(StartupPhase.localServices);
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
  onStartupPhase?.call(StartupPhase.storage);
  await initDatabaseServer();

  fileCache = FileCache.getFileCacheInstance();

  await Future.wait([
    if (fileCache != null) fileCache!.init(),
    GlobalConfig.init(),
  ]);

  onStartupPhase?.call(StartupPhase.accounts);
  clientManager = await ClientManager.init();
  onStartupPhase?.call(StartupPhase.appServices);
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

Future<void> initActivityService() async {
  if (BuildConfig.MOBILE && !BuildConfig.IOS && !BuildConfig.ANDROID) {
    return;
  }

  activityService.configure(
    settingsProvider: () => ActivitySettings.fromPreferences(preferences),
  );

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
Future<void> startGui() async {
  String? initialRoomId;
  String? initialClientId;

  await initGuiRequirements();

  var webOpenRoom = getInitialWebOpenRoom();
  if (webOpenRoom.$2 != null) {
    initialClientId = webOpenRoom.$1;
    initialRoomId = webOpenRoom.$2;
  }

  if (PlatformUtils.isAndroid) {
    enableEdgeToEdge();

    var initialIntent = await getInitialAppIntent();
    appReceivedIntentStream.listen((event) {
      Log.i("Received intent: ${initialIntent}");
      var uri = AndroidIntentHelper.getUriFromIntent(event);
      if (uri is OpenRoomURI) {
        EventBus.openRoom.add((uri.roomId, uri.clientId));
      }
    });

    Log.i("Initial intent: ${initialIntent}");

    var uri = AndroidIntentHelper.getUriFromIntent(initialIntent);

    if (uri is OpenRoomURI) {
      initialClientId = uri.clientId;
      initialRoomId = uri.roomId;
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
