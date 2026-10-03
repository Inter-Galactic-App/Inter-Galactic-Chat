import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/ui/atoms/stream_viewer_header_indicator.dart';

List<StreamViewerDisplay> viewers(int count) => [
  for (var index = 0; index < count; index++)
    StreamViewerDisplay(
      userId: '@viewer$index:example.org',
      displayName: 'Viewer $index',
      placeholderColor: Colors.teal,
    ),
];

Future<void> pumpIndicator(
  WidgetTester tester, {
  required int count,
  bool compact = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Call room'),
          actions: [
            StreamViewerHeaderContent(
              viewers: viewers(count),
              compact: compact,
            ),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('three watchers stay as avatars in a normal header', (
    tester,
  ) async {
    await pumpIndicator(tester, count: 3);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
    expect(find.text('3'), findsNothing);
    expect(find.byType(PopupMenuButton<int>), findsOneWidget);
  });

  testWidgets('overflow collapses to one button with a scrollable name list', (
    tester,
  ) async {
    await pumpIndicator(tester, count: 12);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Viewer 0'), findsOneWidget);
    await tester.ensureVisible(find.text('Viewer 11'));
    await tester.pumpAndSettle();
    expect(find.text('Viewer 11'), findsOneWidget);
  });

  testWidgets('compact header collapses after two watchers', (tester) async {
    await pumpIndicator(tester, count: 3, compact: true);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('overflow button fits a narrow mobile header', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await pumpIndicator(tester, count: 12, compact: true);
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });
}
