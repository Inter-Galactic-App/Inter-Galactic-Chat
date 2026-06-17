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
import 'package:intergalactic/client/components/soundboard/soundboard_playback_service.dart';
import 'package:intergalactic/client/components/push_notification/web/web_app_badge_manager.dart';
import 'package:intergalactic/client/components/push_notification/web/web_push_notification_bridge.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_service.dart';
import 'package:intergalactic/client/components/voip/audio/noise_suppression/noise_suppression_tuning_profile.dart';
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
import 'package:intergalactic/ui/app_shell.dart';
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
import 'package:tiamat/tiamat.dart' as tiamat;

final GlobalKey<NavigatorState> navigator = GlobalKey();
FileCache? fileCache;
ShortcutsManager shortcutsManager = ShortcutsManager();
BackgroundTaskManager backgroundTaskManager = BackgroundTaskManager();
CallPopoutController callPopoutController = CallPopoutController();
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
      storedClientId:
          preferences.isInit ? preferences.activitySpotifyClientId.value : null,
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
  runZonedGuarded<Future<void>>(() async {
    isHeadless = true;
    Log.prefix = "unified-push";
    WidgetsFlutterBinding.ensureInitialized();
    await Log.initialize();
    Log.installFlutterErrorHandler();
    Log.installPlatformDispatcherErrorHandler();
    await preferences.init();
    await UnifiedPushNotifier().init();
  }, (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Unhandled unified push entrypoint error',
      category: LogCategory.notifications,
      source: 'unified-push',
      flush: true,
    );
  }, zoneSpecification: Log.spec);
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
  runZonedGuarded<Future<void>>(() async {
    Log.prefix = "bubble";
    isBubble = true;
    ensureBindingInit();
    await Log.initialize();
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

    runApp(MaterialApp(
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
        )));
  }, (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Unhandled bubble entrypoint error',
      category: LogCategory.notifications,
      source: 'bubble',
      flush: true,
    );
  }, zoneSpecification: Log.spec);
}

void main(List<String> args) {
  commandLineArgs = args;

  if (!UpdateChecker.isWindowsUpdaterInvocation(args) &&
      runDesktopWebViewTitleBarWidget(args)) {
    return;
  }

  final diagnosticsOptions = RuntimeDiagnosticsOptions.fromArgs(args);
  Log.configureRuntimeOptions(diagnosticsOptions);
  runZonedGuarded<Future<void>>(() async {
    Log.prefix = "main";
    ensureBindingInit();
    await Log.initialize(options: diagnosticsOptions);
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
  }, (error, stackTrace) {
    Log.onError(
      error,
      stackTrace,
      content: 'Unhandled app zone error',
      category: LogCategory.app,
      source: 'run-zoned-guarded',
      flush: true,
    );
  }, zoneSpecification: Log.spec);
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

    isHeadless = PlatformUtils.isAndroid &&
        AppLifecycleState.detached == WidgetsBinding.instance.lifecycleState;

    loading = initNecessary();

    if (isHeadless) {
      WidgetsBinding.instance.addObserver(AppStarter());
      await loading;
      return;
    } else {
      await loading;
    }

    SystemWideShortcuts.init();

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

/// Initializes the bare necessities for the app to run in headless mode
Future<void> initNecessary() async {
  initSqfliteFfi();
  await preferences.init();
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
  await initDatabaseServer();

  fileCache = FileCache.getFileCacheInstance();

  await Future.wait([
    if (fileCache != null) fileCache!.init(),
    GlobalConfig.init(),
  ]);

  clientManager = await ClientManager.init();
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
      SystemUiMode.edgeToEdge); // Enable Edge-to-Edge on Android 10+
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor:
          Colors.transparent, // Setting a transparent navigation bar color
      systemNavigationBarContrastEnforced: true, // Default
      systemNavigationBarIconBrightness: theme.brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark));
}

class App extends StatelessWidget {
  const App(
      {super.key,
      required this.clientManager,
      this.initialTheme,
      this.initialRoom,
      this.initialClientId});
  final ThemeData? initialTheme;
  final ClientManager clientManager;

  final String? initialRoom;
  final String? initialClientId;

  @override
  Widget build(BuildContext context) {
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
  const AppView(
      {required this.clientManager,
      super.key,
      this.initialClientId,
      this.initialRoom});
  final ClientManager clientManager;
  final String? initialRoom;
  final String? initialClientId;

  @override
  State<AppView> createState() => _AppViewState();
}

class _AppViewState extends State<AppView> {
  StreamSubscription? _onClientRemovedSubscription;
  StreamSubscription? _onClientAddedSubscription;

  @override
  void initState() {
    super.initState();
    _onClientRemovedSubscription =
        widget.clientManager.onClientRemoved.stream.listen((_) {
      if (!widget.clientManager.isLoggedIn()) {
        navigator.currentState?.popUntil((route) => route.isFirst);
      }
      if (!mounted) return;
      setState(() {});
    });
    _onClientAddedSubscription =
        widget.clientManager.onClientAdded.stream.listen((_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _onClientRemovedSubscription?.cancel();
    _onClientAddedSubscription?.cancel();
    unawaited(soundboardPlaybackService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showMain = widget.clientManager.isLoggedIn();
    final content = showMain
        ? MainPage(
            widget.clientManager,
            initialClientId: widget.initialClientId,
            initialRoom: widget.initialRoom,
          )
        : LoginPage(onSuccess: (_) {
            if (!mounted) return;
            setState(() {});
          });

    if (!showMain || !BuildConfig.DESKTOP) {
      return content;
    }

    return Stack(
      children: [
        content,
        DesktopCallPopoutHost(widget.clientManager.callManager),
      ],
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
