import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/matrix/matrix_client.dart';
import 'package:intergalactic/client/matrix/vodozemac_single_flight.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu.dart';
import 'package:intergalactic/ui/organisms/room_quick_access_menu/room_quick_access_menu_desktop.dart';
import 'package:tiamat/config/style/theme_extensions.dart';
import 'package:tiamat/tiamat.dart' as tiamat;

/// CodeRabbit #8, second round. The first version of the encryption gate
/// renamed the Retry Decrypt entry to explain its state, and the entry-level
/// tests were green because they only ever looked at the entry.
///
/// The side panel renders its dedicated padlock as
/// `RoomQuickAccessMenuViewDesktop(onlyActionName: "Retry Decrypt")`, and that
/// view selects by EXACT name. So the rename did not disable the button, it
/// removed it - on web, during the startup window this whole change is for -
/// and took the explanatory label with it, since the label lived on the entry
/// that was filtered out. These build the real view.
void main() {
  tearDown(() {
    MatrixClient.encryptionAvailability.value = EncryptionAvailability.pending;
  });

  Future<Widget> encryptedRoomPadlock() async {
    final client = DemoClient.createOfflineDemo();
    await client.init(false);
    addTearDown(client.close);

    final room = client.getRoom(DemoClient.demoEncryptedRoomId)!;
    return RoomQuickAccessMenuViewDesktop(
      room: room,
      onlyActionName: retryDecryptActionName,
    );
  }

  for (final availability in <EncryptionAvailability>[
    EncryptionAvailability.pending,
    EncryptionAvailability.unavailable,
  ]) {
    testWidgets('the padlock is still rendered, and disabled, when encryption '
        'is ${availability.name}', (tester) async {
      MatrixClient.encryptionAvailability.value = availability;

      await tester.pumpWidget(_TestApp(child: await encryptedRoomPadlock()));
      await tester.pumpAndSettle();

      final button = tester.widget<tiamat.IconButton>(
        find.byType(tiamat.IconButton),
      );
      expect(
        button.onPressed,
        isNull,
        reason:
            'a non-null callback around a null action renders an operable '
            'button that does nothing when pressed',
      );
      expect(button.tooltip, isNot(retryDecryptActionName));

      // What a null callback then means is tiamat's own contract, read
      // rather than re-asserted here: its IconButton derives
      // `enabled` from `onPressed != null` and gates the tap, the cursor and
      // the semantics on it (`tiamat/lib/atoms/icon_button.dart`).
      expect(button.semanticLabel, contains('unavailable'));
    });
  }

  testWidgets('the padlock is operable once encryption is ready', (
    tester,
  ) async {
    MatrixClient.encryptionAvailability.value = EncryptionAvailability.ready;

    await tester.pumpWidget(_TestApp(child: await encryptedRoomPadlock()));
    await tester.pumpAndSettle();

    final button = tester.widget<tiamat.IconButton>(
      find.byType(tiamat.IconButton),
    );
    expect(button.onPressed, isNotNull);
    expect(button.tooltip, retryDecryptActionName);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.light(
        useMaterial3: true,
      ).copyWith(extensions: [const ThemeSettings()]),
      home: Scaffold(body: Center(child: child)),
    );
  }
}
