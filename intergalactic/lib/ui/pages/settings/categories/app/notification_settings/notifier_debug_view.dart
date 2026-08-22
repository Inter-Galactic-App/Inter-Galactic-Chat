import 'package:intergalactic/client/components/push_notification/push_notification_component.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/notification_settings/notifier_component_view/notifier_component_view.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:flutter/widgets.dart';

class NotifierDebugView extends StatelessWidget {
  const NotifierDebugView({super.key});

  @override
  Widget build(BuildContext context) {
    final manager = clientManager;
    final component = manager == null
        ? null
        : SettingsAccountScope.selectedClientOf(
            context,
            manager,
          )?.getComponent<PushNotificationComponent>();

    return Column(
      children: [
        if (component != null)
          PushNotificationComponentDebugView(
            component,
            key: ValueKey(
                "push_notification_debug_view:${component.client.identifier}"),
          ),
      ],
    );
  }
}
