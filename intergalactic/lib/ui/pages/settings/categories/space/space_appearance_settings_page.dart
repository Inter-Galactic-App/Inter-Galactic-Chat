import 'dart:async';
import 'dart:typed_data';

import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/space_banner/space_banner_component.dart';
import 'package:intergalactic/ui/molecules/image_select_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/appearance/room_appearance_settings_view.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:flutter/material.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class SpaceAppearanceSettingsPage extends StatefulWidget {
  const SpaceAppearanceSettingsPage({super.key, required this.space});
  final Space space;
  @override
  State<SpaceAppearanceSettingsPage> createState() =>
      _SpaceAppearanceSettingsPageState();
}

class _SpaceAppearanceSettingsPageState
    extends State<SpaceAppearanceSettingsPage> {
  ImageProvider? image;
  bool uploading = false;
  late StreamSubscription _sub;

  @override
  void initState() {
    image = widget.space.getComponent<SpaceBannerComponent>()?.banner;
    super.initState();
    _sub = widget.space.onUpdate.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    bool canEditBanner =
        widget.space.getComponent<SpaceBannerComponent>()?.canEditBanner ==
            true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsSection(
          title: 'Space Profile',
          children: [
            SettingsControlRow(
              title: 'Icon, name, and topic',
              description:
                  'These details are visible to space members and may be controlled by space permissions.',
              child: RoomAppearanceSettingsView(
                avatar: widget.space.avatar,
                displayName: widget.space.displayName,
                identifier: widget.space.identifier,
                onImagePicked: onAvatarPicked,
                onNameChanged: setName,
                setTopic: widget.space.setTopic,
                client: widget.space.client,
                color: widget.space.color,
                topic: widget.space.topic,
                canEditName: widget.space.permissions.canEditName,
                canEditTopic: widget.space.permissions.canEditTopic,
                canEditAvatar: widget.space.permissions.canEditAvatar,
              ),
            ),
          ],
        ),
        if (canEditBanner)
          SettingsSection(
            title: 'Banner',
            children: [
              SettingsControlRow(
                title: 'Space banner',
                description:
                    'Set the wide image shown across this space where supported.',
                child: ClipRRect(
                  borderRadius: BorderRadiusGeometry.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerLow,
                      image: image != null
                          ? DecorationImage(image: image!, fit: BoxFit.cover)
                          : null,
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outline
                            .withValues(alpha: 0.72),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: uploading ? null : editBanner,
                        child: SizedBox(
                          width: double.infinity,
                          height: 220,
                          child: uploading
                              ? Center(
                                  child: SizedBox(
                                    width: 30,
                                    height: 30,
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : image == null
                                  ? Center(
                                      child: tiamat.Text.labelLow(
                                        'Choose Banner',
                                      ),
                                    )
                                  : null,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
      ],
    );
  }

  Future<void> editBanner() async {
    if (uploading) {
      return;
    }

    final action = await ImageSelectDialog.show(
      context,
      image: image,
    );

    if (!mounted) {
      return;
    }

    if (action == ImageEditAction.remove) {
      setState(() {
        image = null;
        uploading = true;
      });
      try {
        await widget.space.getComponent<SpaceBannerComponent>()?.removeBanner();
      } finally {
        if (mounted) {
          setState(() {
            uploading = false;
          });
        }
      }
      return;
    } else if (action != ImageEditAction.pick) {
      return;
    }

    var result = await PickerUtils.pickImageAndCrop(
      context,
      aspectRatio: 16 / 9,
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      setState(() {
        image = null;
        uploading = true;
      });

      try {
        await widget.space.getComponent<SpaceBannerComponent>()?.setBanner(
              result,
            );
        if (mounted) {
          setState(() {
            image = MemoryImage(result);
          });
        }
      } finally {
        if (mounted) {
          setState(() {
            uploading = false;
          });
        }
      }
    }
  }

  void onAvatarPicked(Uint8List bytes, String? mimeType) {
    widget.space.changeAvatar(bytes, mimeType);
  }

  void setName(String name) {
    widget.space.setDisplayName(name);
  }
}
