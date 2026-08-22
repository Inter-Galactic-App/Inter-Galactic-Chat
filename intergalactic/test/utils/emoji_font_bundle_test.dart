import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the emoji font payload.
///
/// tiamat used to declare `NotoColorEmoji.ttf` (23.75 MB) as its own
/// `EmojiFont` family. A font declared by a package is registered under a
/// namespaced family — `packages/tiamat/EmojiFont` — while the app declares its
/// own `EmojiFont` pointing at TwemojiCOLR.otf. Every emoji request in this repo
/// asks for the bare name, so the app's font always won and the package font
/// shipped in every build without ever being drawn. It was removed on
/// 2026-08-07; see `tiamat/assets/font/emoji-font/README.md`.
///
/// That failure mode is invisible: no warning, no log line, nothing on screen —
/// only bundle size. So it needs a test rather than a comment.
void main() {
  // The bundle test below is a plain `test`, and it runs before the
  // `testWidgets` in this file. Without this, `rootBundle.load` reaches
  // `ServicesBinding.instance` with no binding and throws a binding
  // `FlutterError` - which the `isNotNull` assertion happily accepts. The test
  // would then pass whether or not the font is bundled, which is the one thing
  // it exists to detect.
  TestWidgetsFlutterBinding.ensureInitialized();

  const probeKey = ValueKey('emoji-probe');
  const notoAssetKey =
      'packages/tiamat/assets/font/emoji-font/NotoColorEmoji.ttf';

  const sample =
      '\u{1F600}\u{1F389}❤️\u{1F1EC}\u{1F1E7}'
      '\u{1F469}‍\u{1F4BB}\u{1F44D}\u{1F3FD}';

  Future<Uint8List> renderSample(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: probeKey,
              child: Text(
                sample,
                style: TextStyle(
                  fontSize: 48,
                  // Only the family this test registers. The app's real chain
                  // lists the three host emoji families ahead of `EmojiFont`,
                  // and any of them resolving on the host would render the
                  // sample before `EmojiFont` was ever consulted - making the
                  // before and after images identical and the assertion below
                  // vacuous. What is under test is that the app's own family
                  // reaches the renderer, so the host families are not part of
                  // the probe.
                  fontFamilyFallback: ['EmojiFont'],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(probeKey),
    );
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    return bytes!;
  }

  test('no emoji font is bundled under a shadowed package family', () async {
    // If someone re-adds a font to tiamat's pubspec under a family the app also
    // declares, it will ship and never render. Fail loudly instead.
    //
    // Caught explicitly rather than with throwsA: the bundle reports a missing
    // asset as an async error that escapes the matcher and fails the test as an
    // unhandled exception, which reads as a broken test rather than the
    // assertion doing its job.
    Object? failure;
    try {
      await rootBundle.load(notoAssetKey);
    } catch (error) {
      failure = error;
    }

    // Note: a stale intergalactic/build/unit_test_assets bundle can still serve
    // a deleted asset. That staleness makes this test fail spuriously, never
    // pass spuriously, so the safe direction is preserved; clear that directory
    // if this trips unexpectedly.
    expect(
      failure,
      isNotNull,
      reason:
          'a font is bundled at $notoAssetKey. It would be registered as '
          '"packages/tiamat/EmojiFont", which nothing in this repo requests, so '
          'it would add payload without ever being drawn.',
    );
    // Pin WHICH failure. Any thrown object satisfies `isNotNull`, including an
    // uninitialized-binding error, so without this the assertion above cannot
    // distinguish "the asset is absent" from "the probe never ran".
    expect(
      failure,
      isA<FlutterError>().having(
        (error) => error.message,
        'message',
        contains('Unable to load asset'),
      ),
      reason: 'the failure must be the missing asset, not a broken probe',
    );
  });

  testWidgets('the emoji font the app does ship changes what is drawn', (
    tester,
  ) async {
    // Doubles as the control for the test above: it proves this probe can
    // actually see a font take effect, so "the other font is absent" is a
    // meaningful statement about rendering rather than an untested assertion.
    final beforeAnyEmojiFont = await renderSample(tester);
    expect(beforeAnyEmojiFont, isNotEmpty);

    await tester.runAsync(() async {
      final loader = FontLoader('EmojiFont')
        ..addFont(rootBundle.load('assets/font/emoji-font/TwemojiCOLR.otf'));
      await loader.load();
    });

    final withEmojiFont = await renderSample(tester);
    expect(
      withEmojiFont,
      isNot(equals(beforeAnyEmojiFont)),
      reason:
          'registering TwemojiCOLR under the family the fallback chain '
          'names did not change the output, so the shipped emoji font is not '
          'reaching the renderer',
    );
  });
}
