import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/config/preferences.dart';
import 'package:intergalactic/ui/accessibility/accessibility_scope.dart';
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses the normal Image widget when animated media is not paused',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.pause_animated_media': 'off',
    });
    final preferences = Preferences();
    await preferences.init();
    final provider = _ManualImageProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: PausedAnimatedImage(
            image: provider,
            width: 10,
            height: 10,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
      'freezes on the first emitted frame when animated media is paused',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'accessibility.pause_animated_media': 'on',
    });
    final preferences = Preferences();
    await preferences.init();
    final provider = _ManualImageProvider();

    await tester.pumpWidget(
      MaterialApp(
        home: AccessibilityScope(
          preferences: preferences,
          child: PausedAnimatedImage(
            image: provider,
            width: 10,
            height: 10,
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byType(RawImage), findsNothing);

    final firstFrame = await _createTestImage(Colors.red);
    provider.emit(firstFrame);
    await tester.pump();

    final renderedFirstFrame = tester.widget<RawImage>(
      find.byType(RawImage),
    );
    final renderedImage = renderedFirstFrame.image;
    expect(renderedImage, isNotNull);

    final secondFrame = await _createTestImage(Colors.blue);
    provider.emit(secondFrame);
    await tester.pump();

    final renderedAfterSecondFrame = tester.widget<RawImage>(
      find.byType(RawImage),
    );
    expect(renderedAfterSecondFrame.image, same(renderedImage));
  });
}

Future<ui.Image> _createTestImage(Color color) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 2, 2),
    Paint()..color = color,
  );
  return recorder.endRecording().toImage(2, 2);
}

class _ManualImageProvider extends ImageProvider<_ManualImageProvider> {
  _ManualImageProvider();

  final _ManualImageStreamCompleter completer = _ManualImageStreamCompleter();

  @override
  Future<_ManualImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_ManualImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _ManualImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return completer;
  }

  void emit(ui.Image image) {
    completer.emit(
      ImageInfo(image: image.clone()),
    );
  }
}

class _ManualImageStreamCompleter extends ImageStreamCompleter {
  void emit(ImageInfo imageInfo) {
    setImage(imageInfo);
  }
}
