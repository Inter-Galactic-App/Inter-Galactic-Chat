import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
// The io implementation directly: the conditional export resolves to the web
// stub under analysis, and the test surface (build, writeInputs, the fakes)
// exists only on the io side.
import 'package:intergalactic/client/components/push_notification/ios/notification_policy_snapshot_io.dart';
import 'package:intergalactic/client/matrix/database/app_group/app_group_storage.dart';
import 'package:intergalactic/config/app_globals.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

/// NSE Phase C policy snapshot, host side (S&C C3).
///
/// WHAT WOULD MAKE THESE WRONG: a test that only checks the file exists
/// passes for a snapshot with the wrong shape, and the extension fails closed
/// on shape - silently, as a generic notification. So every case here parses
/// the document and asserts the exact key set, and the digest case recomputes
/// the HMAC independently rather than comparing the file to itself.
void main() {
  late Directory tempDir;
  late _FakeHost host;
  final key = List<int>.generate(32, (i) => i * 7 % 256);

  NotificationPolicyInputs inputs({
    bool enabled = true,
    String mode = 'all',
    bool completed = true,
    String choice = 'rich',
    bool showMedia = true,
    bool developerMode = false,
    List<SnoozeInput> snoozes = const [],
  }) => NotificationPolicyInputs(
    notificationsEnabled: enabled,
    notificationMode: mode,
    previewChoiceCompleted: completed,
    previewChoice: choice,
    showMediaInNotifications: showMedia,
    formatNotificationBody: true,
    previewUrlInNotifications: true,
    developerMode: developerMode,
    snoozes: snoozes,
  );

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ig-policy-snapshot');
    host = _FakeHost();
    NotificationPolicySnapshot.host = host;
    NotificationPolicySnapshot.platformIsIOS = true;
  });

  tearDown(() {
    NotificationPolicySnapshot.resetForTests();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('build', () {
    test('carries exactly the fixed key set and nothing identifying', () {
      final now = DateTime.utc(2026, 9, 3, 12);
      final doc = NotificationPolicySnapshot.build(
        inputs(
          snoozes: [
            SnoozeInput(
              key: 'clientAAAA::!room:example.org',
              until: now.add(const Duration(hours: 1)),
            ),
          ],
        ),
        digestKey: key,
        now: now,
      );

      expect(doc.keys.toSet(), {
        'version',
        'notifications_enabled',
        'notification_mode',
        'preview_choice',
        'show_media',
        'format_body',
        'preview_url',
        'developer_mode',
        'digest_key',
        'snoozes',
      });
      final text = jsonEncode(doc);
      expect(text, isNot(contains('clientAAAA')));
      expect(text, isNot(contains('example.org')));
      expect(text, isNot(contains('!room')));
      expect(doc['developer_mode'], isFalse);
      final snoozes = doc['snoozes'] as List;
      expect((snoozes.single as Map).keys.toSet(), {'digest', 'until_ms'});
    });

    test('developer mode is explicit and defaults fail closed', () {
      expect(
        NotificationPolicySnapshot.build(
          inputs(),
          digestKey: key,
        )['developer_mode'],
        isFalse,
      );
      expect(
        NotificationPolicySnapshot.build(
          inputs(developerMode: true),
          digestKey: key,
        )['developer_mode'],
        isTrue,
      );
    });

    test('digest is HMAC-SHA256 of clientId::roomId under the file key', () {
      final now = DateTime.utc(2026, 9, 3, 12);
      const snoozeKey = 'clientAAAA::!room:example.org';
      final doc = NotificationPolicySnapshot.build(
        inputs(
          snoozes: [
            SnoozeInput(
              key: snoozeKey,
              until: now.add(const Duration(hours: 1)),
            ),
          ],
        ),
        digestKey: key,
        now: now,
      );

      // Recomputed independently of the class under test.
      final fileKey = _unhex(doc['digest_key'] as String);
      final entry = (doc['snoozes'] as List).single as Map;
      expect(entry['digest'], _expectedDigest(fileKey, snoozeKey));
      expect(
        entry['until_ms'],
        now.add(const Duration(hours: 1)).millisecondsSinceEpoch,
      );
    });

    test('expired snoozes are dropped', () {
      final now = DateTime.utc(2026, 9, 3, 12);
      final doc = NotificationPolicySnapshot.build(
        inputs(
          snoozes: [
            SnoozeInput(
              key: 'a::b',
              until: now.subtract(const Duration(minutes: 1)),
            ),
            SnoozeInput(
              key: 'c::d',
              until: now.add(const Duration(minutes: 1)),
            ),
          ],
        ),
        digestKey: key,
        now: now,
      );
      expect((doc['snoozes'] as List).length, 1);
      // WHICH one survived, not how many. Inverting the comparison keeps the
      // expired entry and drops the live one, and the count is identical
      // either way; the extension would then stay silent for a room the user
      // has already un-snoozed. Pinned through the digest as well as the
      // expiry, because the digest is the field the extension matches on.
      final entry = (doc['snoozes'] as List).single as Map;
      expect(
        entry['until_ms'],
        now.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
      );
      expect(
        entry['digest'],
        _expectedDigest(_unhex(doc['digest_key'] as String), 'c::d'),
      );
    });

    test('an unmade preview choice is undecidable, not rich', () {
      final doc = NotificationPolicySnapshot.build(
        inputs(completed: false),
        digestKey: key,
      );
      expect(doc, {'version': 1, 'undecidable': 'preview_choice_not_made'});
    });

    test('more snoozes than the ceiling is undecidable, never truncated', () {
      final now = DateTime.utc(2026, 9, 3, 12);
      final doc = NotificationPolicySnapshot.build(
        inputs(
          snoozes: List.generate(
            NotificationPolicySnapshot.maxSnoozes + 1,
            (i) => SnoozeInput(
              key: 'c$i::r$i',
              until: now.add(const Duration(hours: 1)),
            ),
          ),
        ),
        digestKey: key,
        now: now,
      );
      expect(doc['undecidable'], 'snooze_overflow');
      expect(doc.containsKey('snoozes'), isFalse);
    });

    test('rejects a key of the wrong length', () {
      expect(
        () => NotificationPolicySnapshot.build(inputs(), digestKey: [1, 2, 3]),
        throwsArgumentError,
      );
    });
  });

  group('writeInputs', () {
    test(
      'writes atomically, protects file and directory, excludes from backup',
      () async {
        final dir = p.join(tempDir.path, 'notification-policy');
        await NotificationPolicySnapshot.writeInputs(
          inputs(),
          directory: dir,
          storage: host,
          digestKey: key,
        );

        final file = File(p.join(dir, 'policy.json'));
        expect(file.existsSync(), isTrue);
        expect(File(p.join(dir, 'policy.json.tmp')).existsSync(), isFalse);
        final doc = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        expect(doc['preview_choice'], 'rich');
        expect(host.protected, containsAll([dir, file.path]));
        expect(host.excluded, contains(file.path));
      },
    );

    test('a failed protection read-back leaves no file behind', () async {
      final dir = p.join(tempDir.path, 'notification-policy');
      host.reportFor = (path) =>
          path.endsWith('policy.json') ? 'NSFileProtectionNone' : null;

      await NotificationPolicySnapshot.writeInputs(
        inputs(),
        directory: dir,
        storage: host,
        digestKey: key,
      );

      expect(File(p.join(dir, 'policy.json')).existsSync(), isFalse);
      // The staging file is the same data under the same wrong protection
      // class, so leaving it behind is the leak this test exists to refuse.
      // It is absent today because the rename happens before the read-back;
      // the assertion is what keeps a reordering from making it a leak.
      expect(File(p.join(dir, 'policy.json.tmp')).existsSync(), isFalse);
    });

    test('rewrites in place on the next change', () async {
      final dir = p.join(tempDir.path, 'notification-policy');
      await NotificationPolicySnapshot.writeInputs(
        inputs(choice: 'rich'),
        directory: dir,
        storage: host,
        digestKey: key,
      );
      await NotificationPolicySnapshot.writeInputs(
        inputs(choice: 'private'),
        directory: dir,
        storage: host,
        digestKey: key,
      );
      final doc =
          jsonDecode(File(p.join(dir, 'policy.json')).readAsStringSync())
              as Map<String, dynamic>;
      expect(doc['preview_choice'], 'private');
    });

    test('deleteIn removes the snapshot and any staging file', () async {
      final dir = p.join(tempDir.path, 'notification-policy');
      await NotificationPolicySnapshot.writeInputs(
        inputs(),
        directory: dir,
        storage: host,
        digestKey: key,
      );
      File(p.join(dir, 'policy.json.tmp')).writeAsStringSync('{');

      await NotificationPolicySnapshot.deleteIn(dir);

      expect(File(p.join(dir, 'policy.json')).existsSync(), isFalse);
      expect(File(p.join(dir, 'policy.json.tmp')).existsSync(), isFalse);
    });
  });

  group('hooks', () {
    test('only watched keys trigger a write', () async {
      // No container: write() logs and returns. What this checks is the
      // gate, through the host being asked for the container or not.
      host.containerRoot = null;
      await NotificationPolicySnapshot.onPreferenceWritten('theme_name');
      expect(host.containerLookups, 0);
      await NotificationPolicySnapshot.onPreferenceWritten(
        'notifications_enabled',
      );
      expect(host.containerLookups, 1);
    });

    // The one fail-OPEN path in an otherwise fail-closed design, so it gets a
    // test of its own rather than riding on the filter test above. If a policy
    // preference stops being watched, the snapshot silently freezes and the
    // extension evaluates a STALE policy with full confidence - a user
    // switching to private previews keeps receiving rendered content.
    //
    // The strings are no longer duplicated (watchedKeys now reads
    // Preferences.notificationPolicyKeys), so a RENAME propagates and cannot
    // drift. This pins MEMBERSHIP, which a rename cannot break but a deletion
    // or an unlisted addition can.
    test('every policy preference is watched, by name', () async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();

      expect(NotificationPolicySnapshot.watchedKeys, {
        'notifications_enabled',
        'notification_mode',
        'notification_preview_privacy_choice_completed',
        'notification_preview_privacy_choice_value',
        'format_notification_body',
        'show_media_in_notifications',
        'preview_urls_in_notification',
        'room_notification_snoozes',
        'developer_mode',
      });
    });

    test('the watched set is the one Preferences owns, not a copy', () async {
      SharedPreferences.setMockInitialValues({});
      await preferences.init();

      // Reading through the owner is what makes a rename propagate. If these
      // ever diverge, the duplication is back.
      expect(
        NotificationPolicySnapshot.watchedKeys,
        preferences.notificationPolicyKeys,
      );
      expect(
        NotificationPolicySnapshot.watchedKeys,
        contains(preferences.enableNotifications.key),
      );
      expect(
        NotificationPolicySnapshot.watchedKeys,
        contains(preferences.notificationMode.key),
      );
    });

    test('is inert off iOS', () async {
      NotificationPolicySnapshot.platformIsIOS = false;
      await NotificationPolicySnapshot.onPreferenceWritten(
        'notifications_enabled',
      );
      await NotificationPolicySnapshot.onAccountsChanged(clientCount: 1);
      expect(host.containerLookups, 0);
    });
  });

  group('concurrent mutations', () {
    setUp(() => host.containerRoot = tempDir.path);

    // `onPreferenceWritten` fires once per preference write and nothing
    // ordered the resulting calls, so two writes reached the same
    // `policy.json.tmp` and one could rename it out from under the other,
    // publishing a torn document. The extension fails closed on a malformed
    // file, so the user loses policy-correct notifications silently until
    // something rewrites it.
    //
    // Observed through the container lookup, which is the FIRST filesystem
    // step of a write: if the second call has entered at all, it has already
    // asked for the container. Asserting on the finished file instead would
    // prove nothing here - a fake filesystem completes each write too fast to
    // interleave, so a torn file is exactly what this test could not produce.
    test('a second write does not start until the first finishes', () async {
      host.gate = Completer<void>();

      final first = NotificationPolicySnapshot.write();
      await pumpEventQueue();
      expect(
        host.containerLookups,
        1,
        reason: 'the first write should be parked inside the gate',
      );

      final second = NotificationPolicySnapshot.write();
      await pumpEventQueue();
      expect(
        host.containerLookups,
        1,
        reason:
            'the second write entered while the first was still in flight, so '
            'both are staging through the same policy.json.tmp',
      );

      host.gate!.complete();
      host.gate = null;
      await Future.wait([first, second]);
      // NOT asserted as a second lookup: `_directory()` caches, so once the
      // first write returns the second takes the cached path and never asks
      // the host again. The lookup count is only an observable while the gate
      // is held, which is exactly the window this test needs it for.
      expect(
        File(
          p.join(tempDir.path, 'notification-policy', 'policy.json'),
        ).existsSync(),
        isTrue,
        reason: 'serialising must not drop the writes, only order them',
      );
    });

    // Same hazard with the outcome reversed: a delete landing between another
    // write's staging and its rename republishes a snapshot the caller asked
    // to remove.
    test('a delete queues behind an in-flight write', () async {
      host.gate = Completer<void>();

      final write = NotificationPolicySnapshot.write();
      await pumpEventQueue();
      final delete = NotificationPolicySnapshot.delete();
      await pumpEventQueue();

      expect(host.containerLookups, 1);

      host.gate!.complete();
      host.gate = null;
      await Future.wait([write, delete]);

      // The delete ran second, so it wins: the snapshot is gone rather than
      // republished by a write that finished after it.
      expect(
        File(
          p.join(tempDir.path, 'notification-policy', 'policy.json'),
        ).existsSync(),
        isFalse,
      );
    });
  });
}

