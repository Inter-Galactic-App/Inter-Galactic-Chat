library;

import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  static const String _devProfileDirEnvironment =
      "INTERGALACTIC_DEV_PROFILE_DIR";

  static Future<String?> _devProfileRoot() async {
    if (BuildConfig.WEB) {
      return null;
    }

    final rawValue =
        PlatformUtils.environmentVariable(_devProfileDirEnvironment)?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    if (isAbsolute(rawValue)) {
      return normalize(rawValue);
    }

    final safeName = rawValue.replaceAll(RegExp(r"[^A-Za-z0-9_.-]"), "_");
    if (safeName.isEmpty || safeName == "." || safeName == "..") {
      return null;
    }

    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "dev-profiles", safeName);
  }

  static Future<String> getDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final devProfileRoot = await _devProfileRoot();
    if (devProfileRoot != null) {
      return join(devProfileRoot, "db");
    }
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "db");
  }

  static Future<String> getSocketPath() async {
    if (PlatformUtils.isWindows) {
      return r"\\.\pipe\chat.intergalactic.app";
    }

    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "socket");
  }

  static Future<String> getLogDirectoryPath() async {
    if (BuildConfig.WEB) {
      return "logs";
    }
    final devProfileRoot = await _devProfileRoot();
    if (devProfileRoot != null) {
      return join(devProfileRoot, "logs");
    }
    final dir = await getApplicationSupportDirectory();
    return join(dir.path, "logs");
  }

  static Future<String> getDriftDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final dir = await getDatabasePath();
    return join(dir, "account", "drift");
  }
}
