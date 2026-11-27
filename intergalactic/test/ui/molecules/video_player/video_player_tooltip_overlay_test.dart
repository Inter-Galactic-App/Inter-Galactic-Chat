import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/cache/file_provider.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player.dart';
import 'package:intergalactic/ui/molecules/video_player/video_player_controller.dart';

class _TestVideoFileProvider implements FileProvider {
  @override
  String get fileIdentifier => 'inline-video-tooltip-regression';

  @override
  Future<Uint8List?> getFileData() async => null;

  @override
  Stream<DownloadProgress>? get onProgressChanged => null;

  @override
  Future<Uri?> resolve() async => null;

  @override
  Future<void> save(String filepath) async {}
}

void main() {
  testWidgets(
    'inline video controls stay accessible without hover tooltip portals',
    (tester) async {
      final controller = VideoPlayerController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              height: 180,
              child: VideoPlayer(
                _TestVideoFileProvider(),
                controller: controller,
                showProgressBar: false,
                canGoFullscreen: true,
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Enter fullscreen video'), findsOneWidget);
      expect(find.bySemanticsLabel('Play video'), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    },
  );
}
