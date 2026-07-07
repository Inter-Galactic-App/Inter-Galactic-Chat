import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/atoms/text.dart' as tiamat;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('publishes resolved bold text override through MediaQuery',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.bold_text': 'on',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      material.MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: material.Builder(
            builder: (context) {
              return material.Text(
                'bold ${material.MediaQuery.boldTextOf(context)}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('bold true'), findsOneWidget);
  });

  testWidgets('manual bold text off overrides platform bold text',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.bold_text': 'off',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      material.MaterialApp(
        home: material.MediaQuery(
          data: const material.MediaQueryData(boldText: true),
          child: AccessibilityScope(
            preferences: preferences,
            child: material.Builder(
              builder: (context) {
                return material.Text(
                  'bold ${material.MediaQuery.boldTextOf(context)}',
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('bold false'), findsOneWidget);
  });

  testWidgets('reacts to preference updates after the initial pump',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.bold_text': 'off',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      material.MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: material.Builder(
            builder: (context) {
              return material.Text(
                'bold ${material.MediaQuery.boldTextOf(context)}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('bold false'), findsOneWidget);

    await preferences.accessibilityBoldText.set('on');
    await tester.pump();

    expect(find.text('bold true'), findsOneWidget);
  });

  testWidgets('does not rebuild when preference update resolves unchanged',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.bold_text': 'system',
    });
    final preferences = Preferences();
    await preferences.init();
    var buildCount = 0;

    await tester.pumpWidget(
      material.MaterialApp(
        home: material.MediaQuery(
          data: const material.MediaQueryData(boldText: true),
          child: AccessibilityScope(
            preferences: preferences,
            child: material.Builder(
              builder: (context) {
                buildCount++;
                return material.Text(
                  'bold ${material.MediaQuery.boldTextOf(context)}',
                );
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('bold true'), findsOneWidget);
    final initialBuildCount = buildCount;

    await preferences.accessibilityBoldText.set('on');
    await tester.pump();

    expect(find.text('bold true'), findsOneWidget);
    expect(buildCount, initialBuildCount);
  });

  testWidgets('publishes resolved high contrast and animation state',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.contrast': 'high',
      'accessibility.motion': 'none',
    });
    final preferences = Preferences();
    await preferences.init();

    await tester.pumpWidget(
      material.MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: material.Builder(
            builder: (context) {
              return material.Text(
                'contrast ${material.MediaQuery.highContrastOf(context)} '
                'animations ${material.MediaQuery.disableAnimationsOf(context)}',
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('contrast true animations true'), findsOneWidget);
  });

  testWidgets('Tiamat text uses heavier weights when bold text is active',
      (tester) async {
    await tester.pumpWidget(
      const material.MaterialApp(
        home: tiamat.Text.body('Readable'),
      ),
    );

    material.Text renderedText = tester.widget(find.text('Readable'));
    expect(renderedText.style?.fontWeight, material.FontWeight.w300);

    await tester.pumpWidget(
      const material.MaterialApp(
        home: material.MediaQuery(
          data: material.MediaQueryData(boldText: true),
          child: tiamat.Text.body('Readable'),
        ),
      ),
    );

    renderedText = tester.widget(find.text('Readable'));
    expect(renderedText.style?.fontWeight, material.FontWeight.w600);
  });
}
