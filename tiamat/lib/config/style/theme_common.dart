import 'package:flutter/foundation.dart';

class ThemeCommon {
  static List<String>? fontFamilyFallback() {
    return [
      ..._nativeEmojiFontsForPlatform(),
      "EmojiFont",
    ];
  }

  static List<String> _nativeEmojiFontsForPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const ["Apple Color Emoji"];
      case TargetPlatform.windows:
        return const ["Segoe UI Emoji"];
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
        return const ["Noto Color Emoji"];
    }
  }
}
