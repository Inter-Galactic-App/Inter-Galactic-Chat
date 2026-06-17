import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/client/components/stories/story_component.dart';
import 'package:intergalactic/client/demo/demo_client.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';
import 'package:intergalactic/ui/organisms/home_screen/home_story_viewer.dart';

void main() {
  test('video stories with media wait for player readiness', () {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);

    final now = DateTime.now().toUtc();
    final imageStory = StoryItem(
      client: client,
      storyId: 'image-story',
      senderId: '@mira:intergalactic.local',
      createdAt: now,
      expiresAt: now.add(storyLifetime),
      mediaUri: Uri.parse('mxc://demo.local/image-story'),
      encrypted: false,
      isOwn: false,
      rawContent: const {},
    );
    final brokenVideoStory = StoryItem(
      client: client,
      storyId: 'broken-video-story',
      senderId: '@mira:intergalactic.local',
      createdAt: now,
      expiresAt: now.add(storyLifetime),
      mediaUri: Uri.parse('mxc://demo.local/broken-video-story'),
      mediaType: StoryMediaType.video,
      encrypted: false,
      isOwn: false,
      durationMs: 5000,
      rawContent: const {},
    );
    final videoStory = StoryItem(
      client: client,
      storyId: 'video-story',
      senderId: '@mira:intergalactic.local',
      createdAt: now,
      expiresAt: now.add(storyLifetime),
      mediaUri: Uri.parse('mxc://demo.local/video-story'),
      mediaType: StoryMediaType.video,
      encrypted: false,
      isOwn: false,
      durationMs: 5000,
      rawContent: const {},
      video: _FakeStoryVideoFileProvider(),
    );

    expect(homeStoryViewerRequiresVideoReadySignal(imageStory), isFalse);
    expect(homeStoryViewerRequiresVideoReadySignal(brokenVideoStory), isFalse);
    expect(homeStoryViewerRequiresVideoReadySignal(videoStory), isTrue);
  });

  test('video player controller emits ready when media is renderable',
      () async {
    final controller = VideoPlayerController();
    final ready = expectLater(controller.ready, emits(isNull));

    controller.setReady();

    await ready;
  });

  test('video player controller emits errors when media fails to load',
      () async {
    final controller = VideoPlayerController();
    final error = expectLater(controller.errors, emits(anything));

    controller.setError(StateError('video failed'));

    await error;
  });

  testWidgets('story viewer shows mention pills with overflow details',
      (tester) async {
    final client = DemoClient.createOfflineDemo();
    addTearDown(client.close);

    final now = DateTime.now().toUtc();
    final story = StoryItem(
      client: client,
      storyId: 'story-with-mentions',
      senderId: '@mira:intergalactic.local',
      createdAt: now,
      expiresAt: now.add(storyLifetime),
      mediaUri: Uri.parse('mxc://demo.local/story-with-mentions'),
      encrypted: false,
      isOwn: false,
      roomId: DemoClient.demoMiraDmRoomId,
      rawContent: const {},
      mentionedUserIds: const [
        '@theo:intergalactic.local',
        '@nova:intergalactic.local',
        '@iris:intergalactic.local',
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  HomeStoryViewer.show(
                    context,
                    client: client,
                    userId: story.senderId,
                    stories: [story],
                    displayName: 'Mira',
                    avatarColor: Colors.orange,
                  );
                },
                child: const Text('Open story'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open story'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 180));

    expect(find.text('@Theo'), findsOneWidget);
    expect(find.text('@Nova'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('@Iris'), findsNothing);

    await tester.tap(find.text('+1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(find.text('Mentioned people'), findsOneWidget);
    expect(find.text('Theo'), findsOneWidget);
    expect(find.text('Nova'), findsOneWidget);
    expect(find.text('Iris'), findsOneWidget);
    expect(find.text('@theo:intergalactic.local'), findsOneWidget);
    expect(find.text('@nova:intergalactic.local'), findsOneWidget);
    expect(find.text('@iris:intergalactic.local'), findsOneWidget);
  });
}

class _FakeStoryVideoFileProvider implements FileProvider {
  @override
  String get fileIdentifier => 'fake-story-video';

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uri?> resolve() async =>
      Uri.parse('https://media.example.test/fake-story-video.mp4');

  @override
  Future<void> save(String filepath) async {}

  @override
  Future<Uint8List?> getFileData() async => Uint8List(0);
}
