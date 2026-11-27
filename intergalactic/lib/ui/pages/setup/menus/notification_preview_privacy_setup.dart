import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notification_preview_privacy_choice.dart';
import 'package:intergalactic/ui/pages/setup/setup_menu.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class NotificationPreviewPrivacySetup implements SetupMenu {
  final StreamController<SetupMenuState> _controller =
      StreamController<SetupMenuState>.broadcast();

  @override
  Widget builder(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle('Notification previews'),
        const SizedBox(height: 8),
        tiamat.Text.label(
          'Choose what Inter Galactic can show in notifications on this device.',
        ),
        const SizedBox(height: 16),
        const NotificationPreviewPrivacyChoice(),
      ],
    );
  }

  @override
  Stream<SetupMenuState> get onStateChanged => _controller.stream;

  @override
  SetupMenuState state = SetupMenuState.canProgress;

  @override
  Future<void> submit() async {
    if (preferences.notificationPreviewPrivacyChoiceCompleted.value) {
      return;
    }

    await preferences.applyNotificationPreviewPrivacyChoice(
      Preferences.notificationPreviewPrivacyChoicePrivate,
    );
  }
}
