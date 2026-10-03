import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/main.dart' as globals;
import 'package:intergalactic/ui/accessibility/paused_animated_image.dart';
import 'package:intergalactic/ui/molecules/url_preview_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tiamat/config/style/theme_extensions.dart';

/// Owner report, 2026-09-06: "desktop bubble mode url previews are too large.
/// Regular url previews were shrunk for desktop but bubble mode was not
/// addressed."
///
/// The plain preview card switches at 640 from a hero image above the text to a
/// thumbnail beside it. The bubble card never made that switch, so on a desktop
/// window it kept a full-width image and stood taller than the message it
/// belonged to.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await globals.preferences.init();
  });

  Future<void> pump(
    WidgetTester tester, {
    required double width,
    required bool bubble,
    int? imageWidth = 1200,
    int? imageHeight = 630,
    String? title,
    String? description,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        // The plain card renders through a tiamat Tile, which reads
        // ThemeSettings off the theme unconditionally.
        theme: ThemeData.light().copyWith(extensions: const [ThemeSettings()]),
        home: Scaffold(
          body: UrlPreviewWidget(
            UrlPreviewData(
              Uri.parse('https://example.org/story'),
              title: title ?? 'A headline that runs on for a little while',
              description:
                  description ?? 'Some supporting text under the headline.',
              siteName: 'Example',
              image: MemoryImage(_transparentPng),
              imageWidth: imageWidth,
              imageHeight: imageHeight,
            ),
            messageBubbleMode: bubble,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Size previewImageSize(WidgetTester tester) {
    return tester.getSize(find.byType(PausedAnimatedImage).first);
  }

  /// The bubble card: the rounded container the whole preview is clipped to.
  ///
  /// Scoped to the preview and asserted unique rather than taken as
  /// `find.byType(ClipRRect).first`, which is the card only by accident of
  /// tree order. That finder searches the whole app, and it would silently
  /// start measuring an image clip the day one is added inside the card - the
  /// card-height assertion would then quietly degrade into a second copy of
  /// the image-size assertion. `findsOneWidget` makes that a failure instead.
  double bubbleCardHeight(WidgetTester tester) {
    final card = find.descendant(
      of: find.byType(UrlPreviewWidget),
      matching: find.byType(ClipRRect),
    );
    expect(
      card,
      findsOneWidget,
      reason: 'the measurement has to name one box, and it must be the card',
    );
    return tester.getSize(card).height;
  }

  testWidgets('a bubble preview uses a thumbnail on a desktop window', (
    tester,
  ) async {
    await pump(tester, width: 1400, bubble: true);

    final size = previewImageSize(tester);
    expect(
      size.width,
      lessThan(200),
      reason:
          'the bubble preview is still drawing a full-width hero image on '
          'desktop - the compaction the plain card got was never applied here',
    );
  });

  testWidgets('a bubble preview keeps the hero image on a phone window', (
    tester,
  ) async {
    // The other half. A fix that simply shrank the image everywhere would pass
    // the test above and quietly ruin the layout this one covers, where a wide
    // image is the point.
    await pump(tester, width: 420, bubble: true);

    final size = previewImageSize(tester);
    expect(
      size.width,
      greaterThan(200),
      reason: 'narrow windows keep the full-width image above the text',
    );
  });

  testWidgets('the desktop bubble card is shorter than the hero layout', (
    tester,
  ) async {
    // What the owner actually reported was height, not width. Measured on the
    // card itself so a change that moves the image but keeps the card tall
    // cannot pass - and on the CARD rather than the widget, whose own Align
    // fills the body, so its height is the window's and says nothing.
    await pump(tester, width: 1400, bubble: true);
    final compact = bubbleCardHeight(tester);

    await pump(tester, width: 420, bubble: true);
    final hero = bubbleCardHeight(tester);

    expect(compact, lessThan(hero));
  });

  testWidgets('a desktop thumbnail fills a long preview bubble edge', (
    tester,
  ) async {
    await pump(
      tester,
      width: 1400,
      bubble: true,
      description:
          'This deliberately long description takes the full three preview '
          'lines so the text column is taller than a short thumbnail would be.',
    );

    expect(
      previewImageSize(tester).height,
      closeTo(bubbleCardHeight(tester), 2),
      reason:
          'the desktop thumbnail is the bubble edge, so it must not stop '
          'short when the text column grows',
    );
  });

  testWidgets('a portrait thumbnail in the narrow bubble layout is not clamped '
      'toward square', (tester) async {
    // REVIEW, 2026-09-11 (queue row "URL preview: blank TikTok and
    // Instagram cards..."): messagePreviewImage's aspect-ratio clamp
    // bottomed out at 0.75, so a genuine 9:16 (0.5625) portrait thumbnail -
    // routine for TikTok/Instagram content - rendered forced toward
    // square, cropping most of it under BoxFit.cover. Widened to match
    // imageMobile's existing 0.5 clamp in this same file, which already
    // handles 9:16 correctly. Only half of the aspect-ratio problem:
    // the service still needs to carry oEmbed's thumbnail dimensions
    // through for a real 9:16 preview to reach this code at all, which is
    // SERVER's side of this row.
    await pump(
      tester,
      width: 420,
      bubble: true,
      imageWidth: 9,
      imageHeight: 16,
    );

    final aspectRatioWidget = tester.widget<AspectRatio>(
      find.byType(AspectRatio),
    );

    expect(
      aspectRatioWidget.aspectRatio,
      closeTo(9 / 16, 0.001),
      reason: 'a genuine 9:16 thumbnail must not be clamped toward square',
    );
  });

  testWidgets('the plain preview card is untouched', (tester) async {
    // The plain card already had its desktop treatment; this bundle must not
    // have moved it.
    await pump(tester, width: 1400, bubble: false);

    expect(previewImageSize(tester).width, 176);
  });
}

final _transparentPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
