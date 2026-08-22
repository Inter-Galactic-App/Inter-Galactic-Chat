import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_chat_privacy.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_room_events.dart';
import 'package:intergalactic/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:flutter/widgets.dart';

class RoomGeneralSettingsPage extends StatefulWidget {
  const RoomGeneralSettingsPage({super.key, required this.room});
  final Room room;
  @override
  State<RoomGeneralSettingsPage> createState() =>
      _RoomGeneralSettingsPageState();
}

class _RoomGeneralSettingsPageState extends State<RoomGeneralSettingsPage> {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        RoomGeneralRoomEventsSettings(widget.room),
        const SizedBox(
          height: 10,
        ),
        RoomGeneralChatPrivacySettings(widget.room),
        if (widget.room is MatrixRoom) ...[
          const SizedBox(
            height: 10,
          ),
          MatrixRoomAddressSettings((widget.room as MatrixRoom).matrixRoom),
        ]
      ],
    );
  }
}
