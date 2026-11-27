import 'package:intergalactic/client/components/push_notification/ios/nse_diagnostic_counter.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:intergalactic/client/components/push_notification/room_notification_snooze.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:path/path.dart' as p;

/// The local-only notification controls the extension has to honour
/// (S&C condition C2), captured as plain values so the snapshot builder is a
/// pure function of them and can be tested without a preferences store.
class NotificationPolicyInputs {
  const NotificationPolicyInputs({
    required this.notificationsEnabled,
    required this.notificationMode,
    required this.previewChoiceCompleted,
    required this.previewChoice,
    required this.showMediaInNotifications,
    required this.formatNotificationBody,
    required this.previewUrlInNotifications,
    required this.developerMode,
    required this.snoozes,
  });

  /// Reads the live preferences. Only the host calls this.
  factory NotificationPolicyInputs.fromPreferences(
    Preferences prefs, {
    DateTime? now,
  }) {
    final snoozes = prefs.getRoomNotificationSnoozes(now: now);
    return NotificationPolicyInputs(
      notificationsEnabled: prefs.enableNotifications.value,
      notificationMode: prefs.notificationMode.value,
      previewChoiceCompleted:
          prefs.notificationPreviewPrivacyChoiceCompleted.value,
      previewChoice: prefs.notificationPreviewPrivacyChoiceValue.value,
      showMediaInNotifications: prefs.showMediaInNotifications.value,
      formatNotificationBody: prefs.formatNotificationBody.value,
      previewUrlInNotifications: prefs.previewUrlInNotifications.value,
      developerMode: prefs.developerMode.value,
      snoozes: snoozes.entries
          .map((e) => SnoozeInput(key: e.key, until: e.value.snoozedUntil))
          .toList(growable: false),
    );
  }

  final bool notificationsEnabled;
  final String notificationMode;
  final bool previewChoiceCompleted;
  final String previewChoice;
  final bool showMediaInNotifications;
  final bool formatNotificationBody;
  final bool previewUrlInNotifications;

  /// Fail-closed enablement for the temporary E1-E10 backup-decrypt path.
  final bool developerMode;
  final List<SnoozeInput> snoozes;
}

/// One active snooze: the preferences key (`clientId::roomId`) and its end.
class SnoozeInput {
  const SnoozeInput({required this.key, required this.until});

  final String key;
  final DateTime until;
}

/// Host side of the policy snapshot (S&C C3, REVIEW's staleness ruling).
///
/// The shape, and why each part is the way it is:
///
/// - **Policy only.** Booleans and enumerations from [NotificationPolicyInputs],
///   plus snoozes as `(digest, expiry)`. No content, no names, no counts, no
///   per-event record, no path, no free text, and no timestamp other than the
///   snooze expiries.
/// - **Identifiers only as a keyed digest.** The extension has `client_id` and
///   `room_id` in the push payload and needs a yes/no, so it computes
///   HMAC-SHA256 over `clientId::roomId` with the key carried in the file and
///   matches. The file therefore holds no room id in the clear.
///
///   What that buys, stated exactly, because this used to claim more than it
///   delivers: the digest resists a reader who has the DIGESTS but not the
///   key. It does not resist a reader who has this file, because
///   `digest_key` is written into it. Room identifiers are low-entropy and
///   enumerable from the account's own data, so someone holding a stray copy
///   can recompute the digests and learn which rooms are snoozed. The earlier
///   wording, "a stray copy of this file names no room", was a stronger claim
///   than the design supports.
///
///   Moving the key to a Keychain item shared with the App Group would
///   restore the stronger property. That is native work and needs a device to
///   verify, so it is an owner decision in the queue rather than a silent
///   design change here - and the file's own protection class, not the
///   digest, is what actually keeps this out of a stray reader's hands today.
/// - **Fixed key set, hard ceilings, fail closed on overflow.** More than
///   [maxSnoozes] entries or more than [maxBytes] on disk is written as an
///   explicitly undecidable snapshot, which the extension treats exactly like
///   a missing one: it delivers the gateway's generic payload. Never a
///   silently truncated list.
/// - **A file, in its own directory, under `completeUntilFirstUserAuthentication`
///   read back, and excluded from backup.** If the class does not read back
///   the file is deleted rather than left unprotected, and the extension
///   fails closed on its absence.
/// - **Written in the same operation as the preference change**, through
///   `Preference.afterWrite`, so the staleness window is a crash window. No
///   wall-clock expiry on the whole snapshot: a force-quit device is the case
///   the extension exists for.
/// - **Deleted on data reset, and when the last account is removed.** With an
///   account still signed in the snapshot is rewritten instead, since it
///   describes the device's preferences, not one account.
class NotificationPolicySnapshot {
  NotificationPolicySnapshot._();

