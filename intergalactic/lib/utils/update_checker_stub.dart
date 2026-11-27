import 'package:flutter/material.dart';

class UpdateChecker {
  static bool foundUpdate = false;

  static bool get shouldCheckForUpdates => false;

  static bool isWindowsUpdaterInvocation(List<String> args) => false;

  static Future<bool> maybeRunWindowsUpdater(List<String> args) async => false;

  static Future<bool> checkForStartupUpdate() async => false;

  static void startPeriodicChecks() {}

  static void stopPeriodicChecks() {}

  static Future<void> checkForUpdates() async {}

  static Future<void> doUpdateAction(
      BuildContext context, bool canAutoUpdate) async {}

  static Future<void> windowsUpdateAction(
      BuildContext context, bool canAutoUpdate) async {}
}
