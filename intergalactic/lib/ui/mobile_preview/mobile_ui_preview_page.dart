import 'package:flutter/material.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/molecules/overlapping_panels.dart';
import 'package:intergalactic/ui/pages/settings/mobile_settings_page.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:tiamat/config/style/theme_dark.dart';
import 'package:tiamat/config/style/theme_light.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class MobileUiPreviewPage extends StatefulWidget {
  const MobileUiPreviewPage({super.key});

  @override
  State<MobileUiPreviewPage> createState() => _MobileUiPreviewPageState();
}

class _MobileUiPreviewPageState extends State<MobileUiPreviewPage> {
  final GlobalKey<OverlappingPanelsState> _panelsKey =
      GlobalKey<OverlappingPanelsState>();
  bool _darkMode = true;

  List<SettingsCategory> get _previewSettings => [
        _PreviewSettingsCategory(
          title: "Appearance",
          tabs: [
            SettingsTab(
              label: "Theme",
              icon: Icons.palette_outlined,
              pageBuilder: (context) => const _PreviewSettingsDetail(
                title: "Theme",
                description:
                    "Use this screen to experiment with grouped cards, inset controls, and softer mobile geometry.",
              ),
            ),
            SettingsTab(
              label: "App Icon",
              icon: Icons.auto_awesome_outlined,
              pageBuilder: (context) => const _PreviewSettingsDetail(
                title: "App Icon",
                description:
                    "This is a good place to judge top chrome spacing and the visual rhythm of rounded iOS-style rows.",
              ),
            ),
          ],
        ),
        _PreviewSettingsCategory(
          title: "Messaging",
          tabs: [
            SettingsTab(
              label: "Emoticons",
              icon: Icons.emoji_emotions_outlined,
              pageBuilder: (context) => const _PreviewSettingsDetail(
                title: "Emoticons",
                description:
                    "Preview how mobile action rows feel when they sit inside grouped sections instead of flat cards.",
              ),
            ),
            SettingsTab(
              label: "Notifications",
              icon: Icons.notifications_none_outlined,
              pageBuilder: (context) => const _PreviewSettingsDetail(
                title: "Notifications",
                description:
                    "Helpful for checking spacing, depth, and back-navigation chrome without changing app behavior.",
              ),
            ),
          ],
        ),
      ];

