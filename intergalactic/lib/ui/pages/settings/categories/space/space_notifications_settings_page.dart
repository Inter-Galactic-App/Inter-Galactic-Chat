import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/notifications/room_notifications_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/notifications/room_notifications_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_matrix_room_builder.dart';

class SpaceNotificationsSettingsPage extends StatefulWidget {
  const SpaceNotificationsSettingsPage({required this.space, super.key});

  final Space space;

  @override
  State<SpaceNotificationsSettingsPage> createState() =>
      _SpaceNotificationsSettingsPageState();
}

class _SpaceNotificationsSettingsPageState
    extends State<SpaceNotificationsSettingsPage> {
  StreamSubscription? _subscription;
  late PushRule pushRule;

  @override
  void initState() {
    super.initState();
    _subscribeToSpace();
  }

  @override
  void didUpdateWidget(covariant SpaceNotificationsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.space != widget.space) {
      _subscribeToSpace();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _subscribeToSpace() {
    _subscription?.cancel();
    pushRule = widget.space.pushRule;
    _subscription = widget.space.onUpdate.listen((_) {
      if (mounted) {
        setState(() {
          pushRule = widget.space.pushRule;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.space case MatrixSpace space) {
      return SpaceMatrixRoomBuilder(
        space: space,
        builder: (context, room) => RoomNotificationsSettingsPage(
          room: room,
          contextLabel: 'space',
        ),
      );
    }

    return RoomNotificationsSettingsView(
      pushRule: pushRule,
      contextLabel: 'space',
      onPushRuleChanged: setPushRule,
    );
  }

  void setPushRule(PushRule? rule) {
    if (rule == null) return;

    setState(() {
      pushRule = rule;
    });

    widget.space.setPushRule(rule);
  }
}
