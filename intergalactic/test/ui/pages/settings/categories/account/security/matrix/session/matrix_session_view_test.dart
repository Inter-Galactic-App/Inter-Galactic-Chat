import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/account/security/matrix/session/matrix_session_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('session removal waits for dangerous confirmation', (
    tester,
  ) async {
    var removals = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: MatrixSessionView(
            deviceId: 'OTHER-DEVICE',
            displayName: 'Desktop',
            removeSession: () {
              removals += 1;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete));
    await tester.pumpAndSettle();

    expect(removals, 0);
    expect(find.text('Remove session?'), findsOneWidget);

    await tester.tap(find.text('Remove session'));
    await tester.pumpAndSettle();

    expect(removals, 1);
  });
}
