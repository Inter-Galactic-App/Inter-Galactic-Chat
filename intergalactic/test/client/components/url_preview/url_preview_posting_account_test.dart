import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_utils.dart';

/// The owner's original 2026-09-03 report was that failed previews "default to
/// just an @ symbol". The image half of that was the missing site-icon
/// fallback; this is the text half. Several providers - TikTok's metadata
/// notably - return a bare "@" for `author_name` or `twitter:creator` when the
/// author is unknown, and it rendered beside the site name as a stray glyph.
void main() {
  group('a posting account with no name behind it is absent', () {
    test('a bare @ is dropped', () {
      expect(normalizeUrlPreviewPostingAccount('@'), isNull);
    });

    test('a bare @ with whitespace is dropped', () {
      expect(normalizeUrlPreviewPostingAccount('  @  '), isNull);
    });

    test('"by @" is dropped after the by-prefix is stripped', () {
      expect(normalizeUrlPreviewPostingAccount('by @'), isNull);
    });

    test('punctuation-only values are dropped', () {
      expect(normalizeUrlPreviewPostingAccount('@_'), isNull);
      expect(normalizeUrlPreviewPostingAccount('---'), isNull);
    });

    // An empty `author_name` is what providers return far more often than a
    // bare "@", and it arrives here on the same path. The result has to be
    // NULL rather than an empty string: `sanitizeUrlPreviewDataForUri` drops
    // a preview by testing this against null, so a "" would keep an otherwise
    // empty card alive and render the same stray glyph one layer up.
    test('empty and whitespace-only values are dropped', () {
      expect(normalizeUrlPreviewPostingAccount(''), isNull);
      expect(normalizeUrlPreviewPostingAccount('   '), isNull);
    });
  });

  group('real posting accounts survive', () {
    test('a normal handle is kept', () {
      expect(normalizeUrlPreviewPostingAccount('@someone'), '@someone');
    });

    test('a handle with underscores and digits is kept', () {
      expect(normalizeUrlPreviewPostingAccount('@some_one99'), '@some_one99');
    });

    test('a plain display name is kept', () {
      expect(normalizeUrlPreviewPostingAccount('Jane Doe'), 'Jane Doe');
    });

    test('the by-prefix is still stripped from a real name', () {
      expect(normalizeUrlPreviewPostingAccount('by Jane Doe'), 'Jane Doe');
    });

    // The guard tests for letters/digits in the UNICODE sense. An ASCII-only
    // check would silently delete these, which would be a worse bug than the
    // stray "@" it set out to fix.
    test('a non-Latin handle is kept', () {
      expect(normalizeUrlPreviewPostingAccount('@ユーザー'), '@ユーザー');
      expect(
        normalizeUrlPreviewPostingAccount('@пользователь'),
        '@пользователь',
      );
      expect(normalizeUrlPreviewPostingAccount('@用户'), '@用户');
    });
  });
}
