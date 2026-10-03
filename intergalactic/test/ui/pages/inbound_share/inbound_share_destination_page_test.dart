import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client.dart';
import 'package:intergalactic/client/components/component.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_model.dart';
import 'package:intergalactic/ui/pages/inbound_share/inbound_share_destination_page.dart';

void main() {
  testWidgets('empty destination state can refresh or cancel without sending', (
    tester,
  ) async {
    var refreshCount = 0;
    var cancelCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InboundShareDestinationPage(
          destinations: const [],
          onSelected: (_) => true,
          onCancelled: () => cancelCount++,
          refreshDestinations: () {
            refreshCount++;
            return const [];
          },
        ),
      ),
    );

    expect(find.text('No writable conversations found.'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(refreshCount, 1);

    await tester.tap(find.byTooltip('Cancel share'));
    expect(cancelCount, 1);
  });

  testWidgets('stale selection keeps query and share pending for refresh', (
    tester,
  ) async {
    final stale = InboundShareDestination(
      room: _FakeRoom('Old room', 1),
      accountLabel: 'Personal',
    );
    final replacement = InboundShareDestination(
      room: _FakeRoom('New room', 2),
      accountLabel: 'Personal',
    );
    var selections = 0;
    var refreshes = 0;
    var cancellations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InboundShareDestinationPage(
          destinations: [stale],
          onSelected: (destination) {
            selections++;
            return destination == replacement;
          },
          onCancelled: () => cancellations++,
          refreshDestinations: () {
            refreshes++;
            return [replacement];
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'room');
    await tester.tap(find.text('Old room'));
    await tester.pump();

    expect(selections, 1);
    expect(find.text('Conversation unavailable'), findsOneWidget);
    expect(find.textContaining('Nothing was sent.'), findsOneWidget);
    expect(find.text('Old room'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<EditableText>(find.byType(EditableText)).controller.text,
      'room',
    );

    await tester.tap(find.text('Refresh'));
    await tester.pump();
    expect(refreshes, 1);
    expect(find.text('New room'), findsOneWidget);
    expect(find.text('Conversation unavailable'), findsNothing);

    await tester.tap(find.text('New room'));
    expect(selections, 2);
    expect(cancellations, 0);
  });

  testWidgets('stale selection can be cancelled without accepting it', (
    tester,
  ) async {
    final stale = InboundShareDestination(
      room: _FakeRoom('Old room', 1),
      accountLabel: 'Personal',
    );
    var selectionAttempts = 0;
    var cancellations = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: InboundShareDestinationPage(
          destinations: [stale],
          onSelected: (_) {
            selectionAttempts++;
            return false;
          },
          onCancelled: () => cancellations++,
        ),
      ),
    );

    await tester.tap(find.text('Old room'));
    await tester.pump();
    await tester.tap(find.byTooltip('Cancel share'));

    expect(selectionAttempts, 1);
    expect(cancellations, 1);
    expect(find.text('Conversation unavailable'), findsOneWidget);
  });
}

class _FakeRoom implements Room {
  _FakeRoom(this.displayName, this.index);

  final int index;

  @override
  final String displayName;

  @override
  String get identifier => '!room-$index:example.org';

  @override
  final Client client = _FakeClient();

  @override
  ImageProvider? get avatar => null;

  @override
  Color get defaultColor => Colors.blue;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClient implements Client {
  @override
  T? getComponent<T extends Component>() => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
