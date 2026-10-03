import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';

/// The account-wide notification mode, and the two rules that govern it.
///
/// This lives in the client layer, not with the settings page, because
/// [resolveNotificationMode] has to be the SINGLE reader. Two readers is what
/// went wrong before: the settings page resolved the mode from the server
/// master rule while `MatrixRoom.shouldNotify` read the raw device-wide
/// `notificationMode` preference, so local mute survived only because
/// `_setNotificationMode` wrote a value this file documents as stale.
///
/// Neither function is given anything that can register, delete or refresh a
/// Matrix pusher: a mode change writes the master push rule and preferences and
/// nothing else, which is the property the integration queue asks to hold.
enum NotificationMode {
  all,
  mentions,
  mute;

  static NotificationMode fromPreference(String value) {
    return switch (value) {
      'mentions' => NotificationMode.mentions,
      'mute' => NotificationMode.mute,
      _ => NotificationMode.all,
    };
  }

  String get preferenceValue => switch (this) {
    NotificationMode.all => 'all',
    NotificationMode.mentions => 'mentions',
    NotificationMode.mute => 'mute',
  };
}

/// Which mode an account is currently in.
///
/// Once an account has migrated, the SERVER master rule is authoritative, so
/// the answer is the same on every signed-in device AND is per-account: muting
/// one account must not silence another. `enableNotifications` is the retired
/// local gate and is only consulted before migration; a migrated account whose
/// local preference still reads `mute` is holding a stale value and is reported
/// as [NotificationMode.all].
NotificationMode resolveNotificationMode({
  required bool isMigrated,
  required bool serverMuted,
  required bool enableNotifications,
  required String localModeValue,
}) {
  if (isMigrated) {
    if (serverMuted) {
      return NotificationMode.mute;
    }
    final localMode = NotificationMode.fromPreference(localModeValue);
    return localMode == NotificationMode.mute
        ? NotificationMode.all
        : localMode;
  }

  if (enableNotifications == false) {
    return NotificationMode.mute;
  }

  return NotificationMode.fromPreference(localModeValue);
}

enum NotificationModeWriteResult { applied, failed }

/// Applies [mode] to a Matrix account: master push rule first, local state only
/// once the server has accepted it.
///
/// A failed or offline SERVER write leaves the account unmigrated and its
/// preferences untouched, so a lost write can never be mistaken for a completed
/// migration. Once the server has accepted, the migration is recorded before
/// the preference writes, because the migration flag is what makes
/// [resolveNotificationMode] read the server at all: a failure between the two
/// would otherwise leave a server-muted account reporting its stale local mode.
/// The result is still [NotificationModeWriteResult.failed] either way.
///
/// `notificationMode` is written for EVERY mode, `mute` included. It is the
/// device-wide All/Mentions store, and [resolveNotificationMode] is what
/// decides whether a `mute` in it still means anything for a given account -
/// so writing it here is not a second source of truth, and skipping it for
/// mute would leave the value describing a different mode than the one chosen.
Future<NotificationModeWriteResult> applyMatrixNotificationMode({
  required NotificationMode mode,
  required String clientIdentifier,
  required Future<void> Function(bool muted) setMuted,
  required Preferences preferences,
}) async {
  try {
    await setMuted(mode == NotificationMode.mute);
    // Immediately after the server write, and before anything local. Whatever
    // fails next, the account then resolves from the rule the server actually
    // holds rather than from a local value that describes a different mode.
    await preferences.markGlobalMutePushRuleMigrated(clientIdentifier);
    await preferences.notificationMode.set(mode.preferenceValue);
    await preferences.enableNotifications.set(true);
    return NotificationModeWriteResult.applied;
  } catch (error, trace) {
    Log.onError(error, trace);
    return NotificationModeWriteResult.failed;
  }
}
