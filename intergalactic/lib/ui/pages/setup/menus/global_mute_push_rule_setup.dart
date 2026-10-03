import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/debug/log.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:intergalactic/ui/pages/setup/post_login_setup_menus.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// Makes the one-time, account-scoped choice that replaces the old local
/// global-Mute preference with Matrix's synced master push rule.
class GlobalMutePushRuleSetup implements PerAccountSetupMenu {
  GlobalMutePushRuleSetup(
    MatrixClient client, {
    required Preferences preferences,
  }) : this._(
         clientIdentifier: client.identifier,
         accountLabel: client.self?.identifier ?? client.identifier,
         setMuted: client.getMatrixClient().setMuteAllPushNotifications,
         preferences: preferences,
       );

  @visibleForTesting
  GlobalMutePushRuleSetup.forTesting({
    required String clientIdentifier,
    required Future<void> Function(bool muted) setMuted,
    required Preferences preferences,
  }) : this._(
         clientIdentifier: clientIdentifier,
         accountLabel: clientIdentifier,
         setMuted: setMuted,
         preferences: preferences,
       );

  GlobalMutePushRuleSetup._({
    required this.clientIdentifier,
    required this.accountLabel,
    required Future<void> Function(bool muted) setMuted,
    required Preferences preferences,
  }) : _setMuted = setMuted,
       _preferences = preferences;

  @override
  final String clientIdentifier;
  final String accountLabel;
  final Future<void> Function(bool muted) _setMuted;
  final Preferences _preferences;
  final StreamController<SetupMenuState> _controller =
      StreamController<SetupMenuState>.broadcast();

  bool _isApplying = false;
  String? _errorMessage;
  bool? _selectedMuted;

  bool get isApplying => _isApplying;
  String? get errorMessage => _errorMessage;
  bool? get selectedMuted => _selectedMuted;
  @override
  SetupMenuState state = SetupMenuState.cannotProgress;

  @override
  Stream<SetupMenuState> get onStateChanged => _controller.stream;

  @override
  Widget builder(BuildContext context) =>
      _GlobalMutePushRuleSetupView(menu: this);

  Future<void> choose(bool muted) async {
    if (_isApplying) {
      return;
    }

    final previousState = state;
    _isApplying = true;
    _errorMessage = null;
    state = SetupMenuState.cannotProgress;
    _controller.add(state);
    try {
      await _setMuted(muted);
      // The legacy flag must not remain a second global-Mute source after the
      // server policy was accepted. The Matrix master rule is now authoritative.
      await _preferences.enableNotifications.set(true);
      await _preferences.markGlobalMutePushRuleMigrated(clientIdentifier);
      _selectedMuted = muted;
      state = SetupMenuState.canProgress;
    } catch (error, trace) {
      Log.onError(
        error,
        trace,
        content: 'Could not update global Matrix notification policy',
      );
      _errorMessage =
          'Inter Galactic could not update this account on the server. Check your connection and try again.';
      state = previousState;
    } finally {
      _isApplying = false;
      _controller.add(state);
    }
  }

  @override
  Future<void> submit() async {
    if (state != SetupMenuState.canProgress) {
      throw StateError('A notification delivery choice is required.');
    }
  }
}

class _GlobalMutePushRuleSetupView extends StatelessWidget {
  const _GlobalMutePushRuleSetupView({required this.menu});

  final GlobalMutePushRuleSetup menu;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SetupMenuState>(
      stream: menu.onStateChanged,
      initialData: menu.state,
      builder: (context, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tiamat.Text.largeTitle('Notification delivery'),
            const SizedBox(height: 8),
            tiamat.Text.label(
              'This sets ${menu.accountLabel}\'s notification rule for the whole account. It applies everywhere you\'re signed in, not just here.',
            ),
            const SizedBox(height: 16),
            SettingsActionChoiceCard(
              icon: Icons.notifications_active_outlined,
              title: 'Keep notifications on',
              description:
                  'Deliver Matrix notifications for this account on every signed-in device, using its room and mention settings.',
              detail: 'You can still use Mentions & Keywords in settings.',
              action: menu.selectedMuted == false
                  ? const SettingsStatusChip(
                      icon: Icons.check_circle_outline,
                      label: 'Selected',
                      semanticLabel: 'Selected: notifications are on',
                      tone: SettingsStatusTone.accent,
                    )
                  : tiamat.Button.secondary(
                      text: menu.isApplying ? 'Updating...' : 'Keep on',
                      onTap: menu.isApplying
                          ? null
                          : () => unawaited(menu.choose(false)),
                    ),
            ),
            const SizedBox(height: 12),
            SettingsActionChoiceCard(
              icon: Icons.notifications_off_outlined,
              title: 'Mute this account',
              description:
                  'Stop Matrix notifications for this account on every signed-in device.',
              detail: 'You can turn them back on later from Notifications.',
              tone: SettingsStatusTone.warning,
              action: menu.selectedMuted == true
                  ? const SettingsStatusChip(
                      icon: Icons.check_circle_outline,
                      label: 'Selected',
                      semanticLabel: 'Selected: this account is muted',
                      tone: SettingsStatusTone.accent,
                    )
                  : tiamat.Button.secondary(
                      text: menu.isApplying ? 'Updating...' : 'Mute account',
                      onTap: menu.isApplying
                          ? null
                          : () => unawaited(menu.choose(true)),
                    ),
            ),
            if (menu.errorMessage case final message?) ...[
              const SizedBox(height: 12),
              SettingsStatePanel(
                icon: Icons.error_outline,
                title: 'Could not update notification delivery',
                description: message,
                tone: SettingsStatusTone.danger,
                padding: EdgeInsets.zero,
              ),
            ],
          ],
        );
      },
    );
  }
}