List<int> _unhex(String hex) => [
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
];

/// The digest the extension recomputes, spelled out here rather than called
/// through the class under test, so a change to the algorithm has to be made
/// twice before these tests agree with it.
String _expectedDigest(List<int> fileKey, String snoozeKey) =>
    Hmac(sha256, fileKey)
        .convert(utf8.encode(snoozeKey))
        .bytes
        .sublist(0, 16)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

class _FakeHost implements AppGroupStorageHost {
  String? containerRoot;
  int containerLookups = 0;
  final List<String> protected = [];
  final List<String> excluded = [];
  String? Function(String path)? reportFor;

  /// Holds a mutation open at its first filesystem step, so a second one can
  /// be started and observed while the first is genuinely still in flight.
  Completer<void>? gate;

  @override
  Future<String?> containerPath() async {
    containerLookups++;
    final held = gate;
    if (held != null) {
      await held.future;
    }
    return containerRoot;
  }

  @override
  Future<String?> protectItem(String path) async {
    protected.add(path);
    return reportFor?.call(path) ?? AppGroupStorageHost.expectedProtectionClass;
  }

  @override
  Future<String?> readProtectionClass(String path) async =>
      AppGroupStorageHost.expectedProtectionClass;

  @override
  Future<bool> excludeFromBackup(String path) async {
    excluded.add(path);
    return true;
  }
}