  static const String directoryName = 'notification-policy';
  static const String fileName = 'policy.json';
  static const int version = 1;
  static const int maxSnoozes = 64;
  static const int maxBytes = 8 * 1024;
  static const int digestKeyBytes = 32;
  static const int digestHexLength = 32;

  /// The preference keys whose change rewrites the snapshot.
  ///
  /// Derived from `Preferences` rather than restated here. These strings used
  /// to be duplicated, so renaming a preference key would silently stop the
  /// snapshot tracking it and leave the extension evaluating a STALE policy
  /// with full confidence - the one fail-OPEN path in an otherwise fail-closed
  /// design. Reading the set from the owner of those constants removes that
  /// drift instead of testing for it.
  static Set<String> get watchedKeys => preferences.notificationPolicyKeys;

  static const String _source = 'notification-policy';

  /// Replaceable in tests.
  @visibleForTesting
  static AppGroupStorageHost? host;

  @visibleForTesting
  static bool? platformIsIOS;

  static bool get _enabled => platformIsIOS ?? PlatformUtils.isIOS;

  /// `Preference.afterWrite` target.
  static Future<void> onPreferenceWritten(String key) async {
    if (!_enabled || !watchedKeys.contains(key)) {
      return;
    }
    await write();
  }

  /// `Preference.afterClear` target: an in-app data reset.
  static Future<void> onPreferencesCleared() async {
    if (!_enabled) {
      return;
    }
    await delete();
    await NseDiagnosticCounter.delete();
  }

  /// After startup, logout or account removal.
  static Future<void> onAccountsChanged({required int clientCount}) async {
    if (!_enabled) {
      return;
    }
    if (clientCount == 0) {
      await delete();
      await NseDiagnosticCounter.delete();
    } else {
      await write();
      await NseDiagnosticCounter.onLaunch();
    }
  }

  /// Orders every snapshot mutation against every other one.
  ///
  /// `onPreferenceWritten` fires once per preference write and nothing else
  /// ordered the resulting calls, so two `write()`s reached the same
  /// `policy.json.tmp`: one could rename the file while the other was still
  /// writing it, publishing a torn document. The extension fails closed on a
  /// malformed file, so the user silently loses policy-correct notifications
  /// until the next preference change rewrites it. `delete()` racing a
  /// `write()` is the same hazard with the outcome reversed.
  ///
  /// Ordering rather than a unique staging name per write, which is the other
  /// obvious fix: a unique name stops two writers sharing a buffer but not one
  /// writer's rename landing between another's write and rename, so the
  /// published file could still be the older of the two. Every caller here is
  /// on the main isolate, so a chain is both sufficient and checkable by
  /// reading - and it lets the staging name stay fixed, which the failure-path
  /// test asserts on by name.
  static Future<void> _mutations = Future<void>.value();

  static Future<void> _serialised(Future<void> Function() action) {
    final next = _mutations.then((_) => action());
    // The chain must survive a failed link. Each action below logs and
    // swallows its own errors, but an unguarded chain would latch on the first
    // escape and silently stop every later write.
    _mutations = next.catchError((Object _) {});
    return next;
  }

