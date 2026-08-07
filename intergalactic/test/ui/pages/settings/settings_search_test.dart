import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/settings_category.dart';
import 'package:intergalactic/ui/pages/settings/settings_search.dart';
import 'package:intergalactic/ui/pages/settings/settings_search_anchor.dart';
import 'package:intergalactic/ui/pages/settings/settings_tab.dart';

void main() {
  test('empty query returns all categories and tabs', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab('General'),
          _tab('Appearance'),
        ],
      ),
      _FakeSettingsCategory(
        title: 'Account',
        tabs: [
          _tab('Security'),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, '');

    expect(results, hasLength(2));
    expect(results.first.tabs.map((match) => match.tab.label), [
      'General',
      'Appearance',
    ]);
    expect(results.last.tabs.single.tab.label, 'Security');
  });

  test('tab label search returns matching tab only', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab('General'),
          _tab('Notifications'),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, 'noti');

    expect(results, hasLength(1));
    expect(results.single.tabs, hasLength(1));
    expect(results.single.tabs.single.tab.label, 'Notifications');
  });

  test('category title search returns all tabs in that category', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab('General'),
          _tab('Appearance'),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, 'app');

    expect(results.single.tabs.map((match) => match.tab.label), [
      'General',
      'Appearance',
    ]);
  });

  test('keyword search finds related tab labels', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab('Appearance', keywords: const ['themes', 'backgrounds']),
          _tab('Voice and Video', keywords: const ['screen share']),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, 'screen');

    expect(results, hasLength(1));
    expect(results.single.tabs.single.tab.label, 'Voice and Video');
  });

  test('row entry search returns matching setting rows', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab(
            'General',
            entries: const [
              SettingsSearchEntry(
                title: 'Read receipts',
                section: 'App Behaviour',
                keywords: ['privacy', 'seen'],
              ),
              SettingsSearchEntry(
                title: 'Minimize on close',
                section: 'Window Behaviour',
                keywords: ['window behavior'],
              ),
            ],
          ),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, 'privacy');

    expect(results, hasLength(1));
    expect(results.single.tabs.single.tab.label, 'General');
    expect(results.single.tabs.single.entries, hasLength(1));
    expect(results.single.tabs.single.entries.single.title, 'Read receipts');
  });

  test('row entries expose stable highlight anchors', () {
    const defaultEntry = SettingsSearchEntry(
      title: 'URL Preview in Encrypted Chats',
    );
    const explicitEntry = SettingsSearchEntry(
      title: 'Selected account',
      anchorId: 'settings-account-header',
    );

    expect(
      defaultEntry.effectiveAnchorId,
      'setting-row-url-preview-in-encrypted-chats',
    );
    expect(explicitEntry.effectiveAnchorId, 'settings-account-header');
  });

  test('tab keyword match is preserved when no row entry matches', () {
    final categories = [
      _FakeSettingsCategory(
        title: 'App Settings',
        tabs: [
          _tab('Developer', keywords: const ['advanced']),
        ],
      ),
    ];

    final results = filterSettingsCategories(categories, 'advanced');

    expect(results.single.tabs.single.tab.label, 'Developer');
    expect(results.single.tabs.single.entries, isEmpty);
    expect(results.single.tabs.single.tabMatched, isTrue);
  });

  testWidgets('highlight target scrolls the matching setting row into view',
      (tester) async {
    final controller = SettingsSearchHighlightController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 220,
            child: SettingsSearchHighlightScope(
              controller: controller,
              child: SingleChildScrollView(
                child: Column(
                  children: const [
                    SizedBox(height: 500),
                    SettingsControlRow(title: 'Read receipts'),
                    SizedBox(height: 200),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.text('Read receipts')).dy, greaterThan(220));

    controller.highlight(SettingsSearchEntry.anchorIdFor('Read receipts'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.getTopLeft(find.text('Read receipts')).dy, lessThan(220));

    final highlightContainer =
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer).first);
    final decoration = highlightContainer.decoration! as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));

    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
  });
}

SettingsTab _tab(
  String label, {
  List<String> keywords = const [],
  List<SettingsSearchEntry> entries = const [],
}) {
  return SettingsTab(
    label: label,
    searchKeywords: keywords,
    searchEntries: entries,
    pageBuilder: (_) => const SizedBox.shrink(),
  );
}

class _FakeSettingsCategory implements SettingsCategory {
  _FakeSettingsCategory({
    required this.title,
    required this.tabs,
  });

  @override
  final String? title;

  @override
  final List<SettingsTab> tabs;
}
