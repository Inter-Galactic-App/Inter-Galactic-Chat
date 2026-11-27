import 'package:flutter/material.dart';

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    this.description,
    this.section,
    this.anchorId,
    this.keywords = const [],
  });

  final String title;
  final String? description;
  final String? section;
  final String? anchorId;
  final List<String> keywords;

  String get effectiveAnchorId => anchorId ?? anchorIdFor(title);

  static String anchorIdFor(String title) {
    final normalized = title
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (normalized.isNotEmpty) {
      return 'setting-row-$normalized';
    }

    final fallback = title.runes
        .map((value) => value.toRadixString(16))
        .where((value) => value.isNotEmpty)
        .join('-');
    return 'setting-row-${fallback.isEmpty ? 'entry' : fallback}';
  }
}

class SettingsTab {
  final String? id;
  final String label;
  final Widget Function(BuildContext context) pageBuilder;
  final IconData? icon;
  final bool makeScrollable;
  final List<String> searchKeywords;
  final List<SettingsSearchEntry> searchEntries;

  SettingsTab({
    this.id,
    required this.label,
    required this.pageBuilder,
    this.icon,
    this.makeScrollable = true,
    this.searchKeywords = const [],
    this.searchEntries = const [],
  });
}
