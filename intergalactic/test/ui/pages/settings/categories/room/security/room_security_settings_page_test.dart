import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/permissions.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/pages/settings/categories/app/setting_row.dart';
import 'package:intergalactic/ui/pages/settings/categories/room/security/room_security_settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
    await globals.preferences.layoutOverride.set('desktop');
  });

  testWidgets('encryption enable waits for dangerous confirmation', (
    tester,
  ) async {
    final room = _FakeRoom();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(body: RoomSecuritySettingsPage(room: room)),
      ),
    );

    final encryptionControl = tester.widget<SettingsControlRow>(
      find.byType(SettingsControlRow).first,
    );
    encryptionControl.onActivate!.call();
    await tester.pumpAndSettle();

    expect(room.enableEncryptionCalls, 0);
    expect(find.text('Enable encryption?'), findsOneWidget);

    await tester.tap(find.text('Enable encryption'));
    await tester.pumpAndSettle();

    expect(room.enableEncryptionCalls, 1);
  });
}

class _FakeRoom extends Room {
  final _FakeClient _client = _FakeClient();
  final _FakePermissions _permissions = _FakePermissions();
  var enableEncryptionCalls = 0;

  @override
  Client get client => _client;

  @override
  Permissions get permissions => _permissions;

  @override
  bool get isE2EE => false;

  @override
  RoomVisibility get visibility => RoomVisibilityPrivate();

  @override
  Future<void> enableE2EE() async {
    enableEncryptionCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePermissions extends Permissions {
  @override
  bool get canEnableE2EE => true;
}

class _FakeClient implements Client {
  @override
  String get identifier => 'test-client';

  @override
  bool get supportsE2EE => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
