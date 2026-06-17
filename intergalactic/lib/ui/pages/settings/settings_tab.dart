import 'package:flutter/material.dart';

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    this.description,
    this.section,
    this.keywords = const [],
  });

  final String title;
  final String? description;
  final String? section;
  final List<String> keywords;
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
