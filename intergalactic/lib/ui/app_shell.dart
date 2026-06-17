import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/bug_report/crash_report_prompt.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/utils/custom_safe_area.dart';
import 'package:intergalactic/utils/focus_node_monitor.dart';
import 'package:intergalactic/utils/text_scale_changer.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/config/style/theme_dark.dart';

class IntergalacticAppShell extends StatelessWidget {
  const IntergalacticAppShell({
    super.key,
    required this.preferences,
    required this.clientManager,
    required this.home,
    this.initialTheme,
    this.navigatorKey,
  });

  final Preferences preferences;
  final ClientManager clientManager;
  final Widget home;
  final ThemeData? initialTheme;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return CustomSafeArea(
      child: FocusNodeMonitor(
        child: TextScaleChanger(
          child: ThemeChanger(
            shouldFollowSystemTheme: () =>
                preferences.shouldFollowSystemTheme.value,
            getDarkTheme: () {
              return preferences.resolveTheme(
                overrideBrightness: Brightness.dark,
              );
            },
            getLightTheme: () {
              return preferences.resolveTheme(
                overrideBrightness: Brightness.light,
              );
            },
            initialTheme: initialTheme ?? ThemeDark.theme,
            materialAppBuilder: (context, theme) {
              return MaterialApp(
                title: BuildConfig.app,
                theme: theme,
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                builder: (context, child) => Provider<ClientManager>.value(
                  value: clientManager,
                  child: child,
                ),
                home: CrashReportPrompt(child: home),
              );
            },
          ),
        ),
      ),
    );
  }
}
