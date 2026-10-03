import 'package:flutter/material.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/matrix/matrix_space.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/discover/server_discovery_publication_settings.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/space/space_matrix_room_builder.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceAdminSettingsPage extends StatelessWidget {
  const SpaceAdminSettingsPage({required this.space, super.key});

  final Space space;

  @override
  Widget build(BuildContext context) {
    final matrixSpace = space is MatrixSpace ? space as MatrixSpace : null;

    // Space Profile, Banner and Addresses deliberately live on the General
    // tab, not here. See SpaceGeneralSettingsPage: an ordinary member can read
    // them, and the topic is what they came for. Bulk repair belongs alongside
    // other server-affecting admin controls, not in the image-pack editor.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (matrixSpace != null)
          ServerDiscoveryPublicationSettings(space: matrixSpace),
        if (matrixSpace != null)
          SpaceMatrixRoomBuilder(
            space: matrixSpace,
            builder: (context, room) => RoomSecuritySettingsPage(
              room: room,
              showEncryptionToggle: false,
              visibilityTargetLabel: 'space',
            ),
          ),
        if (matrixSpace != null)
          SpaceImagePackAccessSettings(space: matrixSpace),
      ],
    );
  }
}

class SpaceImagePackAccessSettings extends StatefulWidget {
  const SpaceImagePackAccessSettings({required this.space, super.key});

  final MatrixSpace space;

  @override
  State<SpaceImagePackAccessSettings> createState() =>
      _SpaceImagePackAccessSettingsState();
}

class _SpaceImagePackAccessSettingsState
    extends State<SpaceImagePackAccessSettings> {
  bool _repairing = false;
  String? _repairStatus;

  @override
  Widget build(BuildContext context) {
    if (!widget.space.canRepairImagePackParentLinks) {
      return const SizedBox.shrink();
    }
    return SettingsSection(
      title: 'Space image-pack access',
      children: [
        SettingsControlRow(
          title: 'Repair access for existing rooms',
          description:
              'Make this Space primary for linked rooms with no primary '
              'Space. Existing primary Spaces are kept. Only child rooms '
              'where you are an admin and can edit parent links are changed.',
          trailing: tiamat.Button.secondary(
            text: 'Repair links',
            isLoading: _repairing,
            onTap: _repairing ? null : _repairImagePackLinks,
          ),
          child: _repairStatus == null
              ? null
              : Semantics(liveRegion: true, child: Text(_repairStatus!)),
        ),
      ],
    );
  }

  Future<void> _repairImagePackLinks() async {
    if (!widget.space.canRepairImagePackParentLinks) return;
    setState(() {
      _repairing = true;
      _repairStatus = null;
    });
    try {
      final result = await widget.space.repairImagePackParentLinks();
      if (!mounted) return;
      setState(() {
        _repairStatus =
            '${result.repaired} room links repaired. '
            '${result.alreadyCanonical} already primary; '
            '${result.otherCanonicalParent} kept another primary Space; '
            '${result.noPermission} without admin permission; '
            '${result.unavailable} unavailable; '
            '${result.failed} failed.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _repairStatus = 'Could not repair this Space’s room links. Try again.';
      });
    } finally {
      if (mounted) setState(() => _repairing = false);
    }
  }
}