  /// Builds and writes the snapshot from the live preferences. Never throws:
  /// a failure is logged as a class and leaves either the previous snapshot
  /// or no snapshot, both of which the extension handles by failing closed.
  static Future<void> write({DateTime? now}) {
    if (!_enabled) {
      return Future<void>.value();
    }
    return _serialised(() => _write(now: now));
  }

  static Future<void> _write({DateTime? now}) async {
    try {
      final directory = await _directory();
      if (directory == null) {
        return;
      }
      final inputs = NotificationPolicyInputs.fromPreferences(
        preferences,
        now: now,
      );
      await writeInputs(inputs, directory: directory, now: now);
    } catch (error) {
      Log.e(
        'Notification policy snapshot write failed: ${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
  }

  static Future<void> delete() {
    if (!_enabled) {
      return Future<void>.value();
    }
    return _serialised(_delete);
  }

  static Future<void> _delete() async {
    try {
      final directory = await _directory();
      if (directory == null) {
        return;
      }
      await deleteIn(directory);
    } catch (error) {
      Log.e(
        'Notification policy snapshot delete failed: ${error.runtimeType}',
        category: LogCategory.notifications,
        source: _source,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Pure parts, testable without a device

  /// The JSON document for [inputs], or the undecidable form when a ceiling
  /// is exceeded. [digestKey] must be [digestKeyBytes] long.
  static Map<String, Object?> build(
    NotificationPolicyInputs inputs, {
    required List<int> digestKey,
    DateTime? now,
  }) {
    if (digestKey.length != digestKeyBytes) {
      throw ArgumentError.value(
        digestKey.length,
        'digestKey',
        'Expected $digestKeyBytes bytes',
      );
    }
    if (!inputs.previewChoiceCompleted) {
      // The user has not made the preview choice yet, so there is no policy
      // to evaluate against. Undecidable, not "default to rich".
      return _undecidable('preview_choice_not_made');
    }
    final current = now ?? DateTime.now();
    final active = inputs.snoozes
        .where((s) => s.until.isAfter(current))
        .toList(growable: false);
    if (active.length > maxSnoozes) {
      return _undecidable('snooze_overflow');
    }
    final hmac = Hmac(sha256, digestKey);
    return <String, Object?>{
      'version': version,
      'notifications_enabled': inputs.notificationsEnabled,
      'notification_mode': inputs.notificationMode,
      'preview_choice': inputs.previewChoice,
      'show_media': inputs.showMediaInNotifications,
      'format_body': inputs.formatNotificationBody,
      'preview_url': inputs.previewUrlInNotifications,
      'developer_mode': inputs.developerMode,
      'digest_key': _hex(digestKey),
      'snoozes': [
        for (final s in active)
          <String, Object?>{
            'digest': digest(hmac, s.key),
            'until_ms': s.until.toUtc().millisecondsSinceEpoch,
          },
      ],
    };
  }

  /// The digest the extension recomputes: HMAC-SHA256 of the snooze key
  /// (`clientId::roomId`, see [roomNotificationSnoozeKey]), first 16 bytes,
  /// lower-case hex.
  static String digest(Hmac hmac, String key) {
    final mac = hmac.convert(utf8.encode(key)).bytes;
    return _hex(mac.sublist(0, digestHexLength ~/ 2));
  }

  static Map<String, Object?> _undecidable(String reason) => <String, Object?>{
    'version': version,
    'undecidable': reason,
  };

  static String _hex(List<int> bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static List<int> newDigestKey([Random? random]) {
    final rng = random ?? Random.secure();
    return List<int>.generate(digestKeyBytes, (_) => rng.nextInt(256));
  }

  /// Writes [inputs] into [directory] atomically and protects the result.
  /// Exposed for tests; [write] is the host entry point.
  @visibleForTesting
  static Future<void> writeInputs(
    NotificationPolicyInputs inputs, {
    required String directory,
    DateTime? now,
    AppGroupStorageHost? storage,
    List<int>? digestKey,
  }) async {
    final target = storage ?? host ?? const ChannelAppGroupStorageHost();
    final document = build(
      inputs,
      digestKey: digestKey ?? newDigestKey(),
      now: now,
    );
    var encoded = jsonEncode(document);
    if (utf8.encode(encoded).length > maxBytes) {
      encoded = jsonEncode(_undecidable('size_overflow'));
    }

    final dir = Directory(directory);
    final created = !await dir.exists();
    await dir.create(recursive: true);
    if (created) {
      await _protect(target, directory);
    }

    final path = p.join(directory, fileName);
    final staging = File('$path.tmp');
    await staging.writeAsString(encoded, flush: true);
    await staging.rename(path);

    try {
      await _protect(target, path);
      await target.excludeFromBackup(path);
    } catch (_) {
      // Fail closed: a snapshot that cannot be protected is not left on disk.
      // Its absence makes the extension deliver the generic payload.
      try {
        await File(path).delete();
      } catch (_) {}
      Log.e(
        'Notification policy snapshot removed: protection unavailable',
        category: LogCategory.notifications,
        source: _source,
      );
      return;
    }
    Log.d(
      'Notification policy snapshot written '
      '${document.containsKey('undecidable') ? 'undecidable=${document['undecidable']}' : 'snoozes=${(document['snoozes'] as List).length}'}',
      category: LogCategory.notifications,
      source: _source,
    );
  }

  @visibleForTesting
  static Future<void> deleteIn(String directory) async {
    final file = File(p.join(directory, fileName));
    if (await file.exists()) {
      await file.delete();
    }
    final staging = File(p.join(directory, '$fileName.tmp'));
    if (await staging.exists()) {
      await staging.delete();
    }
    Log.i(
      'Notification policy snapshot deleted',
      category: LogCategory.notifications,
      source: _source,
    );
  }

  static Future<void> _protect(AppGroupStorageHost target, String path) async {
    final reported = await target.protectItem(path);
    if (reported != AppGroupStorageHost.expectedProtectionClass) {
      throw StateError('protection class did not read back');
    }
  }

  static String? _cachedDirectory;

  /// The snapshot directory, for the developer page's tamper actions that
  /// exercise S&C required check (1) on a device: with the file deleted,
  /// corrupted or truncated the extension must deliver the generic payload.
  static Future<String?> developerDirectory() => _directory();

  /// S&C required check (2): the snapshot as the live preferences would
  /// write it, except with media previews off. The iOS settings page does
  /// not expose the media switch (it is a desktop option), so this is the
  /// only way to put `show_media: false` in front of the extension on a
  /// device. Developer page only; the next preference write replaces it.
  static Future<void> developerWriteWithMediaOff() async {
    if (!_enabled) {
      return;
    }
    final directory = await _directory();
    if (directory == null) {
      return;
    }
    final live = NotificationPolicyInputs.fromPreferences(preferences);
    await writeInputs(
      NotificationPolicyInputs(
        notificationsEnabled: live.notificationsEnabled,
        notificationMode: live.notificationMode,
        previewChoiceCompleted: live.previewChoiceCompleted,
        previewChoice: live.previewChoice,
        showMediaInNotifications: false,
        formatNotificationBody: live.formatNotificationBody,
        previewUrlInNotifications: live.previewUrlInNotifications,
        developerMode: live.developerMode,
        snoozes: live.snoozes,
      ),
      directory: directory,
    );
  }

  static Future<String?> _directory() async {
    final cached = _cachedDirectory;
    if (cached != null) {
      return cached;
    }
    final target = host ?? const ChannelAppGroupStorageHost();
    final container = await target.containerPath();
    if (container == null || container.isEmpty) {
      Log.w(
        'Notification policy snapshot: App Group unavailable',
        category: LogCategory.notifications,
        source: _source,
      );
      return null;
    }
    return _cachedDirectory = p.join(container, directoryName);
  }

  @visibleForTesting
  static void resetForTests() {
    _cachedDirectory = null;
    host = null;
    platformIsIOS = null;
  }
}
