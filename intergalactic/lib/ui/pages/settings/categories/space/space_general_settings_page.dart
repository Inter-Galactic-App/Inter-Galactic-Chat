import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_appearance_settings_page.dart';

/// A space's identity: icon, name, topic, banner and addresses.
///
/// This is deliberately NOT under Admin Settings, matching the room change on
/// the same branch. Everything here is readable by an ordinary member -
/// `SpaceAppearanceSettingsPage` uses `RoomAppearanceSettingsView`, which
/// degrades to a static title, a plain avatar and a non-tappable topic when the
/// permission is absent, and the Banner section only renders for members who
/// can edit it - and the topic is the thing members open space settings to
/// read. Filing it under Admin hid it from its own audience. Owner report,
/// 2026-09-03.
///
/// Previously this file was dead code left over from before the identity was
/// moved into Admin: nothing built it and its composition (notification push
/// rule + addresses) was stale. Reused rather than orphaned beside a new file.
class SpaceGeneralSettingsPage extends StatelessWidget {
  const SpaceGeneralSettingsPage({super.key, required this.space});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final matrixSpace = space is MatrixSpace ? space as MatrixSpace : null;

    // SpaceAppearanceSettingsPage owns its own onUpdate subscription, so this
    // page does not need to listen for name/topic/banner changes itself.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpaceAppearanceSettingsPage(space: space),
        if (matrixSpace != null)
          SettingsSection(
            title: 'Addresses',
            children: [MatrixRoomAddressSettings(matrixSpace.matrixRoom)],
          ),
      ],
    );
  }
}
