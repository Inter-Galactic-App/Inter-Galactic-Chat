/// Web: no App Group, no extension. Signatures mirror the io implementation
/// so the analyzer, which resolves the conditional export to this file, sees
/// the same surface.
class NotificationPolicySnapshot {
  NotificationPolicySnapshot._();

  static Future<void> onPreferenceWritten(String key) async {}

  static Future<void> onPreferencesCleared() async {}

  static Future<void> onAccountsChanged({required int clientCount}) async {}

  static Future<void> write({DateTime? now}) async {}

  static Future<void> delete() async {}

  static Future<String?> developerDirectory() async => null;

  static Future<void> developerWriteWithMediaOff() async {}
}
