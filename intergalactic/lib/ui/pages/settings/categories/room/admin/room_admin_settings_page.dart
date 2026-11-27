import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/matrix/matrix_room.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/pages/settings/categories/discover/server_discovery_publication_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/general/room_general_room_events.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/admin/room_admin_room_classification_settings.dart';

class RoomAdminSettingsPage extends StatefulWidget {
  const RoomAdminSettingsPage({required this.room, super.key});

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
    // Room Profile and Addresses deliberately live on the General tab, not
    // here. See RoomGeneralSettingsPage: an ordinary member can read both, and
    // the topic is what they came for.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.room is MatrixRoom)
          ServerDiscoveryPublicationSettings(room: widget.room),
        if (widget.room case MatrixRoom matrixRoom)
          RoomAdminRoomClassificationSettings(room: matrixRoom),
        RoomGeneralRoomEventsSettings(widget.room),
      ],
    );
  }
}
