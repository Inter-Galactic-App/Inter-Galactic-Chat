import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/categories/category_settings_header.dart';

void main() {
  testWidgets('compact category header preserves readable name and actions', (
    tester,
  ) async {
    const categoryName =
        'A very long category name that should remain horizontally readable';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 292,
              child: CategorySettingsHeader(
                name: categoryName,
                roomCountLabel: '12 rooms',
                collapsed: false,
                actions: [
                  for (var index = 0; index < 5; index++)
                    IconButton(
                      tooltip: 'Action $index',
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(categoryName), findsOneWidget);
    expect(find.text('12 rooms'), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(5));

    final categoryText = tester.widget<Text>(find.text(categoryName));
    expect(categoryText.maxLines, 2);
    expect(categoryText.overflow, TextOverflow.ellipsis);

    // The compact branch is the one that wraps. Asserted here so the wide-layout
    // test below is a real discriminator rather than two tests that would pass
    // against a header with no responsive branch at all.
    expect(find.byType(Wrap), findsOneWidget);
  });

  testWidgets('wide category header lays out without wrapping', (tester) async {
    // The responsive header has two branches and only the compact one at 292px
    // was covered, so the wide branch could have regressed - or been deleted -
    // with the suite still green.
    const categoryName = 'General';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              child: CategorySettingsHeader(
                name: categoryName,
                roomCountLabel: '12 rooms',
                collapsed: false,
                actions: [
                  for (var index = 0; index < 5; index++)
                    IconButton(
                      tooltip: 'Action $index',
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(Wrap), findsNothing);
    expect(find.text(categoryName), findsOneWidget);
    expect(find.text('12 rooms'), findsOneWidget);
    expect(find.byType(IconButton), findsNWidgets(5));
  });
}
