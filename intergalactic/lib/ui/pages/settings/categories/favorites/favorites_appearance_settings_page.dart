import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/image_select_dialog.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/utils/picker_utils.dart';
import 'package:intergalactic/utils/preference_image_data.dart';
import 'package:intl/intl.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class FavoritesAppearanceSettingsPage extends StatefulWidget {
  const FavoritesAppearanceSettingsPage({super.key});

  @override
  State<FavoritesAppearanceSettingsPage> createState() =>
      _FavoritesAppearanceSettingsPageState();
}

class _FavoritesAppearanceSettingsPageState
    extends State<FavoritesAppearanceSettingsPage> {
  String get labelFavoritesAppearanceSettings => Intl.message(
    'Favorites Appearance',
    name: 'labelFavoritesAppearanceSettings',
    desc: 'Section title for Favorites appearance settings',
  );

  String get labelFavoritesIcon => Intl.message(
    'Favorites icon',
    name: 'labelFavoritesIcon',
    desc: 'Label for the Favorites icon appearance setting',
  );

  String get labelFavoritesIconDescription => Intl.message(
    'Shown on the Favorites rail button and virtual-space avatar on this device.',
    name: 'labelFavoritesIconDescription',
    desc: 'Description for the Favorites icon appearance setting',
  );

  String get labelFavoritesBanner => Intl.message(
    'Favorites banner',
    name: 'labelFavoritesBanner',
    desc: 'Label for the Favorites banner appearance setting',
  );

  String get labelFavoritesBannerDescription => Intl.message(
    'Shown across the Favorites virtual-space header on this device.',
    name: 'labelFavoritesBannerDescription',
    desc: 'Description for the Favorites banner appearance setting',
  );

  String get labelChooseFavoritesIcon => Intl.message(
    'Choose icon',
    name: 'labelChooseFavoritesIcon',
    desc: 'Empty-state prompt for choosing a Favorites icon',
  );

  String get labelChooseFavoritesBanner => Intl.message(
    'Choose banner',
    name: 'labelChooseFavoritesBanner',
    desc: 'Empty-state prompt for choosing a Favorites banner',
  );

  String get labelChangeFavoritesIcon => Intl.message(
    'Change Favorites icon',
    name: 'labelChangeFavoritesIcon',
    desc: 'Dialog title for changing the Favorites icon',
  );

  String get labelChangeFavoritesBanner => Intl.message(
    'Change Favorites banner',
    name: 'labelChangeFavoritesBanner',
    desc: 'Dialog title for changing the Favorites banner',
  );

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: labelFavoritesAppearanceSettings,
      children: [
        SettingsControlRow(
          title: labelFavoritesIcon,
          description: labelFavoritesIconDescription,
          child: _FavoritesImagePreview(
            image: _preferenceImageProvider(
              preferences.favoritesIconImageData.value,
            ),
            aspectRatio: 1,
            maxWidth: 120,
            emptyLabel: labelChooseFavoritesIcon,
            onTap: editFavoritesIcon,
          ),
        ),
        SettingsControlRow(
          title: labelFavoritesBanner,
          description: labelFavoritesBannerDescription,
          child: _FavoritesImagePreview(
            image: _preferenceImageProvider(
              preferences.favoritesBannerImageData.value,
            ),
            aspectRatio: 700 / 230,
            maxWidth: double.infinity,
            emptyLabel: labelChooseFavoritesBanner,
            onTap: editFavoritesBanner,
          ),
        ),
      ],
    );
  }

  Future<void> editFavoritesIcon() {
    return editFavoritesImage(
      icon: true,
      title: labelChangeFavoritesIcon,
      aspectRatio: 1,
    );
  }

  Future<void> editFavoritesBanner() {
    return editFavoritesImage(
      icon: false,
      title: labelChangeFavoritesBanner,
      aspectRatio: 700 / 230,
    );
  }

  Future<void> editFavoritesImage({
    required bool icon,
    required String title,
    required double aspectRatio,
  }) async {
    final preference = icon
        ? preferences.favoritesIconImageData
        : preferences.favoritesBannerImageData;
    final currentImage = _preferenceImageProvider(preference.value);
    final action = await ImageSelectDialog.show(
      context,
      image: currentImage,
      title: title,
    );

    if (!mounted) {
      return;
    }

    if (action == ImageEditAction.remove) {
      await preference.set(null);
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (action != ImageEditAction.pick) {
      return;
    }

    final result = await PickerUtils.pickImageAndCrop(
      context,
      aspectRatio: aspectRatio,
    );

    if (!mounted || result == null) {
      return;
    }

    await preference.set(
      encodePreferenceImageData(
        result,
        maxWidth: icon ? 256 : 700,
        maxHeight: icon ? 256 : 230,
      ),
    );
    if (mounted) {
      setState(() {});
    }
  }

  m.ImageProvider? _preferenceImageProvider(String? value) {
    final bytes = decodePreferenceImageData(value);
    return bytes == null ? null : m.MemoryImage(bytes);
  }
}

class _FavoritesImagePreview extends StatelessWidget {
  const _FavoritesImagePreview({
    required this.image,
    required this.aspectRatio,
    required this.maxWidth,
    required this.emptyLabel,
    required this.onTap,
  });

  final m.ImageProvider? image;
  final double aspectRatio;
  final double maxWidth;
  final String emptyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = m.Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              image: image == null
                  ? null
                  : DecorationImage(image: image!, fit: BoxFit.cover),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.72),
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: m.Material(
              color: m.Colors.transparent,
              child: m.InkWell(
                onTap: onTap,
                child: AspectRatio(
                  aspectRatio: aspectRatio,
                  child: image == null
                      ? Center(child: tiamat.Text.labelLow(emptyLabel))
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
