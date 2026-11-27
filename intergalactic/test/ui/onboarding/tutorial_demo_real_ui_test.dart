import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/emoticon/emoticon_component.dart';
import 'package:intergalactic/client/components/emoticon_recent/recent_emoticon_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:intergalactic/ui/pages/settings/categories/account/security/security_tab.dart';
import 'package:intergalactic/ui/pages/settings/categories/app/emoticons_settings_page.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

void main() {
  testWidgets('demo Emoticons settings renders real Available Packs',
      (tester) async {
    final setup = await _createDemoManager();
    addTearDown(setup.close);

    await tester.pumpWidget(
      _TestApp(
        child: EmoticonsSettingsPage(clientManager: setup.manager),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Available Packs'), findsOneWidget);
    expect(find.text('Galaxy Emoji'), findsWidgets);
    expect(find.text('Demo Space Pack'), findsWidgets);
    expect(find.byType(Placeholder), findsNothing);
  });

  testWidgets('demo Security settings renders controls instead of Placeholder',
      (tester) async {
    final setup = await _createDemoManager();
    addTearDown(setup.close);

    await tester.pumpWidget(
      _TestApp(
        child: SecuritySettingsTab(clientManager: setup.manager),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Placeholder), findsNothing);
    expect(find.text('Verify this device'), findsOneWidget);
    expect(find.text('Encrypted message tools'), findsOneWidget);
    expect(find.text('Sessions'), findsWidgets);
  });

  test('demo client exposes account emoticons and quick reactions', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final emoticons = client.getComponent<EmoticonComponent>()!;
    final recent = client.getComponent<RecentEmoticonComponent>()!;

    expect(emoticons.ownedPacks, isNotEmpty);
    expect(emoticons.availablePacks.map((pack) => pack.displayName),
        contains('Demo Space Pack'));
    expect(
      recent.getQuickReactionEmoticon(null),
      hasLength(RecentEmoticonComponent.quickReactionCount),
    );
  });

  test('encrypted demo room exposes retry decrypt quick action', () async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final room = client.getRoom(DemoClient.demoEncryptedRoomId)!;
    final menu = RoomQuickAccessMenu(room: room);

    expect(
      menu.actions.map((entry) => entry.name),
      contains('Retry Decrypt'),
    );
  });
}

Future<_DemoManagerSetup> _createDemoManager() async {
  final manager = ClientManager();
  final client = DemoClient.createOfflineDemo();
  await client.init(false);
  manager.addClient(client);
  return _DemoManagerSetup(manager);
}

class _DemoManagerSetup {
  const _DemoManagerSetup(this.manager);

  final ClientManager manager;

  Future<void> close() async {
    await manager.close();
  }
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(useMaterial3: true).copyWith(
        extensions: [
          const ThemeSettings(),
        ],
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: child,
        ),
      ),
    );
  }
}
