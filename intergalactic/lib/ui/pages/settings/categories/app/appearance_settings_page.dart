import 'package:intergalactic/config/build_config.dart';
import 'package:intergalactic/config/layout_config.dart';
import 'package:intergalactic/main.dart';
import 'package:intergalactic/ui/molecules/message_background_settings.dart';
import 'package:intergalactic/utils/app_icon/app_icon_manager.dart';
import 'package:intergalactic/utils/app_icon/app_icon_utils.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/boolean_toggle.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/double_preference_slider.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/theme_settings/theme_settings_widget.dart';
import 'package:intergalactic/utils/scaled_app.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:tiamat/config/style/theme_changer.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class AppearanceSettingsPage extends StatefulWidget {
  const AppearanceSettingsPage({super.key});

  @override
  State<AppearanceSettingsPage> createState() => _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  String get labelSettingsAppTheme => Intl.message("Theme",
      name: "labelSettingsAppTheme",
      desc: "Label for theme section of app appearance");

  String get labelStyle => Intl.message("Style",
      name: "labelStyle", desc: "Section title for style settings");

  String get labelAppScale => Intl.message("App Scale",
      name: 'labelAppScale',
      desc:
          "Label for the setting which controls the UI scale of the overall app");

  String get labelDesktopSmallWindowModeToggle => Intl.message(
      "Desktop small-window mode",
      desc:
          "Label for the toggle that enables the compact desktop small-window layout",
      name: "labelDesktopSmallWindowModeToggle");

  String get labelDesktopSmallWindowModeDescription => Intl.message(
      "Use a compact desktop layout for short or narrow windows while keeping room navigation, messages, and the composer on screen.",
      desc: "Description for the compact desktop small-window layout setting",
      name: "labelDesktopSmallWindowModeDescription");

  String get labelUseRoomAvatars => Intl.message("Use room avatars",
      name: "labelUseRoomAvatars",
      desc: "Label for enabling using room avatars instead of icons");

  String get labelBubbleMessages => Intl.message("Use bubble messages",
      name: "labelBubbleMessages",
      desc: "Label for enabling bubble-style message cards");

  String get labelBubbleMessagesDescription => Intl.message(
      "Render room messages in rounded bubble cards instead of the flatter timeline style",
      name: "labelBubbleMessagesDescription",
      desc: "Description for the message bubble appearance setting");

  String get labelAlignSentMessagesRight => Intl.message("Align messages right",
      name: "labelAlignSentMessagesRight",
      desc:
          "Label for aligning the current user's sent messages to the right side of the timeline");

  String get labelAlignSentMessagesRightDescription => Intl.message(
      "Place your sent messages on the right side of the chat, similar to iMessage",
      name: "labelAlignSentMessagesRightDescription",
      desc: "Description for the sent message alignment appearance setting");

  String get labelEnableRoomIconsDescription =>
      Intl.message("Show room avatar images instead of icons",
          name: "labelEnableRoomIconsDescription",
          desc: "Description for the enable room icons setting");

  String get labelUseRoomAvatarPlaceholders =>
      Intl.message("Use placeholder avatars",
          name: "labelUseRoomAvatarPlaceholders",
          desc: "Label for enabling generic icons in the appearance settings");

  String get labelUseRoomAvatarPlaceholdersDescription => Intl.message(
      "When a room does not have an avatar set, or using them is disabled, fallback to a generic color + first letter placeholder for the image",
      name: "labelUseRoomAvatarPlaceholdersDescription",
      desc: "Description for the enable generic icons setting");

  String get labelShowRoomPreviewsInSpaceSidebar => Intl.message(
      "Show unjoined rooms in sidebar",
      name: "labelShowRoomPreviewsInSpaceSidebar",
      desc: "Label for enabling using the preview list in the space sidebar");

  String get labelShowRoomPreviewsInSpaceSidebarDescription => Intl.message(
      "When there are rooms which you have not joined in a space, show them in the sidebar with the rest of the rooms in the space",
      name: "labelShowRoomPreviewsInSpaceSidebarDescription",
      desc:
          "Description for enabling using the preview list in the space sidebar");

  String get labelAppIcon => Intl.message("App Icon",
      name: "labelAppIcon",
      desc: "Label for the app icon preference in appearance settings");

  String get labelAppIconDescription => Intl.message(
      "Choose whether the app icon follows the system appearance or always uses the light or dark version.",
      name: "labelAppIconDescription",
      desc: "Description for the app icon preference");

  String get labelAppIconSystem => Intl.message("System",
      name: "labelAppIconSystem",
      desc: "Option label for system-following app icon mode");

  String get labelAppIconLight => Intl.message("Light",
      name: "labelAppIconLight", desc: "Option label for light app icon mode");

  String get labelAppIconDark => Intl.message("Dark",
      name: "labelAppIconDark", desc: "Option label for dark app icon mode");

  String get labelMessageAppearance => Intl.message("Message Appearance",
      name: "labelMessageAppearance",
      desc: "Section title for message appearance settings");

  String get labelDefaultBackground => Intl.message("Default background",
      name: "labelDefaultBackground",
      desc: "Label for the default message room background setting");

  String get labelDefaultForMessageRooms =>
      Intl.message("Default for message rooms",
          name: "labelDefaultForMessageRooms",
          desc: "Description for the default message room background setting");

  String get labelScaling => Intl.message("Scaling",
      name: "labelScaling", desc: "Section title for interface scale settings");

  String get labelAppScaleDescription =>
      Intl.message("Resizes the overall interface of the app",
          name: "labelAppScaleDescription",
          desc: "Description for the app scale setting");

  String get labelTextScale => Intl.message("Text Scale",
      name: "labelTextScale", desc: "Label for the text scale setting");

  String get labelTextScaleDescription =>
      Intl.message("Multiply the size of text",
          name: "labelTextScaleDescription",
          desc: "Description for the text scale setting");

  String get labelOtherOptions => Intl.message("Other Options",
      name: "labelOtherOptions",
      desc: "Section title for other appearance settings");

  String get labelOverrideLayout => Intl.message("Override layout",
      desc: "Label for overriding the app layout mode",
      name: "labelOverrideLayout");

  String get labelOverrideLayoutRestartNotice =>
      Intl.message("You may need to restart the app for this to take effect.",
          desc: "Description for the layout override setting",
          name: "labelOverrideLayoutRestartNotice");

  String get labelOverrideLayoutNoOverride => Intl.message("No Override",
      desc: "Option label for not overriding the app layout mode",
      name: "labelOverrideLayoutNoOverride");

  String get labelOverrideLayoutDesktop => Intl.message("Desktop",
      desc: "Option label for forcing the desktop layout mode",
      name: "labelOverrideLayoutDesktop");

  String get labelOverrideLayoutMobile => Intl.message("Mobile",
      desc: "Option label for forcing the mobile layout mode",
      name: "labelOverrideLayoutMobile");

  String get labelFollowSystemBrightness =>
      Intl.message("Follow System Brightness",
          name: "labelFollowSystemBrightness",
          desc: "Label for following the system light and dark theme");

  String get labelFollowSystemBrightnessDescription =>
      Intl.message("Automatically follow system Light / Dark mode",
          name: "labelFollowSystemBrightnessDescription",
          desc: "Description for following the system light and dark theme");

  String get labelFollowSystemColors => Intl.message("Follow System Colors",
      name: "labelFollowSystemColors",
      desc: "Label for following the system color scheme");

  String get labelFollowSystemColorsDescription =>
      Intl.message("Automatically follow system color scheme",
          name: "labelFollowSystemColorsDescription",
          desc: "Description for following the system color scheme");

  String labelForLayoutOverride(String? value) {
    if (value == "desktop") {
      return labelOverrideLayoutDesktop;
    }
    if (value == "mobile") {
      return labelOverrideLayoutMobile;
    }
    return labelOverrideLayoutNoOverride;
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        styleSettings(context),
        appIconSettings(context),
        themeSettings(context),
        if (BuildConfig.MOBILE || BuildConfig.DESKTOP) ...[
          SettingsSection(
            title: labelMessageAppearance,
            children: [
              Column(
                spacing: 12,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: BooleanPreferenceToggle(
                      preference: preferences.bubbleMessages,
                      title: labelBubbleMessages,
                      description: labelBubbleMessagesDescription,
                      onChanged: (_) async {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                    child: BooleanPreferenceToggle(
                      preference: preferences.alignSentMessagesRight,
                      title: labelAlignSentMessagesRight,
                      description: labelAlignSentMessagesRightDescription,
                      onChanged: (_) async {
                        if (mounted) setState(() {});
                      },
                    ),
                  ),
                  MessageBackgroundSettings(
                    title: labelDefaultBackground,
                    description: labelDefaultForMessageRooms,
                    storageKey: "default",
                    value: preferences.messageBackgroundImagePath.value,
                    backgroundOpacity:
                        preferences.getDefaultMessageBackgroundOpacity(),
                    sentBubbleColorHex:
                        preferences.sentMessageBubbleColor.value ??
                            preferences.messageBubbleColor.value,
                    receivedBubbleColorHex:
                        preferences.receivedMessageBubbleColor.value ??
                            preferences.messageBubbleColor.value,
                    onChanged: (path) async {
                      await preferences.messageBackgroundImagePath.set(path);
                      if (mounted) setState(() {});
                    },
                    onBackgroundOpacityChanged: (value) async {
                      await preferences
                          .setDefaultMessageBackgroundOpacity(value);
                      if (mounted) setState(() {});
                    },
                    onClearBackgroundOpacity: () async {
                      await preferences.clearDefaultMessageBackgroundOpacity();
                      if (mounted) setState(() {});
                    },
                    onSentBubbleColorChanged: (hexColor) async {
                      await preferences.sentMessageBubbleColor.set(hexColor);
                      if (mounted) setState(() {});
                    },
                    onClearSentBubbleColor: () async {
                      await preferences.sentMessageBubbleColor.set(null);
                      if (mounted) setState(() {});
                    },
                    onReceivedBubbleColorChanged: (hexColor) async {
                      await preferences.receivedMessageBubbleColor
                          .set(hexColor);
                      if (mounted) setState(() {});
                    },
                    onClearReceivedBubbleColor: () async {
                      await preferences.receivedMessageBubbleColor.set(null);
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),
            ],
          ),
        ],
        SettingsSection(
          title: labelScaling,
          children: [
            _ScaleSettingsGrid(
              appScale: DoublePreferenceSlider(
                min: 0.2,
                max: 2,
                preference: preferences.appScale,
                onChanged: (p0) {
                  ScaledWidgetsFlutterBinding.instance.scaleFactor =
                      (deviceSize) {
                    return p0;
                  };
                },
                title: labelAppScale,
                description: labelAppScaleDescription,
              ),
              textScale: DoublePreferenceSlider(
                min: 0.2,
                max: 3,
                preference: preferences.textScale,
                title: labelTextScale,
                description: labelTextScaleDescription,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: labelOtherOptions,
          showDivider: false,
          children: [
            Column(
              children: [
                if (Layout.desktop) ...[
                  BooleanPreferenceToggle(
                    preference: preferences.desktopSmallWindowMode,
                    title: labelDesktopSmallWindowModeToggle,
                    description: labelDesktopSmallWindowModeDescription,
                  ),
                ],
                BooleanPreferenceToggle(
                  preference: preferences.showRoomPreviewsInSpaceSidebar,
                  title: labelShowRoomPreviewsInSpaceSidebar,
                  description: labelShowRoomPreviewsInSpaceSidebarDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.showRoomAvatars,
                  title: labelUseRoomAvatars,
                  description: labelEnableRoomIconsDescription,
                ),
                BooleanPreferenceToggle(
                  preference: preferences.usePlaceholderRoomAvatars,
                  title: labelUseRoomAvatarPlaceholders,
                  description: labelUseRoomAvatarPlaceholdersDescription,
                ),
                _LayoutOverridePicker(
                  title: labelOverrideLayout,
                  description: labelOverrideLayoutRestartNotice,
                  options: const [null, "desktop", "mobile"],
                  value: preferences.layoutOverride.value,
                  labelForOption: labelForLayoutOverride,
                  onChanged: (item) async {
                    await preferences.layoutOverride.set(item);
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget styleSettings(BuildContext context) {
    return SettingsSection(
      title: labelStyle,
      children: [
        BooleanPreferenceToggle(
          preference: preferences.shouldFollowSystemTheme,
          title: labelFollowSystemBrightness,
          description: labelFollowSystemBrightnessDescription,
          onChanged: (_) async {
            var theme = await preferences.resolveTheme();
            if (context.mounted) ThemeChanger.setTheme(context, theme);
          },
        ),
        BooleanPreferenceToggle(
          preference: preferences.shouldFollowSystemColors,
          title: labelFollowSystemColors,
          description: labelFollowSystemColorsDescription,
          onChanged: (_) async {
            var theme = await preferences.resolveTheme();
            if (context.mounted) ThemeChanger.setTheme(context, theme);
          },
        ),
      ],
    );
  }

  Widget appIconSettings(BuildContext context) {
    return SettingsSection(
      title: labelAppIcon,
      children: [
        _AppIconModePicker(
          title: labelAppIcon,
          description: labelAppIconDescription,
          systemLabel: labelAppIconSystem,
          lightLabel: labelAppIconLight,
          darkLabel: labelAppIconDark,
        ),
      ],
    );
  }

  Widget themeSettings(BuildContext context) {
    return SettingsSection(
      title: labelSettingsAppTheme,
      children: [
        const ThemeListWidget(),
      ],
    );
  }
}

class _AppIconModeEntry {
  const _AppIconModeEntry({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;
}

class _AppIconModePicker extends StatefulWidget {
  const _AppIconModePicker({
    required this.title,
    required this.description,
    required this.systemLabel,
    required this.lightLabel,
    required this.darkLabel,
  });

  final String title;
  final String description;
  final String systemLabel;
  final String lightLabel;
  final String darkLabel;

  @override
  State<_AppIconModePicker> createState() => _AppIconModePickerState();
}

class _AppIconModePickerState extends State<_AppIconModePicker> {
  List<_AppIconModeEntry> get entries => [
        _AppIconModeEntry(value: "system", label: widget.systemLabel),
        _AppIconModeEntry(value: "light", label: widget.lightLabel),
        _AppIconModeEntry(value: "dark", label: widget.darkLabel),
      ];

  @override
  Widget build(BuildContext context) {
    final entries = this.entries;
    final currentValue = preferences.appIconMode.value;
    final selectedEntry = entries.firstWhere(
      (entry) => entry.value == currentValue,
      orElse: () => entries.first,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: m.Theme.of(context).colorScheme.surfaceContainerLow,
          border: Border.all(
            color: m.Theme.of(context).colorScheme.outline.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 620;
            final preview = _AppIconPreview(mode: selectedEntry.value);
            final selector = tiamat.DropdownSelector<_AppIconModeEntry>(
              color: m.Theme.of(context).colorScheme.surfaceContainer,
              items: entries,
              itemBuilder: (item) {
                return tiamat.Text(item.label);
              },
              onItemSelected: (item) async {
                if (item == null) {
                  return;
                }

                final previousMode = preferences.appIconMode.value;
                await preferences.appIconMode.set(item.value);
                try {
                  await AppIconManager.instance.apply();
                } catch (_) {
                  await preferences.appIconMode.set(previousMode);
                  rethrow;
                }

                if (mounted) {
                  setState(() {});
                }
              },
              value: selectedEntry,
            );
            final label = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                tiamat.Text(widget.title),
                const SizedBox(height: 4),
                tiamat.Text.labelLow(widget.description),
              ],
            );

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      preview,
                      const SizedBox(width: 14),
                      Expanded(child: label),
                    ],
                  ),
                  const SizedBox(height: 14),
                  selector,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                preview,
                const SizedBox(width: 16),
                Expanded(child: label),
                const SizedBox(width: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: 220,
                    maxWidth: 360,
                  ),
                  child: selector,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AppIconPreview extends StatelessWidget {
  const _AppIconPreview({
    required this.mode,
  });

  final String mode;

  @override
  Widget build(BuildContext context) {
    final systemBrightness = mode == "light"
        ? Brightness.light
        : mode == "dark"
            ? Brightness.dark
            : null;

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: m.Theme.of(context).colorScheme.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: m.Theme.of(context).shadowColor.withAlpha(45),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          AppIconUtils.roundedAssetPath(
            systemBrightness: systemBrightness,
          ),
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _ScaleSettingsGrid extends StatelessWidget {
  const _ScaleSettingsGrid({
    required this.appScale,
    required this.textScale,
  });

  final Widget appScale;
  final Widget textScale;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(
            children: [
              appScale,
              const SizedBox(height: 8),
              textScale,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: appScale),
            const SizedBox(width: 28),
            Expanded(child: textScale),
          ],
        );
      },
    );
  }
}

class _LayoutOverridePicker extends StatelessWidget {
  const _LayoutOverridePicker({
    required this.title,
    required this.description,
    required this.options,
    required this.value,
    required this.labelForOption,
    required this.onChanged,
  });

  final String title;
  final String description;
  final List<String?> options;
  final String? value;
  final String Function(String? option) labelForOption;
  final Future<void> Function(String? option) onChanged;

  @override
  Widget build(BuildContext context) {
    return SettingsControlRow(
      title: title,
      description: description,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260, minWidth: 180),
        child: tiamat.DropdownSelector<String?>(
          color: m.Theme.of(context).colorScheme.surfaceContainer,
          items: options,
          itemBuilder: (item) => tiamat.Text.label(labelForOption(item)),
          onItemSelected: (item) => onChanged(item),
          value: value,
        ),
      ),
    );
  }
}
