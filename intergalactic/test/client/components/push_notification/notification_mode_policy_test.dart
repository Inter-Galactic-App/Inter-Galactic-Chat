import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/client/components/push_notification/notification_mode_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Covers the parts of the global-mute migration that the setup-menu test
/// cannot reach: the CROSS-DEVICE read, and the settings-page write path.
///
/// `notification_settings_page.dart` calls `setMuteAllPushNotifications` from a
/// second site that had no coverage at all, and the mode a migrated account
/// displays is read back from the SERVER rule rather than from local state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('resolveNotificationMode reads server state for migrated accounts', () {
    // The point of the migration: the master rule is account state on the
    // homeserver, so every signed-in device resolves the same mode from it.
    // A local preference cannot override it in either direction.
    test('a migrated account muted on the server reads as mute', () {
      expect(
        resolveNotificationMode(
          isMigrated: true,
          serverMuted: true,
          enableNotifications: true,
          localModeValue: 'all',
        ),
        NotificationMode.mute,
      );
    });

    test('server mute wins even when local state says notify', () {
      expect(
        resolveNotificationMode(
          isMigrated: true,
          serverMuted: true,
          enableNotifications: true,
          localModeValue: 'mentions',
        ),
        NotificationMode.mute,
      );
    });

    test('an unmuted migrated account reads its local non-mute mode', () {
      expect(
        resolveNotificationMode(
          isMigrated: true,
          serverMuted: false,
          enableNotifications: true,
          localModeValue: 'mentions',
        ),
        NotificationMode.mentions,
      );
    });

    // The legacy local gate is retired at migration. A stale local 'mute' left
    // behind by the old flow must not re-mute an account the server says is
    // live, or the migration would be silently undone on that device.
    test('a stale local mute does not mute an unmuted migrated account', () {
      expect(
        resolveNotificationMode(
          isMigrated: true,
          serverMuted: false,
          enableNotifications: true,
          localModeValue: 'mute',
        ),
        NotificationMode.all,
      );
    });

    test('the retired enableNotifications gate is ignored once migrated', () {
      expect(
        resolveNotificationMode(
          isMigrated: true,
          serverMuted: false,
          enableNotifications: false,
          localModeValue: 'all',
        ),
        NotificationMode.all,
      );
    });
  });

  group('resolveNotificationMode keeps the legacy rules before migration', () {
    test('the local gate still mutes an unmigrated account', () {
      expect(
        resolveNotificationMode(
          isMigrated: false,
          serverMuted: false,
          enableNotifications: false,
          localModeValue: 'all',
        ),
        NotificationMode.mute,
      );
    });

    test('an unmigrated account otherwise reads its local mode', () {
      expect(
        resolveNotificationMode(
          isMigrated: false,
          serverMuted: false,
          enableNotifications: true,
          localModeValue: 'mentions',
        ),
        NotificationMode.mentions,
      );
    });

    // Server state is not consulted before migration, so a stray true here
    // must not leak into the answer.
    test('server state is not consulted before migration', () {
      expect(
        resolveNotificationMode(
          isMigrated: false,
          serverMuted: true,
          enableNotifications: true,
          localModeValue: 'all',
        ),
        NotificationMode.all,
      );
    });
  });

  group('applyMatrixNotificationMode writes the server rule first', () {
    late Preferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = Preferences();
      await preferences.init();
      await preferences.notificationMode.set('all');
      await preferences.enableNotifications.set(true);
    });

    test('muting writes muted=true and marks only that account', () async {
      final writes = <bool>[];

      final result = await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (muted) async => writes.add(muted),
        preferences: preferences,
      );

      expect(result, NotificationModeWriteResult.applied);
      expect(writes, [true]);
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isTrue);
      expect(preferences.isGlobalMutePushRuleMigrated('account-b'), isFalse);
    });

    test('choosing a notifying mode writes muted=false', () async {
      final writes = <bool>[];

      final result = await applyMatrixNotificationMode(
        mode: NotificationMode.mentions,
        clientIdentifier: 'account-a',
        setMuted: (muted) async => writes.add(muted),
        preferences: preferences,
      );

      expect(result, NotificationModeWriteResult.applied);
      expect(writes, [false]);
      expect(preferences.notificationMode.value, 'mentions');
      expect(preferences.enableNotifications.value, isTrue);
    });

    // The ordering is the contract: nothing local may change until the server
    // has accepted the write, or a lost write reads as a completed migration.
    test('a failed write marks nothing and leaves preferences alone', () async {
      await preferences.notificationMode.set('all');

      final result = await applyMatrixNotificationMode(
        mode: NotificationMode.mentions,
        clientIdentifier: 'account-a',
        setMuted: (_) async => throw StateError('offline'),
        preferences: preferences,
      );

      expect(result, NotificationModeWriteResult.failed);
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isFalse);
      expect(preferences.notificationMode.value, 'all');
    });

    test('a failed mute leaves the account unmigrated', () async {
      final result = await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (_) async => throw StateError('offline'),
        preferences: preferences,
      );

      expect(result, NotificationModeWriteResult.failed);
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isFalse);
    });

    // The gap between the server write and the local writes. An empty client
    // identifier is what markGlobalMutePushRuleMigrated rejects, so it fails at
    // exactly the point a preferences write would: after the homeserver has
    // already accepted the rule. Nothing local may be half applied there, or
    // resolveNotificationMode reports a mode the server does not have.
    test('a failure after the server write applies no local state', () async {
      await preferences.notificationMode.set('all');
      await preferences.enableNotifications.set(false);
      final writes = <bool>[];

      final result = await applyMatrixNotificationMode(
        mode: NotificationMode.mentions,
        clientIdentifier: '',
        setMuted: (muted) async => writes.add(muted),
        preferences: preferences,
      );

      expect(result, NotificationModeWriteResult.failed);
      expect(writes, [false], reason: 'the server write is what succeeded');
      expect(
        preferences.notificationMode.value,
        'all',
        reason:
            'the migration record is written first, so a failure there stops '
            'the local writes instead of leaving the mode half applied',
      );
      expect(preferences.enableNotifications.value, isFalse);
    });

    test('migrating one account does not migrate another', () async {
      await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (_) async {},
        preferences: preferences,
      );
      await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-b',
        setMuted: (_) async => throw StateError('offline'),
        preferences: preferences,
      );

      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isTrue);
      expect(preferences.isGlobalMutePushRuleMigrated('account-b'), isFalse);
    });

    // 'No pusher lifecycle change' holds by construction: the only collaborator
    // this function is given is the master-rule write, so it cannot register,
    // delete, or refresh a pusher. This pins that shape - a pusher call added
    // here would need a new dependency and would fail to compile against it.
    test('the server write is the only outbound call', () async {
      var calls = 0;

      await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (_) async => calls++,
        preferences: preferences,
      );

      expect(calls, 1);
    });
  });

  // REVIEW finding, 2026-09-06: notificationMode and enableNotifications are
  // DEVICE-wide, and MatrixRoom.shouldNotify read notificationMode raw. Muting
  // one account therefore silenced local notifications for every other signed
  // in account, while the settings page still showed those accounts as All.
  //
  // The master rule is per-account, so resolving through the server state is
  // what makes the two agree. These drive the SAME device-wide preference
  // values for both accounts, which is the situation that produced the bug.
  group('muting one account leaves another account alone', () {
    late Preferences preferences;
    late List<bool> accountAWrites;
    late List<bool> accountBWrites;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = Preferences();
      await preferences.init();
      await preferences.notificationMode.set('all');
      await preferences.enableNotifications.set(true);
    });

    /// Both accounts through the WRITER, against one shared [Preferences].
    ///
    /// The order is production's and is load-bearing.
    /// `applyMatrixNotificationMode` writes the DEVICE-WIDE `notificationMode`
    /// for every mode, so whichever account applies LAST owns the value both
    /// accounts then read. Account A mutes last, so the shared preference holds
    /// `mute` - which is precisely the value account B has to ignore. Muting A
    /// first and setting B to All afterwards leaves `all` in the preference,
    /// and account B's assertion below then passes even against a resolver
    /// that obeys the device-wide value.
    Future<void> driveBothAccounts() async {
      accountBWrites = <bool>[];
      await applyMatrixNotificationMode(
        mode: NotificationMode.all,
        clientIdentifier: 'account-b',
        setMuted: (muted) async => accountBWrites.add(muted),
        preferences: preferences,
      );

      accountAWrites = <bool>[];
      await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (muted) async => accountAWrites.add(muted),
        preferences: preferences,
      );

      expect(
        preferences.notificationMode.value,
        'mute',
        reason:
            'the shared device-wide preference must carry account A mute, or '
            'the cross-account cases below are not testing anything',
      );
    }

    /// Every input comes from what the writer produced or from the shared
    /// preference store. Nothing is a literal, so a writer that stopped
    /// marking the account migrated, or stopped writing the device-wide mode,
    /// changes what the reader is handed here.
    NotificationMode resolveFor(String clientId, List<bool> serverWrites) =>
        resolveNotificationMode(
          isMigrated: preferences.isGlobalMutePushRuleMigrated(clientId),
          serverMuted: serverWrites.single,
          enableNotifications: preferences.enableNotifications.value,
          localModeValue: preferences.notificationMode.value,
        );

    test('the muted account resolves to mute', () async {
      await driveBothAccounts();

      expect(resolveFor('account-a', accountAWrites), NotificationMode.mute);
    });

    test(
      'a second migrated account on the same device still notifies',
      () async {
        await driveBothAccounts();

        expect(
          resolveFor('account-b', accountBWrites),
          NotificationMode.all,
          reason:
              'the device-wide mute preference belongs to the other account',
        );
      },
    );

    // The residual, and why migration is the fix rather than a tidier read of
    // the preference. Before migration the device-wide value is the ONLY thing
    // the resolver has, so account A's mute does reach an account that has not
    // migrated yet. Pinned rather than wished away: it is the shape of the
    // original bug, and it disappears for an account the moment it migrates.
    test(
      'an unmigrated account still reads the device-wide preference',
      () async {
        await driveBothAccounts();

        expect(preferences.isGlobalMutePushRuleMigrated('account-c'), isFalse);
        expect(
          resolveNotificationMode(
            isMigrated: preferences.isGlobalMutePushRuleMigrated('account-c'),
            serverMuted: false,
            enableNotifications: preferences.enableNotifications.value,
            localModeValue: preferences.notificationMode.value,
          ),
          NotificationMode.mute,
          reason:
              'an unmigrated account has no server rule to resolve from, so it '
              'is still exposed to the device-wide value until it migrates',
        );
      },
    );
  });

  // REVIEW finding, 2026-09-06: applyMatrixNotificationMode used to SKIP the
  // notificationMode write for mute, while _setNotificationMode wrote it
  // unconditionally on the next line - and that second write was the only thing
  // making local mute work. Deleting the apparently-redundant line, which this
  // file's own comment invited, silently removed local mute.
  //
  // The write now happens here, once, for every mode. resolveNotificationMode
  // is what decides whether a stored 'mute' still means anything.
  group('the stored mode always describes the mode that was chosen', () {
    late Preferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = Preferences();
      await preferences.init();
      await preferences.notificationMode.set('all');
    });

    test('choosing mute stores mute', () async {
      await applyMatrixNotificationMode(
        mode: NotificationMode.mute,
        clientIdentifier: 'account-a',
        setMuted: (_) async {},
        preferences: preferences,
      );

      expect(preferences.notificationMode.value, 'mute');
    });

    test('choosing mentions stores mentions', () async {
      await applyMatrixNotificationMode(
        mode: NotificationMode.mentions,
        clientIdentifier: 'account-a',
        setMuted: (_) async {},
        preferences: preferences,
      );

      expect(preferences.notificationMode.value, 'mentions');
    });

    // The round trip that ties the writer to the reader: what mute stores must
    // resolve back to mute for the account that chose it.
    test(
      'a stored mute resolves back to mute for the muting account',
      () async {
        // Every input the reader gets here is produced by the writer. Handing
        // it a literal `serverMuted: true` would have supplied the half of the
        // trip the writer is supposed to prove, so a mute write that flipped
        // to false still passed.
        final writes = <bool>[];

        await applyMatrixNotificationMode(
          mode: NotificationMode.mute,
          clientIdentifier: 'account-a',
          setMuted: (muted) async => writes.add(muted),
          preferences: preferences,
        );

        expect(
          resolveNotificationMode(
            isMigrated: preferences.isGlobalMutePushRuleMigrated('account-a'),
            serverMuted: writes.single,
            enableNotifications: preferences.enableNotifications.value,
            localModeValue: preferences.notificationMode.value,
          ),
          NotificationMode.mute,
        );
      },
    );
  });
}
