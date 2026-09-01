import 'package:intergalactic/config/platform_utils.dart';
import 'package:intergalactic/ui/atoms/scaled_safe_area.dart';
import 'package:intergalactic/ui/mobile/mobile_surface.dart';
import 'package:intergalactic/ui/mobile/mobile_visuals.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_account_scope.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';
import 'package:intergalactic/ui/pages/settings/settings_search_anchor.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:intergalactic/ui/pages/settings/settings_typography.dart';
import 'package:flutter/cupertino.dart' as c;
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
  static const _mainHeaderPadding = EdgeInsets.fromLTRB(8, 8, 8, 12);

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
          _pushSettingsSubPage(
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
              fit: StackFit.expand,
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
                Positioned.fill(
                  child: Tile.surfaceContainer(
                    child: ScaledSafeArea(
                      child: Padding(
                        padding: MobileVisuals.screenEdgeInsets,
                        child: Column(
                          children: [
                            _MobileSettingsHeaderSurface(
                              child: Padding(
                                padding: _mainHeaderPadding,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 42,
                                      height: 5,
                                      decoration: m.BoxDecoration(
                                        color: theme.colorScheme.outline
                                            .withValues(alpha: 0.24),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    SizedBox(
                                      height: 50,
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
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
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                tiamat.Text.labelLow(
                                                  "Settings",
                                                ),
                                                SizedBox(height: 2),
                                                tiamat.Text.labelEmphasised(
                                                  "Explore",
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const SettingsAccountHeader(compact: true),
                                    const SizedBox(height: 14),
                                    buildSearchField(context),
                                  ],
                                ),
                              ),
                            ),
                            Flexible(
                              child: ListView(
                                children: [
                                  if (visibleCategories.isEmpty)
                                    SettingsStatePanel(
                                      icon: m.Icons.manage_search_rounded,
                                      title: "No settings found",
                                      description:
                                          'No settings match "$_searchQuery". Clear the search or try a different term.',
                                      padding: const EdgeInsets.only(
                                        bottom: 14,
                                      ),
                                      action: MobilePillButton(
                                        label: "Clear search",
                                        icon: m.Icons.close_rounded,
                                        onTap: clearSearch,
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
                                          padding: const EdgeInsets.only(
                                            bottom: 14,
                                          ),
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
                                                        .category
                                                        .title !=
                                                    null)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                          4,
                                                          2,
                                                          4,
                                                          10,
                                                        ),
                                                    child: tiamat.Text.labelLow(
                                                      searchCategory
                                                          .category
                                                          .title!,
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
                                              vertical: 4,
                                            ),
                                            child: button(
                                              label: b.label,
                                              icon: b.icon,
                                              color: b.color,
                                              onTap: b.onPress,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
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
        onSubmitted: (_) => _openFirstSearchResult(),
        textInputAction: m.TextInputAction.search,
        decoration: m.InputDecoration(
          hintText: "Search settings",
          hintStyle: settingsHintTextStyle(context),
          prefixIcon: const Icon(m.Icons.search, size: 20),
          suffixIcon: hasSearchQuery
              ? m.IconButton(
                  tooltip: "Clear search",
                  icon: const Icon(m.Icons.close, size: 18),
                  onPressed: clearSearch,
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
      child: ClipRRect(borderRadius: radius, child: field),
    );
  }

  void clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = "";
    });
  }

  void _openFirstSearchResult() {
    if (!hasSearchQuery) {
      return;
    }

    final visibleCategories = filteredCategories;
    for (final searchCategory in visibleCategories) {
      for (final searchTab in searchCategory.tabs) {
        _openSearchTab(
          searchTab,
          searchTab.entries.isEmpty ? null : searchTab.entries.first,
        );
        return;
      }
    }
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
                  onTap: () => _openSearchTab(searchTab, entry),
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

  void _openSearchTab(
    SettingsSearchTab searchTab, [
    SettingsSearchEntry? entry,
  ]) {
    _pushSettingsSubPage(
      SettingsSubPage(
        makeScrollable: searchTab.tab.makeScrollable,
        builder: searchTab.tab.pageBuilder,
        accountController: SettingsAccountScope.maybeRead(context),
        initialSearchAnchorId: entry?.effectiveAnchorId,
      ),
    );
  }

  void _pushSettingsSubPage(SettingsSubPage page) {
    if (PlatformUtils.isIOS) {
      Navigator.of(context).push(c.CupertinoPageRoute(builder: (_) => page));
      return;
    }

    NavigationUtils.navigateTo(context, page);
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
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: 0.54,
            ),
            border: Border.all(
              color: theme.colorScheme.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
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

  Widget button({
    required String label,
    IconData? icon,
    bool highlighted = false,
    Color? color,
    Function()? onTap,
  }) {
    return MobilePillButton(
      label: label,
      icon: icon,
      highlighted: highlighted,
      color: color,
      onTap: onTap,
    );
  }
}

class _MobileSettingsHeaderSurface extends StatelessWidget {
  const _MobileSettingsHeaderSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = m.Theme.of(context);

    return DecoratedBox(
      decoration: m.BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.20),
        ),
      ),
      child: child,
    );
  }
}

class SettingsSubPage extends StatefulWidget {
  const SettingsSubPage({
    required this.builder,
    super.key,
    this.makeScrollable = true,
    this.accountController,
    this.initialSearchAnchorId,
  });
  final Widget Function(BuildContext) builder;
  final bool makeScrollable;
  final SettingsAccountController? accountController;
  final String? initialSearchAnchorId;

  @override
  State<SettingsSubPage> createState() => _SettingsSubPageState();
}

class _SettingsSubPageState extends State<SettingsSubPage> {
  static const double _headerHeight = 80;
  static const _headerPadding = EdgeInsets.fromLTRB(4, 8, 4, 8);

  final SettingsSearchHighlightController _searchHighlightController =
      SettingsSearchHighlightController();

  @override
  void initState() {
    super.initState();
    _scheduleInitialSearchHighlight();
  }

  @override
  void didUpdateWidget(covariant SettingsSubPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSearchAnchorId != widget.initialSearchAnchorId) {
      _scheduleInitialSearchHighlight();
    }
  }

  @override
  void dispose() {
    _searchHighlightController.dispose();
    super.dispose();
  }

  void _scheduleInitialSearchHighlight() {
    final anchorId = widget.initialSearchAnchorId;
    if (anchorId == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.initialSearchAnchorId != anchorId) {
        return;
      }
      _searchHighlightController.highlight(anchorId);
    });
  }

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
                    fit: StackFit.expand,
                    children: [
                      if (widget.makeScrollable)
                        Positioned.fill(
                          child: ListView(
                            padding: const EdgeInsets.only(top: _headerHeight),
                            children: [widget.builder(context)],
                          ),
                        ),
                      if (!widget.makeScrollable)
                        Positioned.fill(
                          child: m.Padding(
                            padding: const EdgeInsets.fromLTRB(
                              0,
                              _headerHeight,
                              0,
                              0,
                            ),
                            child: widget.builder(context),
                          ),
                        ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: 0,
                        child: _MobileSettingsHeaderSurface(
                          child: m.Padding(
                            padding: _headerPadding,
                            child: SizedBox(
                              height: 50,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  CircleButton(
                                    radius: 25,
                                    icon: m.Icons.arrow_back_ios_new,
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Center(
                                      child: SettingsSearchHighlightTarget(
                                        anchorId: 'settings-account-header',
                                        child: SettingsAccountHeader(
                                          compact: true,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );

    final highlightedContent = SettingsSearchHighlightScope(
      controller: _searchHighlightController,
      child: content,
    );

    final controller = widget.accountController;
    if (controller == null) {
      return highlightedContent;
    }

    return SettingsAccountScope(
      controller: controller,
      child: highlightedContent,
    );
  }
}