  List<SettingsButton> get _previewButtons => [
        SettingsButton(
          label: "Sign Out",
          icon: Icons.logout,
          color: Colors.redAccent,
          onPress: () {},
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final theme = _darkMode ? ThemeDark.theme : ThemeLight.theme;

    return AnimatedTheme(
      data: theme,
      duration: const Duration(milliseconds: 200),
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;

          return Scaffold(
            backgroundColor: scheme.surface,
            body: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.surfaceContainerHighest
                                .withValues(alpha: 0.16),
                            scheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final stackVertically = constraints.maxWidth < 1050;

                      final infoPanel = _PreviewInfoPanel(
                        darkMode: _darkMode,
                        onRevealLeft: () =>
                            _panelsKey.currentState?.reveal(RevealSide.left),
                        onRevealMain: () =>
                            _panelsKey.currentState?.reveal(RevealSide.main),
                        onRevealRight: () =>
                            _panelsKey.currentState?.reveal(RevealSide.right),
                        onToggleTheme: () => setState(() {
                          _darkMode = !_darkMode;
                        }),
                      );

                      final previewPanel = _DeviceFrame(
                        child: DefaultTabController(
                          length: 5,
                          child: Column(
                            children: [
                              const _PreviewPhoneChrome(),
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 10),
                                child: Container(
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: scheme.surfaceContainerHigh
                                        .withValues(alpha: 0.48),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: scheme.outline
                                          .withValues(alpha: 0.12),
                                    ),
                                  ),
                                  child: const TabBar(
                                    dividerColor: Colors.transparent,
                                    indicatorSize: TabBarIndicatorSize.tab,
                                    isScrollable: true,
                                    tabs: [
                                      Tab(text: "Shell"),
                                      Tab(text: "Chat"),
                                      Tab(text: "Settings"),
                                      Tab(text: "Panels"),
                                      Tab(text: "Surfaces"),
                                    ],
                                  ),
                                ),
                              ),
                              const Expanded(
                                child: TabBarView(
                                  children: [
                                    _ShellPreview(),
                                    _ChatPreview(),
                                    _SettingsPreviewHost(),
                                    _PanelsPreviewHost(),
                                    _SurfacePreview(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );

                      return stackVertically
                          ? ListView(
                              padding: const EdgeInsets.all(24),
                              children: [
                                infoPanel,
                                const SizedBox(height: 24),
                                Align(
                                  alignment: Alignment.topCenter,
                                  child: previewPanel,
                                ),
                              ],
                            )
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(width: 360, child: infoPanel),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: previewPanel,
                                    ),
                                  ),
                                ],
                              ),
                            );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PreviewInfoPanel extends StatelessWidget {
  const _PreviewInfoPanel({
    required this.darkMode,
    required this.onRevealLeft,
    required this.onRevealMain,
    required this.onRevealRight,
    required this.onToggleTheme,
  });

  final bool darkMode;
  final VoidCallback onRevealLeft;
  final VoidCallback onRevealMain;
  final VoidCallback onRevealRight;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 92,
          height: 32,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              colors: [
                scheme.surfaceContainerHighest.withValues(alpha: 0.45),
                scheme.surfaceContainer.withValues(alpha: 0.22),
              ],
            ),
            border: Border.all(
              color: scheme.outline.withValues(alpha: 0.16),
            ),
          ),
          alignment: Alignment.center,
          child: const tiamat.Text.labelLow("Preview"),
        ),
        const SizedBox(height: 12),
        const tiamat.Text.largeTitle("iOS Mobile Pass"),
        const SizedBox(height: 8),
        tiamat.Text.body(
          "This sandbox now covers the shell, chat composer, picker layout, settings, panels, and shared mobile surfaces. Use it for quick Chrome iteration before building mobile targets.",
        ),
        const SizedBox(height: 20),
        MobileSectionCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const tiamat.Text.labelLow("Appearance"),
                    const SizedBox(height: 2),
                    tiamat.Text.body(
                      darkMode
                          ? "Dark preview lighting"
                          : "Light preview lighting",
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 110,
                child: MobilePillButton(
                  label: darkMode ? "Dark" : "Light",
                  icon: darkMode
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  highlighted: true,
                  onTap: onToggleTheme,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionHeader(label: "Quick Controls"),
        const SizedBox(height: 12),
        MobileSectionCard(
          padding: MobileVisuals.groupedSectionPadding,
          child: Column(
            children: [
              MobilePillButton(
                label: "Reveal left panel",
                icon: Icons.menu_open,
                onTap: onRevealLeft,
              ),
              const SizedBox(height: 8),
              MobilePillButton(
                label: "Center panels",
                icon: Icons.dashboard_customize_outlined,
                onTap: onRevealMain,
              ),
              const SizedBox(height: 8),
              MobilePillButton(
                label: "Reveal right panel",
                icon: Icons.tune,
                onTap: onRevealRight,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionHeader(label: "Edit First"),
        const SizedBox(height: 12),
        MobileSectionCard(
          padding: MobileVisuals.groupedSectionPadding,
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _FileHint(path: "lib/ui/pages/main/main_page_view_mobile.dart"),
              SizedBox(height: 8),
              _FileHint(path: "lib/ui/atoms/room_header.dart"),
              SizedBox(height: 8),
              _FileHint(path: "lib/ui/molecules/message_input.dart"),
              SizedBox(height: 8),
              _FileHint(path: "lib/ui/molecules/emoticon_picker.dart"),
              SizedBox(height: 8),
              _FileHint(path: "lib/ui/molecules/emoji_picker.dart"),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShellPreview extends StatelessWidget {
  const _ShellPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          Container(
            width: 90,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topRight: Radius.circular(MobileVisuals.panelRadius),
                bottomRight: Radius.circular(MobileVisuals.panelRadius),
              ),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surfaceContainerHighest.withValues(alpha: 0.12),
                  scheme.surfaceContainerLow,
                ],
              ),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                const _NavBadge(icon: Icons.home_rounded, selected: true),
                const SizedBox(height: 10),
                const _NavBadge(icon: Icons.star_rounded),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 16),
                const _AvatarRailItem(color: Color(0xFF3C7AE6)),
                const SizedBox(height: 10),
                const _AvatarRailItem(color: Color(0xFF9C5AF1)),
                const SizedBox(height: 10),
                const _AvatarRailItem(color: Color(0xFFF79E3D)),
                const Spacer(),
                const _NavBadge(icon: Icons.add_rounded),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(MobileVisuals.panelRadius),
              child: ColoredBox(
                color: scheme.surfaceContainerLow,
                child: Column(
                  children: [
                    _PreviewHeroHeader(scheme: scheme),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _ShellRoomRow(
                              icon: Icons.tag_rounded,
                              label: "General",
                              selected: true,
                            ),
                            SizedBox(height: 10),
                            _ShellRoomRow(
                              icon: Icons.campaign_outlined,
                              label: "Announcements",
                            ),
                            SizedBox(height: 10),
                            _ShellRoomRow(
                              icon: Icons.mic_none_rounded,
                              label: "Voice Chat",
                            ),
                            SizedBox(height: 10),
                            _ShellRoomRow(
                              icon: Icons.calendar_today_outlined,
                              label: "Calendar",
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(
                      height: 86,
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: scheme.outline.withValues(alpha: 0.12),
                          ),
                        ),
                        color: scheme.surfaceContainer,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: const Row(
                        children: [
                          CircleAvatar(radius: 22),
                          SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                tiamat.Text.largeTitle("Preview User"),
                                tiamat.Text.labelLow(
                                  "@preview:ourgalaxy.space",
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.settings_rounded),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Container(
          height: 62,
          margin: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                scheme.surfaceContainerHighest.withValues(alpha: 0.12),
                scheme.surfaceContainerLow,
              ],
            ),
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: const Row(
            children: [
              Icon(Icons.menu_rounded),
              SizedBox(width: 12),
              CircleAvatar(radius: 16),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    tiamat.Text.largeTitle("Botless"),
                    tiamat.Text.labelLow("General discussion"),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
            children: const [
              _TimelineDivider(label: "Friday, April 24"),
              SizedBox(height: 12),
              _MessageRow(name: "Mouse Droid", body: "test", time: "12:46 AM"),
              SizedBox(height: 20),
              _TimelineDivider(label: "10:28 PM"),
              SizedBox(height: 12),
              _MessageRow(
                name: "Preview User",
                body: "Test",
                time: "10:28 PM",
              ),
              SizedBox(height: 14),
              _MessageRow(
                name: "Preview User",
                body: "Message\n\nMessage\n(Edited)",
                time: "11:13 PM",
              ),
            ],
          ),
        ),
        _ComposerPreview(scheme: scheme),
      ],
    );
  }
}

class _ComposerPreview extends StatelessWidget {
  const _ComposerPreview({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(
            color: scheme.outline.withValues(alpha: 0.14),
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surfaceContainerHighest.withValues(alpha: 0.14),
                  scheme.surfaceContainerLow,
                ],
              ),
              border: Border.all(
                color: scheme.outline.withValues(alpha: 0.12),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _MiniAction(icon: Icons.add_rounded, scheme: scheme),
                const SizedBox(width: 6),
                const Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: tiamat.Text.labelLow("Send an encrypted message"),
                  ),
                ),
                _MiniAction(
                    icon: Icons.emoji_emotions_outlined, scheme: scheme),
                const SizedBox(width: 6),
                _MiniAction(icon: Icons.more_horiz_rounded, scheme: scheme),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            height: 300,
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(MobileVisuals.panelRadius),
              ),
              border: Border(
                top: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.14),
                ),
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _SegmentLabel("Emoji", true),
                        _SegmentLabel("Sticker", false),
                        _SegmentLabel("Gif", false),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: const Row(
                      children: [
                        Icon(Icons.search_rounded),
                        SizedBox(width: 8),
                        tiamat.Text.labelLow("Search"),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: SizedBox(
                    height: 54,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: const [
                        _PackChip(selected: true),
                        _PackChip(),
                        _PackChip(),
                        _PackChip(),
                        _PackChip(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    children: const [
                      _EmojiCell("😀"),
                      _EmojiCell("👍"),
                      _EmojiCell("❤️"),
                      _EmojiCell("🔥"),
                      _EmojiCell("😂"),
                      _EmojiCell("🥲"),
                      _EmojiCell("🚀"),
                      _EmojiCell("✨"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPreviewHost extends StatelessWidget {
  const _SettingsPreviewHost();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_MobileUiPreviewPageState>()!;
    return MobileSettingsPage(
      settings: state._previewSettings,
      buttons: state._previewButtons,
    );
  }
}

class _PanelsPreviewHost extends StatelessWidget {
  const _PanelsPreviewHost();

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_MobileUiPreviewPageState>()!;
    return _PanelPreview(panelsKey: state._panelsKey);
  }
}

class _PanelPreview extends StatelessWidget {
  const _PanelPreview({required this.panelsKey});

  final GlobalKey<OverlappingPanelsState> panelsKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: MobileVisuals.panelBorderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: MobileVisuals.panelBorderRadius,
          child: OverlappingPanels(
            key: panelsKey,
            left: _PanelCard(
              title: "Left Panel",
              color: Colors.deepPurple.shade400,
              icon: Icons.space_dashboard_outlined,
            ),
            main: _PanelCard(
              title: "Main Panel",
              color: Colors.indigo.shade400,
              icon: Icons.chat_bubble_outline,
            ),
            right: _PanelCard(
              title: "Right Panel",
              color: Colors.teal.shade500,
              icon: Icons.info_outline,
            ),
            restWidth: 72,
            scaleFactor: 1.0,
          ),
        ),
      ),
    );
  }
}

class _SurfacePreview extends StatelessWidget {
  const _SurfacePreview();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: MobileVisuals.screenEdgeInsets,
      children: [
        const _SectionHeader(label: "Rounded Surfaces"),
        const SizedBox(height: 12),
        MobileSectionCard(
          padding: MobileVisuals.groupedSectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const tiamat.Text.largeTitle("Mobile Section Card"),
              const SizedBox(height: 8),
              tiamat.Text.body(
                "Tune grouped-card radius, inset padding, and subtle lighting here before touching shared widgets.",
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _SectionHeader(label: "Pill Buttons"),
        const SizedBox(height: 12),
        MobileSectionCard(
          padding: MobileVisuals.groupedSectionPadding,
          child: const Column(
            children: [
              MobilePillButton(
                label: "Default row",
                icon: Icons.circle_outlined,
              ),
              SizedBox(height: 8),
              MobilePillButton(
                label: "Highlighted row",
                icon: Icons.check_circle_outline,
                highlighted: true,
              ),
              SizedBox(height: 8),
              MobilePillButton(
                label: "Accent row",
                icon: Icons.favorite_border,
                color: Colors.pinkAccent,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewSettingsDetail extends StatelessWidget {
  const _PreviewSettingsDetail({
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        tiamat.Text.largeTitle(title),
        const SizedBox(height: 12),
        MobileSectionCard(
          padding: MobileVisuals.groupedSectionPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              tiamat.Text.body(description),
              const SizedBox(height: 16),
              const MobilePillButton(
                label: "Preview action",
                icon: Icons.touch_app_outlined,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewHeroHeader extends StatelessWidget {
  const _PreviewHeroHeader({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.26),
            scheme.surfaceContainerHigh,
          ],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Spacer(),
          tiamat.Text.largeTitle("Admin"),
          SizedBox(height: 2),
          tiamat.Text.labelLow("Space overview"),
        ],
      ),
    );
  }
}

class _ShellRoomRow extends StatelessWidget {
  const _ShellRoomRow({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.transparent,
      ),
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 14),
          Expanded(child: tiamat.Text.largeTitle(label)),
        ],
      ),
    );
  }
}

class _TimelineDivider extends StatelessWidget {
  const _TimelineDivider({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: tiamat.Text.labelLow(label),
        ),
        Expanded(
          child: Divider(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }
}

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.name,
    required this.body,
    required this.time,
  });

  final String name;
  final String body;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(radius: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: tiamat.Text.largeTitle(name)),
                  tiamat.Text.labelLow(time),
                ],
              ),
              const SizedBox(height: 4),
              tiamat.Text.body(body),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.scheme,
  });

  final IconData icon;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Icon(icon, size: 20),
    );
  }
}

class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel(this.text, this.selected);

  final String text;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Colors.transparent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: tiamat.Text.labelLow(text),
    );
  }
}

class _PackChip extends StatelessWidget {
  const _PackChip({this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: const Icon(Icons.emoji_emotions_outlined),
    );
  }
}

class _EmojiCell extends StatelessWidget {
  const _EmojiCell(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Text(
          value,
          style: const TextStyle(fontSize: 28),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({
    required this.icon,
    this.selected = false,
  });

  final IconData icon;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 66,
      height: 66,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : Theme.of(context).colorScheme.surfaceContainerLow,
        border: selected
            ? Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.18),
              )
            : null,
      ),
      child: Icon(icon, size: 34),
    );
  }
}

