import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/pages/setup/menus/global_mute_push_rule_setup.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('global mute push-rule migration preferences', () {
    late Preferences preferences;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      preferences = Preferences();
      await preferences.init();
    });

    test('records migration completion per Matrix account', () async {
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isFalse);
      expect(preferences.isGlobalMutePushRuleMigrated('account-b'), isFalse);

      await preferences.markGlobalMutePushRuleMigrated('account-a');

      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isTrue);
      expect(preferences.isGlobalMutePushRuleMigrated('account-b'), isFalse);
    });

    test('rejects an empty migration account identifier', () async {
      expect(
        () => preferences.markGlobalMutePushRuleMigrated(''),
        throwsArgumentError,
      );
    });

    test('writes the master rule then marks only the chosen account', () async {
      final writes = <bool>[];
      final setup = GlobalMutePushRuleSetup.forTesting(
        clientIdentifier: 'account-a',
        setMuted: (muted) async => writes.add(muted),
        preferences: preferences,
      );

      await setup.choose(true);

      expect(writes, [true]);
      expect(setup.state, SetupMenuState.canProgress);
      expect(setup.selectedMuted, isTrue);
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isTrue);
      expect(preferences.isGlobalMutePushRuleMigrated('account-b'), isFalse);
      expect(preferences.enableNotifications.value, isTrue);
    });

    test('keeps migration pending when the master-rule write fails', () async {
      final setup = GlobalMutePushRuleSetup.forTesting(
        clientIdentifier: 'account-a',
        setMuted: (_) async => throw StateError('offline'),
        preferences: preferences,
      );

      await setup.choose(false);

      expect(setup.state, SetupMenuState.cannotProgress);
      expect(setup.selectedMuted, isNull);
      expect(setup.errorMessage, isNotNull);
      expect(preferences.isGlobalMutePushRuleMigrated('account-a'), isFalse);
    });

    test(
      'blocks progression while a correction is pending and restores it on failure',
      () async {
        final correction = Completer<void>();
        var writeCount = 0;
        final setup = GlobalMutePushRuleSetup.forTesting(
          clientIdentifier: 'account-a',
          setMuted: (_) {
            writeCount++;
            return writeCount == 2 ? correction.future : Future.value();
          },
          preferences: preferences,
        );

        await setup.choose(false);
        expect(setup.state, SetupMenuState.canProgress);
        expect(setup.selectedMuted, isFalse);

        final pendingCorrection = setup.choose(true);
        expect(setup.isApplying, isTrue);
        expect(setup.state, SetupMenuState.cannotProgress);
        expect(setup.selectedMuted, isFalse);
        await expectLater(setup.submit(), throwsStateError);

        correction.completeError(StateError('offline'));
        await pendingCorrection;

        expect(setup.isApplying, isFalse);
        expect(setup.state, SetupMenuState.canProgress);
        expect(setup.selectedMuted, isFalse);
        expect(setup.errorMessage, isNotNull);
      },
    );
  });
}
