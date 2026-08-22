import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/atoms/rich_text/spans/link.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('LinkSpan underlines links when accessibility setting is on',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.underline_links': 'on',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: Builder(
            builder: (context) => Text.rich(
              LinkSpan.create(
                'Open link',
                context: context,
                clientId: 'test',
              ),
              key: const Key('link-text'),
            ),
          ),
        ),
      ),
    );

    final linkText = tester.widget<Text>(find.byKey(const Key('link-text')));
    final span = linkText.textSpan! as TextSpan;

    expect(span.style?.decoration, TextDecoration.underline);
    expect(span.style?.decorationColor, span.style?.color);
  });

  testWidgets('LinkSpan leaves links color-only when setting is off',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.underline_links': 'off',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: Builder(
            builder: (context) => Text.rich(
              LinkSpan.create(
                'Open link',
                context: context,
                clientId: 'test',
              ),
              key: const Key('link-text'),
            ),
          ),
        ),
      ),
    );

    final linkText = tester.widget<Text>(find.byKey(const Key('link-text')));
    final span = linkText.textSpan! as TextSpan;

    expect(span.style?.decoration, isNull);
    expect(span.style?.color, isNotNull);
  });
}
