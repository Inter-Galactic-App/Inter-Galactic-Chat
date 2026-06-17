import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_room_events.dart';

class RoomAdminSettingsPage extends StatefulWidget {
  const RoomAdminSettingsPage({
    required this.room,
    super.key,
  });

  final Room room;

  @override
  State<RoomAdminSettingsPage> createState() => _RoomAdminSettingsPageState();
}

class _RoomAdminSettingsPageState extends State<RoomAdminSettingsPage> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.room.onUpdate.listen((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Room Profile',
          children: [
            SettingsControlRow(
              title: 'Icon, name, and topic',
              description:
                  'These details are visible to room members and may be controlled by room permissions.',
              child: RoomAppearanceSettingsView(
                client: widget.room.client,
                avatar: widget.room.avatar,
                displayName: widget.room.displayName,
                identifier: widget.room.identifier,
                color: widget.room.defaultColor,
                canEditName: widget.room.permissions.canEditName,
                canEditAvatar: widget.room.permissions.canEditAvatar,
                canEditTopic: widget.room.permissions.canEditTopic,
                topic: widget.room.topic,
                setTopic: widget.room.setTopic,
                onImagePicked: setRoomAvatar,
                onNameChanged: setRoomName,
              ),
            ),
          ],
        ),
        if (widget.room is MatrixRoom)
          SettingsSection(
            title: 'Addresses',
            children: [
              MatrixRoomAddressSettings(
                (widget.room as MatrixRoom).matrixRoom,
              ),
            ],
          ),
        RoomGeneralRoomEventsSettings(widget.room),
      ],
    );
  }

  void setRoomAvatar(Uint8List bytes, String? mimeType) {
    widget.room.setRoomAvatar(bytes, mimeType);
  }

  void setRoomName(String name) {
    widget.room.setDisplayName(name);
  }
}
