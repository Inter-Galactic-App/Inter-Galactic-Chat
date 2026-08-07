import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:intergalactic/ui/organisms/call_view/screen_capture_source_widget.dart';
import 'package:tiamat/config/style/theme_dark_matter.dart';

void main() {
  testWidgets(
    'reused source tile ignores late thumbnail events from previous source',
    (tester) async {
      final globalThumbnailUpdates =
          StreamController<DesktopCapturerSource>.broadcast(sync: true);
      final sourceA = _FakeDesktopCapturerSource(
        id: 'source-a',
        name: 'Source A',
        type: SourceType.Window,
        thumbnail: _pngA,
      );
      final sourceB = _FakeDesktopCapturerSource(
        id: 'source-b',
        name: 'Source B',
        type: SourceType.Screen,
        thumbnail: _pngB,
      );

      await tester.pumpWidget(
        _buildHost(sourceA, globalThumbnailUpdates.stream),
      );
      expect(_visibleImageBytes(tester), orderedEquals(_pngA));

      await tester.pumpWidget(
        _buildHost(sourceB, globalThumbnailUpdates.stream),
      );
      expect(_visibleImageBytes(tester), orderedEquals(_pngB));

      sourceA.emitThumbnail(_pngOldA);
      await tester.pump();

      expect(_visibleImageBytes(tester), orderedEquals(_pngB));

      await globalThumbnailUpdates.close();
    },
  );

  testWidgets('same source id replacement reads inline thumbnail', (
    tester,
  ) async {
    final globalThumbnailUpdates =
        StreamController<DesktopCapturerSource>.broadcast(sync: true);
    final initialSource = _FakeDesktopCapturerSource(
      id: 'source-a',
      name: 'Source A',
      type: SourceType.Window,
      thumbnail: _pngA,
    );
    final refreshedSource = _FakeDesktopCapturerSource(
      id: 'source-a',
      name: 'Source A',
      type: SourceType.Window,
      thumbnail: _pngB,
    );

    await tester.pumpWidget(
      _buildHost(initialSource, globalThumbnailUpdates.stream),
    );
    expect(_visibleImageBytes(tester), orderedEquals(_pngA));

    await tester.pumpWidget(
      _buildHost(refreshedSource, globalThumbnailUpdates.stream),
    );
    expect(_visibleImageBytes(tester), orderedEquals(_pngB));

    await globalThumbnailUpdates.close();
  });
}

Widget _buildHost(
  DesktopCapturerSource source,
  Stream<DesktopCapturerSource> thumbnailUpdates,
) {
  return MaterialApp(
    theme: ThemeDarkMatter.theme,
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 220,
          child: ScreenCaptureSourceWidget(
            source,
            thumbnailUpdates,
            key: const ValueKey('reused-source-tile'),
            refreshThumbnailEvents: (_) async {},
          ),
        ),
      ),
    ),
  );
}

Uint8List _visibleImageBytes(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as MemoryImage).bytes;
}

final _pngA = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8z8BQDwAFgwJ/l6YdNwAAAABJRU5ErkJggg==',
);
final _pngB = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
final _pngOldA = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg==',
);

class _FakeDesktopCapturerSource implements DesktopCapturerSource {
  _FakeDesktopCapturerSource({
    required this.id,
    required this.name,
    required this.type,
    Uint8List? thumbnail,
  }) : _thumbnail = thumbnail;

  @override
  final String id;

  @override
  final String name;

  @override
  final SourceType type;

  Uint8List? _thumbnail;

  @override
  Uint8List? get thumbnail => _thumbnail;

  @override
  ThumbnailSize get thumbnailSize => ThumbnailSize(320, 180);

  @override
  final StreamController<String> onNameChanged =
      StreamController<String>.broadcast(sync: true);

  @override
  final StreamController<Uint8List> onThumbnailChanged =
      StreamController<Uint8List>.broadcast(sync: true);

  void emitThumbnail(Uint8List thumbnail) {
    _thumbnail = thumbnail;
    onThumbnailChanged.add(thumbnail);
  }
}
