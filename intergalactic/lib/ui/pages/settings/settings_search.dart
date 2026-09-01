import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';

class SettingsSearchCategory {
  const SettingsSearchCategory({
    required this.category,
    required this.categoryIndex,
    required this.tabs,
  });

  final SettingsCategory category;
  final int categoryIndex;
  final List<SettingsSearchTab> tabs;
}

class SettingsSearchTab {
  const SettingsSearchTab({
    required this.tab,
    required this.tabIndex,
    this.entries = const [],
    this.tabMatched = false,
  });

  final SettingsTab tab;
  final int tabIndex;
  final List<SettingsSearchEntry> entries;
  final bool tabMatched;
}

List<SettingsSearchCategory> filterSettingsCategories(
  List<SettingsCategory> categories,
  String query,
) {
  final normalizedQuery = _normalizeSearchText(query);

  return [
    for (var categoryIndex = 0;
        categoryIndex < categories.length;
        categoryIndex += 1)
      if (_filterCategory(
        categories[categoryIndex],
        categoryIndex,
        normalizedQuery,
      )
          case final category?)
        category,
  ];
}

SettingsSearchCategory? _filterCategory(
  SettingsCategory category,
  int categoryIndex,
  String normalizedQuery,
) {
  if (normalizedQuery.isEmpty) {
    return SettingsSearchCategory(
      category: category,
      categoryIndex: categoryIndex,
      tabs: [
        for (var tabIndex = 0; tabIndex < category.tabs.length; tabIndex += 1)
          SettingsSearchTab(tab: category.tabs[tabIndex], tabIndex: tabIndex),
      ],
    );
  }

  final categoryMatches = _matches(category.title, normalizedQuery);
  final matchingTabs = <SettingsSearchTab>[];

  for (var tabIndex = 0; tabIndex < category.tabs.length; tabIndex += 1) {
    final tab = category.tabs[tabIndex];
    final matchingEntries = categoryMatches
        ? const <SettingsSearchEntry>[]
        : [
            for (final entry in tab.searchEntries)
              if (_matchesSearchEntry(entry, normalizedQuery)) entry,
          ];
    final tabMatched = categoryMatches ||
        _matches(tab.label, normalizedQuery) ||
        tab.searchKeywords.any((keyword) => _matches(keyword, normalizedQuery));

    if (tabMatched || matchingEntries.isNotEmpty) {
      matchingTabs.add(SettingsSearchTab(
        tab: tab,
        tabIndex: tabIndex,
        entries: matchingEntries,
        tabMatched: tabMatched,
      ));
    }
  }

  if (matchingTabs.isEmpty) {
    return null;
  }

  return SettingsSearchCategory(
    category: category,
    categoryIndex: categoryIndex,
    tabs: matchingTabs,
  );
}

bool _matches(String? value, String normalizedQuery) {
  if (value == null) {
    return false;
  }

  return _normalizeSearchText(value).contains(normalizedQuery);
}

bool _matchesSearchEntry(
  SettingsSearchEntry entry,
  String normalizedQuery,
) {
  return _matches(entry.title, normalizedQuery) ||
      _matches(entry.description, normalizedQuery) ||
      _matches(entry.section, normalizedQuery) ||
      entry.keywords.any((keyword) => _matches(keyword, normalizedQuery));
}

String _normalizeSearchText(String value) {
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
