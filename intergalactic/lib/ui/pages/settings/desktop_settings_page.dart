import 'package:intergalactic/ui/pages/settings/settings_account_header.dart';
import 'package:intergalactic/ui/pages/settings/settings_button.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';
import 'package:intergalactic/ui/pages/settings/settings_typography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as m;

import 'package:tiamat/tiamat.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

class DesktopSettingsPage extends StatefulWidget {
  const DesktopSettingsPage({
    required this.settings,
    this.buttons,
    this.initialTabId,
    super.key,
  });
  final List<SettingsCategory> settings;
  final List<SettingsButton>? buttons;
  final String? initialTabId;
  @override
  State<DesktopSettingsPage> createState() => DesktopSettingsPageState();
}

class DesktopSettingsPageState extends State<DesktopSettingsPage> {
  late List<SettingsCategory> categories;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _contentScrollController = ScrollController();
  String _searchQuery = "";
  int selectedCategoryIndex = 0;
  int selectedTabIndex = 0;

  static ValueKey backButtonKey =
      const ValueKey("DESKTOP_SETTINGS_PAGE_BACK_BUTTON");

  @override
  void initState() {
    categories = widget.settings;
    super.initState();
    selectInitialTab();
  }

  @override
  void didUpdateWidget(covariant DesktopSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.settings, widget.settings)) {
      categories = widget.settings;
      final selectedInitialTab = selectInitialTab();
      ensureSelectionIsVisible();
      if (selectedInitialTab) {
        setState(() {});
      }
    } else if (oldWidget.initialTabId != widget.initialTabId) {
      if (selectInitialTab()) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _contentScrollController.dispose();
    super.dispose();
  }

  List<SettingsSearchCategory> get filteredCategories =>
      filterSettingsCategories(categories, _searchQuery);

  bool get hasSearchQuery => _searchQuery.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final visibleCategories = filteredCategories;

    return SettingsTypography(
      child: Builder(
        builder: (context) {
          final theme = m.Theme.of(context);

          return m.Material(
            color: theme.colorScheme.surfaceContainer,
            child: Row(
              children: [
                tabSelector(context),
                Expanded(
                  child: Column(
                    children: [
                      contentHeader(context),
                      Expanded(
                        child: visibleCategories.isEmpty
                            ? buildEmptySearchContent()
                            : buildActiveContent(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget buildEmptySearchContent() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 40, 44, 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const tiamat.Text.largeTitle("No settings found"),
              const SizedBox(height: 8),
              tiamat.Text.body(
                'Try a different search for "$_searchQuery".',
                softwrap: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildActiveContent() {
    if (selectedCategoryIndex < 0 ||
        selectedCategoryIndex >= categories.length) {
      return const SizedBox.shrink();
    }

    final category = categories[selectedCategoryIndex];
    if (selectedTabIndex < 0 || selectedTabIndex >= category.tabs.length) {
      return const SizedBox.shrink();
    }

    final tab = category.tabs[selectedTabIndex];
    final content = buildContent();

    if (!tab.makeScrollable) {
      return content;
    }

    return m.Scrollbar(
      controller: _contentScrollController,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _contentScrollController,
        child: content,
      ),
    );
  }

  Widget buildContent() {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(44, 36, 44, 44),
          child: selectedCategoryIndex < categories.length &&
                  selectedTabIndex <
                      categories[selectedCategoryIndex].tabs.length
              ? settingsTab(
                  categories[selectedCategoryIndex]
                      .tabs[selectedTabIndex]
                      .pageBuilder,
                )
              : Container(),
        ),
      ),
    );
  }

  Widget contentHeader(BuildContext context) {
    final theme = m.Theme.of(context);
    final title = selectedCategoryIndex < categories.length &&
            selectedTabIndex < categories[selectedCategoryIndex].tabs.length
        ? categories[selectedCategoryIndex].tabs[selectedTabIndex].label
        : "Settings";

    return Container(
      height: 48,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: m.Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w400,
                letterSpacing: 0,
              ),
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 12, 0),
            child: m.IconButton(
              key: backButtonKey,
              tooltip: "Close settings",
              icon: const Icon(m.Icons.close_rounded),
              color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }

  Widget tabSelector(BuildContext context) {
    final theme = m.Theme.of(context);

    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.14),
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 14, 14),
        child: Column(
          children: [
            const SettingsAccountHeader(),
            const SizedBox(height: 18),
            buildSearchField(context),
            const SizedBox(height: 14),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListView.builder(
                    physics: const NeverScrollableScrollPhysics(),
                    shrinkWrap: true,
                    itemCount: filteredCategories.length,
                    itemBuilder: (context, visibleIndex) {
                      final searchCategory = filteredCategories[visibleIndex];
                      final category = searchCategory.category;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (visibleIndex != 0) const SizedBox(height: 16),
                          if (category.title != null)
                            Padding(
                              padding: const EdgeInsets.fromLTRB(0, 4, 0, 6),
                              child: tiamat.Text.labelLow(category.title!),
                            ),
                          tabListBuilder(searchCategory),
                        ],
                      );
                    },
                  ),
                  if (widget.buttons != null && !hasSearchQuery)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(0, 12, 0, 8),
                      child: Seperator(),
                    ),
                  if (widget.buttons != null && !hasSearchQuery)
                    ListView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: widget.buttons!.length,
                      itemBuilder: (context, index) {
                        return button(
                          label: widget.buttons![index].label,
                          icon: widget.buttons![index].icon,
                          onTap: widget.buttons![index].onPress,
                          color: widget.buttons![index].color,
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSearchField(BuildContext context) {
    final theme = m.Theme.of(context);

    return SizedBox(
      height: 42,
      child: m.TextField(
        controller: _searchController,
        onChanged: updateSearchQuery,
        textInputAction: m.TextInputAction.search,
        decoration: m.InputDecoration(
          hintText: "Search settings",
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
          fillColor: theme.colorScheme.surface.withValues(alpha: 0.72),
          border: m.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: m.BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
          ),
          enabledBorder: m.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: m.BorderSide(
              color: theme.colorScheme.outline.withValues(alpha: 0.08),
            ),
          ),
          focusedBorder: m.OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: m.BorderSide(
              color: theme.colorScheme.primary.withValues(alpha: 0.76),
            ),
          ),
        ),
      ),
    );
  }

  void clearSearch() {
    _searchController.clear();
    updateSearchQuery("");
  }

  void updateSearchQuery(String value) {
    setState(() {
      _searchQuery = value;
      ensureSelectionIsVisible();
    });
  }

  void ensureSelectionIsVisible() {
    final visibleCategories = filteredCategories;
    if (visibleCategories.isEmpty) {
      return;
    }

    final selectionVisible = visibleCategories.any((category) {
      return category.categoryIndex == selectedCategoryIndex &&
          category.tabs.any((tab) => tab.tabIndex == selectedTabIndex);
    });

    if (selectionVisible) {
      return;
    }

    selectedCategoryIndex = visibleCategories.first.categoryIndex;
    selectedTabIndex = visibleCategories.first.tabs.first.tabIndex;
  }

  bool selectInitialTab() {
    final initialTabId = widget.initialTabId;
    if (initialTabId == null) {
      return false;
    }

    for (var categoryIndex = 0;
        categoryIndex < categories.length;
        categoryIndex++) {
      final tabs = categories[categoryIndex].tabs;
      for (var tabIndex = 0; tabIndex < tabs.length; tabIndex++) {
        if (tabs[tabIndex].id == initialTabId) {
          final selectionChanged = selectedCategoryIndex != categoryIndex ||
              selectedTabIndex != tabIndex;
          selectedCategoryIndex = categoryIndex;
          selectedTabIndex = tabIndex;
          return selectionChanged;
        }
      }
    }

    return false;
  }

  Widget tabListBuilder(SettingsSearchCategory searchCategory) {
    return Column(
      children: [
        for (final searchTab in searchCategory.tabs)
          if (hasSearchQuery && searchTab.entries.isNotEmpty)
            for (final entry in searchTab.entries)
              searchResultButton(
                searchCategory: searchCategory,
                searchTab: searchTab,
                entry: entry,
              )
          else
            button(
                label: searchTab.tab.label,
                icon: searchTab.tab.icon,
                highlighted:
                    searchCategory.categoryIndex == selectedCategoryIndex &&
                        searchTab.tabIndex == selectedTabIndex,
                onTap: () {
                  setState(() {
                    selectedCategoryIndex = searchCategory.categoryIndex;
                    selectedTabIndex = searchTab.tabIndex;
                  });
                }),
      ],
    );
  }

  Widget searchResultButton({
    required SettingsSearchCategory searchCategory,
    required SettingsSearchTab searchTab,
    required SettingsSearchEntry entry,
  }) {
    final theme = m.Theme.of(context);
    final highlighted = searchCategory.categoryIndex == selectedCategoryIndex &&
        searchTab.tabIndex == selectedTabIndex;
    final caption = [
      searchTab.tab.label,
      if (entry.section != null) entry.section!,
    ].join(" / ");

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: m.Material(
        color: highlighted
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.72)
            : m.Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: m.InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() {
              selectedCategoryIndex = searchCategory.categoryIndex;
              selectedTabIndex = searchTab.tabIndex;
            });
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
            child: Row(
              children: [
                if (searchTab.tab.icon != null) ...[
                  Icon(
                    searchTab.tab.icon,
                    size: 18,
                    color: highlighted
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      m.Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      m.Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
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
      ),
    );
  }

  Widget button(
      {required String label,
      IconData? icon,
      bool highlighted = false,
      Color? color,
      Function()? onTap}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 2),
      child: SizedBox(
          height: 40,
          width: double.infinity,
          child: TextButton(
            label,
            icon: icon,
            highlighted: highlighted,
            onTap: onTap,
            textColor: color,
            iconColor: color,
          )),
    );
  }

  Widget settingsTab(Widget Function(BuildContext context) builder) {
    return builder(context);
  }
}
