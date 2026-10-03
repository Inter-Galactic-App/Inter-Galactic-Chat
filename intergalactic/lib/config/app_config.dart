library;

import 'package:intergalactic/client/matrix/database/app_group/drift_database_location.dart';
import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

class AppConfig {
  static const String _devProfileDirEnvironment =
      "INTERGALACTIC_DEV_PROFILE_DIR";

  /// Where the dev-profile override is read from. Replaceable in tests only:
  /// the process environment cannot be set from inside a Dart test, and the
  /// override's priority over the App Group branch (REVIEW R6) is exactly the
  /// thing a test has to be able to exercise.
  @visibleForTesting
  static String? Function(String name) environmentVariable =
      PlatformUtils.environmentVariable;

  static Future<String?> _devProfileRoot() async {
    if (BuildConfig.WEB) {
      return null;
    }

    final rawValue = environmentVariable(_devProfileDirEnvironment)?.trim();
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

  /// True when `INTERGALACTIC_DEV_PROFILE_DIR` redirects this profile. The
  /// App Group migration consults this so a redirected profile never moves.
  static Future<bool> hasDevProfileOverride() async {
    return await _devProfileRoot() != null;
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

  /// The Matrix account database root.
  ///
  /// On iOS this is the App Group container once the migration has made it
  /// authoritative (`DriftDatabaseLocation.prepare`, run at startup before any
  /// client opens a database), so the Notification Service Extension can read
  /// it. Everywhere else, and on iOS before or without the migration, it is
  /// `<db>/account/drift` exactly as before.
  ///
  /// The dev-profile override is re-consulted HERE, not only inside
  /// [getDatabasePath] (REVIEW R6): the App Group branch does not go through
  /// [getDatabasePath], so without this check `INTERGALACTIC_DEV_PROFILE_DIR`
  /// would silently stop isolating profiles on iOS. The result for a
  /// redirected profile is byte-identical to the previous delegation.
  static Future<String> getDriftDatabasePath() async {
    if (BuildConfig.WEB) {
      return "commet";
    }
    final devProfileRoot = await _devProfileRoot();
    if (devProfileRoot != null) {
      return join(devProfileRoot, "db", "account", "drift");
    }
    final appGroupRoot = DriftDatabaseLocation.appGroupDriftRoot;
    if (appGroupRoot != null) {
      return appGroupRoot;
    }
    final dir = await getDatabasePath();
    return join(dir, "account", "drift");
  }
}
