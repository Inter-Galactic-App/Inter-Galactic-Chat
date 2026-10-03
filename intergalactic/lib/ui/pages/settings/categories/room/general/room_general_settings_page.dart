import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:intergalactic/utils/error_utils.dart';

/// The room's identity: icon, name, topic and addresses.
///
/// This is deliberately NOT under Admin Settings. Everything here is readable
/// by an ordinary member - `RoomAppearanceSettingsView` falls back to a plain
/// avatar, a static title and a non-tappable topic when the corresponding
/// permission is absent - and the topic is the main thing members come to room
/// settings to read. Filing it under Admin hid it from exactly the audience it
/// is for. Owner report, 2026-09-03.
class RoomGeneralSettingsPage extends StatefulWidget {
  const RoomGeneralSettingsPage({super.key, required this.room});

  final Room room;

  @override
  State<RoomGeneralSettingsPage> createState() =>
      _RoomGeneralSettingsPageState();
}

class _RoomGeneralSettingsPageState extends State<RoomGeneralSettingsPage> {
  StreamSubscription? _subscription;

  @override
  void initState() {
    super.initState();
    // Name, avatar and topic are all live room state, so this page has to
    // rebuild when it changes underneath the viewer.
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
              MatrixRoomAddressSettings((widget.room as MatrixRoom).matrixRoom),
            ],
          ),
      ],
    );
  }

  // `RoomAppearanceSettingsView` takes these as void callbacks and drops what
  // they return, so an awaited future has nowhere to go and a rejected
  // homeserver write - permission revoked between the permission read and the
  // tap, a rate limit, a transport error - becomes an unhandled zone error.
  // The dialog closes, nothing changes, and the user is told nothing. Route
  // them through `ErrorUtils.tryRun` the way the other room settings pages do.
  void setRoomAvatar(Uint8List bytes, String? mimeType) {
    unawaited(
      ErrorUtils.tryRun(
        context,
        () => widget.room.setRoomAvatar(bytes, mimeType),
      ),
    );
  }

  void setRoomName(String name) {
    unawaited(
      ErrorUtils.tryRun(context, () => widget.room.setDisplayName(name)),
    );
  }
}
