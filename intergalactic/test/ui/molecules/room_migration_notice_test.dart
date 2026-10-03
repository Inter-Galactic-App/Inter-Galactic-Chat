import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/molecules/room_migration_notice.dart';

void main() {
  test('shows the notice only for developer-mode successor rooms', () {
    expect(
      shouldShowRoomMigrationNotice(
        developerMode: false,
        predecessorRoomId: '!older:example.org',
      ),
      isFalse,
    );
    expect(
      shouldShowRoomMigrationNotice(
        developerMode: true,
        predecessorRoomId: null,
      ),
      isFalse,
    );
    expect(
      shouldShowRoomMigrationNotice(
        developerMode: true,
        predecessorRoomId: '!older:example.org',
      ),
      isTrue,
    );
  });

  testWidgets('opens the predecessor history link', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              RoomMigrationNotice(onOpenHistory: () => opened = true),
              const Expanded(child: SizedBox()),
            ],
          ),
        ),
      ),
    );

    expect(
      find.text('This room is a continuation of another conversation.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Click here to see older messages.'));
    expect(opened, isTrue);
  });
}
