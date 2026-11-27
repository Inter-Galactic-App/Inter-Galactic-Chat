import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/main.dart';
import 'package:flutter/widgets.dart';

enum AppIconMode {
  system,
  light,
  dark,
}

class AppIconAssets {
  static const String darkAndroid =
      "assets/images/app_icon/dark/app_icon_android.png";
  static const String darkFilled =
      "assets/images/app_icon/dark/app_icon_filled.png";
  static const String darkRounded =
      "assets/images/app_icon/dark/app_icon_rounded.png";
  static const String darkTransparent =
      "assets/images/app_icon/dark/app_icon_transparent.png";
  static const String darkTransparentCropped =
      "assets/images/app_icon/dark/app_icon_transparent_cropped.png";

  static const String lightAndroid =
      "assets/images/app_icon/light/app_icon_android.png";
  static const String lightFilled =
      "assets/images/app_icon/light/app_icon_filled.png";
  static const String lightRounded =
      "assets/images/app_icon/light/app_icon_rounded.png";
  static const String lightTransparent =
      "assets/images/app_icon/light/app_icon_transparent.png";
  static const String lightTransparentCropped =
      "assets/images/app_icon/light/app_icon_transparent_cropped.png";
}

class AppIconUtils {
  static AppIconMode get currentMode {
    return switch (preferences.appIconMode.value) {
      "light" => AppIconMode.light,
      "dark" => AppIconMode.dark,
      _ => AppIconMode.system,
    };
  }

  static Brightness resolveBrightness({Brightness? systemBrightness}) {
    return switch (currentMode) {
      AppIconMode.light => Brightness.light,
      AppIconMode.dark => Brightness.dark,
      AppIconMode.system => systemBrightness ??
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };
  }

  static String transparentCroppedAssetPath({Brightness? systemBrightness}) {
    return switch (resolveBrightness(systemBrightness: systemBrightness)) {
      Brightness.light => AppIconAssets.lightTransparentCropped,
      Brightness.dark => AppIconAssets.darkTransparentCropped,
    };
  }

  static String launcherPreviewAssetPath({Brightness? systemBrightness}) {
    if (!PlatformUtils.isAndroid) {
      return transparentCroppedAssetPath(systemBrightness: systemBrightness);
    }

    return switch (resolveBrightness(systemBrightness: systemBrightness)) {
      Brightness.light => AppIconAssets.lightAndroid,
      Brightness.dark => AppIconAssets.darkAndroid,
    };
  }

  static String transparentAssetPath({Brightness? systemBrightness}) {
    return switch (resolveBrightness(systemBrightness: systemBrightness)) {
      Brightness.light => AppIconAssets.lightTransparent,
      Brightness.dark => AppIconAssets.darkTransparent,
    };
  }

  static String roundedAssetPath({Brightness? systemBrightness}) {
    return switch (resolveBrightness(systemBrightness: systemBrightness)) {
      Brightness.light => AppIconAssets.lightRounded,
      Brightness.dark => AppIconAssets.darkRounded,
    };
  }

  static String filledAssetPath({Brightness? systemBrightness}) {
    return switch (resolveBrightness(systemBrightness: systemBrightness)) {
      Brightness.light => AppIconAssets.lightFilled,
      Brightness.dark => AppIconAssets.darkFilled,
    };
  }
}
