import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/app_globals.dart' as globals;
import 'package:intergalactic/ui/onboarding/demo_tutorial_content.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/help_tutorial_page.dart';
import 'package:intergalactic/ui/pages/settings/categories/help/settings_category_help.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  test('Help category includes Tutorial tab', () {
    final tabs = SettingsCategoryHelp().tabs;

    expect(tabs.any((tab) => tab.label == 'Tutorial'), isTrue);
  });

  test('Help category hides Tutorial tab on mobile layout', () async {
    await globals.preferences.layoutOverride.set('mobile');
    final tabs = SettingsCategoryHelp().tabs;

    expect(tabs.any((tab) => tab.label == 'Tutorial'), isFalse);
  });

  testWidgets('Mobile tutorial page shows desktop-only restriction',
      (tester) async {
    await globals.preferences.layoutOverride.set('mobile');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true).copyWith(
          extensions: [
            const ThemeSettings(),
          ],
        ),
        home: const Scaffold(
          body: HelpTutorialPage(),
        ),
      ),
    );

    expect(find.text('Tutorial'), findsOneWidget);
    expect(
      find.text(
        'The guided tutorial is desktop-only for now. Mobile builds hide replay until the mobile tutorial path is ready.',
      ),
      findsOneWidget,
    );
    expect(find.text('Replay tutorial'), findsNothing);
  });

  testWidgets('Replay tutorial button opens onboarding', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true).copyWith(
          extensions: [
            const ThemeSettings(),
          ],
        ),
        home: const Scaffold(
          body: HelpTutorialPage(),
        ),
      ),
    );

    await tester.tap(find.text('Replay tutorial'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
    expect(find.text('1 of ${demoTutorialSteps.length}'), findsOneWidget);
  });

  testWidgets('Developer placeholder button opens legacy onboarding',
      (tester) async {
    await globals.preferences.developerMode.set(true);

    tester.view
      ..physicalSize = const Size(1600, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(useMaterial3: true).copyWith(
          extensions: [
            const ThemeSettings(),
          ],
        ),
        home: const Scaffold(
          body: HelpTutorialPage(),
        ),
      ),
    );

    expect(find.text('Open placeholder tutorial'), findsOneWidget);

    await tester.tap(find.text('Open placeholder tutorial'));
    await _pumpTutorialAnimation(tester);

    expect(find.text('Welcome to Inter Galactic'), findsWidgets);
    expect(find.text('1 of 10'), findsOneWidget);
  });
}

Future<void> _pumpTutorialAnimation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump();
}
