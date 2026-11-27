import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/pages/settings/settings_status_components.dart';

void main() {
  testWidgets(
    'SettingsActionChoiceCard keeps compact actions below explanatory copy',
    (tester) async {
      var tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 320,
                child: SettingsActionChoiceCard(
                  icon: Icons.key_outlined,
                  title: 'Repair key delivery',
                  description: 'Refresh key delivery for missing room keys.',
                  detail:
                      'This cannot unlock backed-up history without your recovery key.',
                  tone: SettingsStatusTone.warning,
                  action: ElevatedButton(
                    onPressed: () => tapped = true,
                    child: const Text('Repair delivery'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Repair key delivery'), findsOneWidget);
      expect(
        find.text('Refresh key delivery for missing room keys.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'This cannot unlock backed-up history without your recovery key.',
        ),
        findsOneWidget,
      );

      final detailBottom = tester
          .getBottomLeft(
            find.text(
              'This cannot unlock backed-up history without your recovery key.',
            ),
          )
          .dy;
      final actionTop = tester
          .getTopLeft(find.widgetWithText(ElevatedButton, 'Repair delivery'))
          .dy;

      expect(actionTop, greaterThan(detailBottom));

      await tester.tap(find.text('Repair delivery'));
      expect(tapped, isTrue);
    },
  );
}
