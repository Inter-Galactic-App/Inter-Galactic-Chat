import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/utils/system_wide_shortcuts/navigation_shortcut_room_options.dart';

void main() {
  test('joined room options use room display names as primary labels',
      () async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);

    final options = buildNavigationShortcutRoomOptions(clients: [client]);
    final lounge = options.singleWhere(
      (option) => option.targetAddress == DemoClient.demoLoungeRoomId,
    );

    expect(lounge.displayName, 'lounge');
    expect(lounge.clientId, DemoClient.demoIdentifier);
    expect(lounge.selectedLabel, contains('lounge'));
    expect(lounge.secondaryLabel, contains('@demo:intergalactic.local'));
    expect(lounge.secondaryLabel, contains(DemoClient.demoLoungeRoomId));
  });

  test('joined room options sort by user-facing room name', () async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);

    final options = buildNavigationShortcutRoomOptions(clients: [client]);
    final labels = options.map((option) => option.displayName).toList();
    final sortedLabels = List<String>.from(labels)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    expect(labels, sortedLabels);
  });

  test('joined room option matching respects account scope when present',
      () async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);

    final options = buildNavigationShortcutRoomOptions(clients: [client]);
    final matched = findNavigationShortcutRoomOptionForTarget(
      options: options,
      targetAddress: DemoClient.demoVoiceRoomId,
      clientId: DemoClient.demoIdentifier,
    );

    expect(matched, isNotNull);
    expect(matched!.displayName, 'game-night-voice');
  });
}
