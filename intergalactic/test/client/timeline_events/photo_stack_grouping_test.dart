import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/timeline_events/photo_stack_grouping.dart';

void main() {
  group('PhotoStackGrouping.looksLikeGeneratedImageBody', () {
    test('treats an empty or whitespace body as generated', () {
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody(null, 'IMG_1.jpeg'),
        isTrue,
      );
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody('   ', 'IMG_1.jpeg'),
        isTrue,
      );
    });

    test('treats a body that repeats the filename as generated', () {
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody(
          'IMG_1.jpeg',
          'IMG_1.jpeg',
        ),
        isTrue,
      );
    });

    test('treats any image filename as generated', () {
      for (final body in [
        'photo.PNG',
        'holiday.jpg',
        'clip.webp',
        'shot.heic',
      ]) {
        expect(
          PhotoStackGrouping.looksLikeGeneratedImageBody(body, 'IMG_1.jpeg'),
          isTrue,
          reason: '$body should look like a generated body',
        );
      }
    });

    test('treats a real caption as a message of its own', () {
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody(
          'look at this view',
          'IMG_1.jpeg',
        ),
        isFalse,
      );
    });

    test('keeps a real caption when the attachment has no name', () {
      // Regression: a blank attachment name used to short-circuit to "generated"
      // regardless of the body, so a captioned photo was folded into a stack and
      // its notification suppressed entirely.
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody('look at this view', ''),
        isFalse,
      );
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody(
          'look at this view',
          '   ',
        ),
        isFalse,
      );
    });

    test('still treats a filename-like body with no attachment name as '
        'generated', () {
      expect(
        PhotoStackGrouping.looksLikeGeneratedImageBody('IMG_1.jpeg', ''),
        isTrue,
      );
    });
  });

  group('PhotoStackGrouping.singleImageAttachment', () {
    test('returns null for a non-message event', () {
      expect(PhotoStackGrouping.singleImageAttachment(null), isNull);
    });
  });
}