class _AvatarRailItem extends StatelessWidget {
  const _AvatarRailItem({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.color,
    required this.icon,
  });

  final String title;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(
        child: MobileSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          mode: tiamat.TileType.surfaceContainer,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36),
              const SizedBox(height: 12),
              tiamat.Text.largeTitle(title),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 430,
      height: 932,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF101216),
            Color(0xFF000000),
          ],
        ),
        borderRadius: BorderRadius.circular(42),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surface,
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _PreviewPhoneChrome extends StatelessWidget {
  const _PreviewPhoneChrome();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 116,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: scheme.surfaceContainerHigh.withValues(alpha: 0.38),
                ),
                child: const tiamat.Text.labelLow("9:41"),
              ),
              const Spacer(),
              Icon(
                Icons.signal_cellular_alt,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.wifi_rounded,
                size: 16,
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.battery_full_rounded,
                size: 18,
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return tiamat.Text.labelLow(label);
  }
}

class _FileHint extends StatelessWidget {
  const _FileHint({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.code, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: tiamat.Text.body(path),
        ),
      ],
    );
  }
}

class _PreviewSettingsCategory implements SettingsCategory {
  _PreviewSettingsCategory({
    required this.tabs,
    this.title,
  });

  @override
  final String? title;

  @override
  final List<SettingsTab> tabs;
}
