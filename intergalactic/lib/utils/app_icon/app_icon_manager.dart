import 'dart:async';

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/utils/app_icon/app_icon_utils.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class AppIconManager with WidgetsBindingObserver {
  AppIconManager._();

  static final AppIconManager instance = AppIconManager._();

  static const MethodChannel _channel =
      MethodChannel("chat.intergalactic.app/app_icon");

  StreamSubscription? _preferenceSubscription;
  bool _initialized = false;

  bool get _supportsRuntimeIcon =>
      BuildConfig.WINDOWS ||
      BuildConfig.LINUX ||
      PlatformUtils.isIOS ||
      PlatformUtils.isAndroid;

  Future<void> init() async {
    if (_initialized) {
      return;
    }

    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _preferenceSubscription = preferences.appIconMode.onChanged.listen((_) {
      apply();
    });

    await apply();
  }

  Future<void> apply() async {
    if (!_supportsRuntimeIcon) {
      return;
    }

    try {
      await _channel.invokeMethod("setAppIcon", {
        "assetPath": AppIconUtils.roundedAssetPath(),
        "brightness": AppIconUtils.resolveBrightness().name,
        "mode": preferences.appIconMode.value,
        "iconName": _iosAlternateIconName(),
      });
    } on MissingPluginException {
      // The runtime icon bridge is optional on each platform runner.
    } on PlatformException {
      // Keep the preference usable even if a platform runner build lacks support.
    }
  }

  String? _iosAlternateIconName() {
    if (!PlatformUtils.isIOS) {
      return null;
    }

    final brightness = AppIconUtils.resolveBrightness();
    return brightness == Brightness.dark ? "AppIcon-Dark" : null;
  }

  @override
  void didChangePlatformBrightness() {
    if (AppIconUtils.currentMode == AppIconMode.system) {
      apply();
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _preferenceSubscription?.cancel();
    _preferenceSubscription = null;
    _initialized = false;
  }
}
