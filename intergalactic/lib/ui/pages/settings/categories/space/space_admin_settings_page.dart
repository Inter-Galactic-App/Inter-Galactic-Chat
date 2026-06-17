import 'package:flutter/widgets.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/ui/pages/matrix/room_address_settings/matrix_room_address_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_appearance_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_matrix_room_builder.dart';

class SpaceAdminSettingsPage extends StatelessWidget {
  const SpaceAdminSettingsPage({
    required this.space,
    super.key,
  });

  final Space space;

  @override
  Widget build(BuildContext context) {
    final matrixSpace = space is MatrixSpace ? space as MatrixSpace : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpaceAppearanceSettingsPage(space: space),
        if (matrixSpace != null)
          SettingsSection(
            title: 'Addresses',
            children: [
              MatrixRoomAddressSettings(matrixSpace.matrixRoom),
            ],
          ),
        if (matrixSpace != null)
          SpaceMatrixRoomBuilder(
            space: matrixSpace,
            builder: (context, room) => RoomSecuritySettingsPage(
              room: room,
              showEncryptionToggle: false,
            ),
          ),
      ],
    );
  }
}
