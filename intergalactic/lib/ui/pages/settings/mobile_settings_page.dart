import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';
import 'package:intergalactic/ui/pages/settings/settings_typography.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter/widgets.dart';
import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

import '../../navigation/navigation_utils.dart';

class MobileSettingsPage extends StatefulWidget {
  const MobileSettingsPage({
    required this.settings,
    this.buttons,
    this.initialTabId,
    super.key,
  });
  final List<SettingsButton>? buttons;
  final List<SettingsCategory> settings;
  final String? initialTabId;

  @override
  State<MobileSettingsPage> createState() => _MobileSettingsPageState();
}

class _MobileSettingsPageState extends State<MobileSettingsPage> {
  late List<SettingsCategory> tabs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  int selectedTabIndex = 0;
  int selectedCategoryIndex = 0;
  bool _openedInitialTab = false;

  @override
  void initState() {
    tabs = widget.settings;
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => openInitialTab());
  }

  @override
  void didUpdateWidget(covariant MobileSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final settingsChanged = !identical(oldWidget.settings, widget.settings);
    if (settingsChanged) {
      tabs = widget.settings;
    }
    if (oldWidget.initialTabId != widget.initialTabId) {
      _openedInitialTab = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => openInitialTab());
    } else if (settingsChanged &&
        !_openedInitialTab &&
        widget.initialTabId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openInitialTab());
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SettingsSearchCategory> get filteredCategories =>
      filterSettingsCategories(tabs, _searchQuery);

  bool get hasSearchQuery => _searchQuery.trim().isNotEmpty;

  void openInitialTab() {
    if (_openedInitialTab || !mounted || widget.initialTabId == null) {
      return;
    }

    for (final category in tabs) {
      for (final tab in category.tabs) {
        if (tab.id == widget.initialTabId) {
          _openedInitialTab = true;
          NavigationUtils.navigateTo(
            context,
            SettingsSubPage(
              makeScrollable: tab.makeScrollable,
              builder: tab.pageBuilder,
              accountController: SettingsAccountScope.maybeRead(context),
            ),
          );
          return;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visibleCategories = filteredCategories;

    return SettingsTypography(
      child: Builder(
        builder: (context) {
          final theme = m.Theme.of(context);

          return m.Material(
            color: theme.colorScheme.surface,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: m.BoxDecoration(
                        gradient: m.LinearGradient(
                          begin: m.Alignment.topCenter,
                          end: m.Alignment.bottomCenter,
                          colors: [
                            theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.1),
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Tile.surfaceContainer(
                  child: ScaledSafeArea(
                    child: Padding(
                      padding: MobileVisuals.screenEdgeInsets,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                            child: Column(
                              children: [
                                Container(
                                  width: 42,
                                  height: 5,
                                  decoration: m.BoxDecoration(
                                    color: theme.colorScheme.outline
                                        .withValues(alpha: 0.24),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    CircleButton(
                                      radius: 25,
                                      icon: m.Icons.arrow_back_ios_new,
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          tiamat.Text.labelLow("Settings"),
                                          SizedBox(height: 2),
                                          tiamat.Text.largeTitle("Explore"),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const SettingsAccountHeader(compact: true),
                                const SizedBox(height: 12),
                                buildSearchField(context),
                              ],
                            ),
                          ),
                          Flexible(
                            child: ListView(
                              children: [
                                if (visibleCategories.isEmpty)
                                  MobileSectionCard(
                                    padding:
                                        MobileVisuals.groupedSectionPadding,
                                    child: m.Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const tiamat.Text.labelEmphasised(
                                            "No settings found"),
                                        const SizedBox(height: 8),
                                        tiamat.Text.body(
                                          'Try a different search for "$_searchQuery".',
                                          softwrap: true,
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: visibleCategories.length,
                                    itemBuilder: (context, visibleIndex) {
                                      final searchCategory =
                                          visibleCategories[visibleIndex];
                                      return m.Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 14),
                                        child: MobileSectionCard(
                                          padding: MobileVisuals
                                              .groupedSectionPadding,
                                          child: m.Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              if (searchCategory
                                                      .category.title !=
                                                  null)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          4, 2, 4, 10),
                                                  child: tiamat.Text.labelLow(
                                                    searchCategory
                                                        .category.title!,
                                                  ),
                                                ),
                                              _buildSearchCategoryResults(
                                                searchCategory,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                if (widget.buttons != null && !hasSearchQuery)
                                  MobileSectionCard(
                                    padding:
                                        MobileVisuals.groupedSectionPadding,
                                    child: ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: widget.buttons!.length,
                                      itemBuilder: (context, index) {
                                        var b = widget.buttons![index];
                                        return Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: button(
                                            label: b.label,
                                            icon: b.icon,
                                            color: b.color,
                                            onTap: b.onPress,
                                          ),
                                        );
                                      },
                                    ),
                                  )
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
        },
      ),
    );
  }

  Widget buildSearchField(BuildContext context) {
    final theme = m.Theme.of(context);
    final useLiquidGlassFallback = PlatformUtils.isIOS;
    final radius = BorderRadius.circular(999);

    final field = SizedBox(
      height: 44,
      child: m.TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        textInputAction: m.TextInputAction.search,
        decoration: m.InputDecoration(
          hintText: "Search settings",
          prefixIcon: const Icon(m.Icons.search, size: 20),
          suffixIcon: hasSearchQuery
              ? m.IconButton(
                  tooltip: "Clear search",
                  icon: const Icon(m.Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = "";
                    });
                  },
                )
              : null,
          isDense: true,
          filled: true,
          fillColor: useLiquidGlassFallback
              ? theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.36)
              : theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.58),
          border: m.OutlineInputBorder(
            borderRadius: radius,
            borderSide: m.BorderSide(
              color: theme.colorScheme.outline.withValues(
                alpha: useLiquidGlassFallback ? 0.07 : 0.14,
              ),
            ),
          ),
          enabledBorder: m.OutlineInputBorder(
            borderRadius: radius,
            borderSide: m.BorderSide(
              color: theme.colorScheme.outline.withValues(
                alpha: useLiquidGlassFallback ? 0.07 : 0.14,
              ),
            ),
          ),
          focusedBorder: m.OutlineInputBorder(
            borderRadius: radius,
            borderSide: m.BorderSide(
              color: theme.colorScheme.primary.withValues(
                alpha: useLiquidGlassFallback ? 0.42 : 0.76,
              ),
            ),
          ),
        ),
      ),
    );

    if (!useLiquidGlassFallback) {
      return field;
    }

    return MobileGlassEdgeHighlight(
      borderRadius: radius,
      style: MobileGlassHighlightStyle.composer,
      intensity: 0.42,
      child: ClipRRect(
        borderRadius: radius,
        child: field,
      ),
    );
  }

  Widget _buildSearchCategoryResults(SettingsSearchCategory searchCategory) {
    return Column(
      children: [
        for (final searchTab in searchCategory.tabs)
          if (hasSearchQuery && searchTab.entries.isNotEmpty)
            for (final entry in searchTab.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: searchResultButton(
                  label: entry.title,
                  subtitle: [
                    searchTab.tab.label,
                    if (entry.section != null) entry.section!,
                  ].join(" / "),
                  icon: searchTab.tab.icon,
                  onTap: () => _openSearchTab(searchTab),
                ),
              )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: button(
                label: searchTab.tab.label,
                icon: searchTab.tab.icon,
                onTap: () => _openSearchTab(searchTab),
              ),
            ),
      ],
    );
  }

  void _openSearchTab(SettingsSearchTab searchTab) {
    setState(() {
      NavigationUtils.navigateTo(
        context,
        SettingsSubPage(
          makeScrollable: searchTab.tab.makeScrollable,
          builder: searchTab.tab.pageBuilder,
          accountController: SettingsAccountScope.maybeRead(context),
        ),
      );
    });
  }

  Widget searchResultButton({
    required String label,
    required String subtitle,
    IconData? icon,
    Function()? onTap,
  }) {
    final theme = m.Theme.of(context);

    return m.Material(
      color: m.Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: m.InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color:
                theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.54),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    m.Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    m.Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget button(
      {required String label,
      IconData? icon,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    return MobilePillButton(
      label: label,
      icon: icon,
      highlighted: highlighted,
      color: color,
      onTap: onTap,
    );
  }
}

class SettingsSubPage extends StatelessWidget {
  const SettingsSubPage(
      {required this.builder,
      super.key,
      this.makeScrollable = true,
      this.accountController});
  final Widget Function(BuildContext) builder;
  final bool makeScrollable;
  final SettingsAccountController? accountController;

  @override
  Widget build(BuildContext context) {
    final content = SettingsTypography(
      child: Builder(
        builder: (context) {
          final theme = m.Theme.of(context);

          return m.Material(
            color: theme.colorScheme.surface,
            child: Tile(
              child: ScaledSafeArea(
                child: m.Padding(
                  padding: MobileVisuals.screenEdgeInsets,
                  child: Stack(
                    children: [
                      if (makeScrollable)
                        ListView(
                          children: [
                            const SizedBox(
                              height: 88,
                            ),
                            builder(context)
                          ],
                        ),
                      if (!makeScrollable)
                        m.Padding(
                          padding: const EdgeInsets.fromLTRB(0, 88, 0, 0),
                          child: builder(context),
                        ),
                      m.Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
                        child: Row(
                          children: [
                            CircleButton(
                              radius: 25,
                              icon: m.Icons.arrow_back_ios_new,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: SettingsAccountHeader(compact: true),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    final controller = accountController;
    if (controller == null) {
      return content;
    }

    return SettingsAccountScope(
      controller: controller,
      child: content,
    );
  }
}
