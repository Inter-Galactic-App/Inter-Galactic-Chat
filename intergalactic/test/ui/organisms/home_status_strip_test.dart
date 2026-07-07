import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/client_manager.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/client/room.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_status_strip.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_composer.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_desktop_recorder.dart';
import 'package:intergalactic/ui/organisms/home_screen/story_video_trim_exporter.dart';

void main() {
  test(
    'home status entries include self and direct-message contacts',
    () async {
      final clientManager = ClientManager();
      final client = DemoClient.createOfflineDemo();
      clientManager.addClient(client);

      final entries = buildHomeStatusEntries(clientManager: clientManager);

      expect(entries.where((entry) => entry.isSelf), hasLength(1));
      expect(
        entries.firstWhere((entry) => entry.isSelf).userId,
        client.self?.identifier,
      );
      expect(entries.where((entry) => !entry.isSelf), isNotEmpty);
      expect(
        entries.map((entry) => entry.stableKey).toSet(),
        hasLength(entries.length),
      );

      await clientManager.close();
    },
  );

  test(
    'home status entries respect the direct-message contact limit',
    () async {
      final clientManager = ClientManager();
      final client = DemoClient.createOfflineDemo();
      clientManager.addClient(client);

      final entries = buildHomeStatusEntries(
        clientManager: clientManager,
        directMessageLimit: 1,
      );

      expect(entries.where((entry) => entry.isSelf), hasLength(1));
      expect(entries.where((entry) => !entry.isSelf), hasLength(1));

      await clientManager.close();
    },
  );

  test('home status entries respect client filtering', () async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);

    final entries = buildHomeStatusEntries(
      clientManager: clientManager,
      filterClient: client,
    );

    expect(entries, isNotEmpty);
    expect(entries.every((entry) => entry.client == client), isTrue);

    await clientManager.close();
  });

  testWidgets('home status strip renders self and DM bubbles', (tester) async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);
    addTearDown(clientManager.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HomeStatusStrip(clientManager: clientManager),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Status'), findsOneWidget);
    expect(find.text('Inter Galactic Demo'), findsOneWidget);
    expect(find.text('Mira'), findsOneWidget);
  });

  testWidgets('unseen story contacts render before seen story contacts', (
    tester,
  ) async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);
    addTearDown(clientManager.close);
    final stories = client.getComponent<StoryComponent>()!;
    await stories.markStoriesSeen(
      '@mira:intergalactic.local',
      stories.activeStoriesForUser('@mira:intergalactic.local'),
    );
    (stories as DemoStoryComponent).addDemoStory(
      senderId: '@theo:intergalactic.local',
      displayName: 'Theo',
      createdAt: DateTime.now().toUtc().subtract(const Duration(hours: 3)),
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 21)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: HomeStatusStrip(clientManager: clientManager),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getTopLeft(find.text('Theo').first).dx,
      lessThan(tester.getTopLeft(find.text('Mira').first).dx),
    );
  });

  testWidgets(
    'tapping a direct-message bubble without stories opens its room',
    (tester) async {
      final clientManager = ClientManager();
      final client = DemoClient.createOfflineDemo();
      clientManager.addClient(client);
      addTearDown(clientManager.close);

      Room? openedRoom;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: HomeStatusStrip(
                clientManager: clientManager,
                onRoomClicked: (room) => openedRoom = room,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Theo'));

      expect(openedRoom?.displayName, 'Theo');
    },
  );

  testWidgets('tapping a story bubble opens the story viewer', (tester) async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);
    addTearDown(clientManager.close);

    Room? openedRoom;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HomeStatusStrip(
              clientManager: clientManager,
              onRoomClicked: (room) => openedRoom = room,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Mira').first);
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(openedRoom, isNull);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('long-pressing a story bubble opens the DM', (tester) async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);
    addTearDown(clientManager.close);

    Room? openedRoom;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HomeStatusStrip(
              clientManager: clientManager,
              onRoomClicked: (room) => openedRoom = room,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.longPress(find.text('Mira').first);
    await tester.pump();

    expect(openedRoom?.displayName, 'Mira');
  });

  testWidgets('tapping the self bubble opens the story composer', (
    tester,
  ) async {
    final clientManager = ClientManager();
    final client = DemoClient.createOfflineDemo();
    clientManager.addClient(client);
    addTearDown(clientManager.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HomeStatusStrip(
              clientManager: clientManager,
              storyComposerOpener: (context, client) => HomeStoryComposer.show(
                context,
                client: client,
                mediaServices: const HomeStoryComposerMediaServices(
                  desktopVideoRecorder: _FakeDesktopVideoRecorder(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Inter Galactic Demo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Your Story'), findsOneWidget);
  });
}

class _FakeDesktopVideoRecorder implements StoryDesktopVideoRecorder {
  const _FakeDesktopVideoRecorder();

  StoryVideoFfmpegTools get tools => const StoryVideoFfmpegTools();

  @override
  Future<List<StoryDesktopVideoInputDevice>> listVideoInputDevices() async {
    return const [];
  }

  @override
  Future<StoryDesktopVideoRecordStartResult> start({
    required String deviceLabel,
    String? sourceName,
  }) async {
    return StoryDesktopVideoRecordStartResult.unsupported('fake recorder');
  }
}
