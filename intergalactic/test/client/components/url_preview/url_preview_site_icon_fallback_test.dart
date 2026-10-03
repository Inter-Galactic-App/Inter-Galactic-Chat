import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intergalactic/client/components/url_preview/url_preview_component.dart';
import 'package:intergalactic/client/matrix/components/url_preview/url_preview_fallback_fetcher.dart';

/// When a provider blocks or omits its thumbnail, the preview card rendered as
/// text only. The site-icon fallback gives it the provider's own mark instead.
///
/// The owner's constraint is the important half, and it is why an earlier
/// blanket fallback was removed: the fallback must never TAKE OVER from a real
/// thumbnail. That is enforced structurally rather than by ordering -
/// `shouldUseSiteIconFallback` is false whenever any image is present - and
/// this suite pins exactly that.
///
/// Scope is also load-bearing: the fallback only runs for hosts
/// `shouldPreferDirectFetch` already permits (TikTok, Instagram, Reddit), so it
/// adds no host to the client-side-fetchable set that 90f75c96 closed on
/// 2026-05-20.
void main() {
  final uri = Uri.parse('https://www.instagram.com/p/example');

  group('the site-icon fallback cannot displace a real thumbnail', () {
    test('a preview with an ImageProvider is not eligible', () {
      final data = UrlPreviewData(
        uri,
        siteName: 'Instagram',
        image: const NetworkImage('https://example.test/real.jpg'),
      );

      expect(
        UrlPreviewFallbackFetcher.shouldUseSiteIconFallback(data),
        isFalse,
        reason: 'a real thumbnail must win over the provider mark',
      );
    });

    test('a preview with only an imageUri is not eligible', () {
      final data = UrlPreviewData(
        uri,
        siteName: 'Instagram',
        imageUri: Uri.parse('https://example.test/real.jpg'),
      );

      expect(
        UrlPreviewFallbackFetcher.shouldUseSiteIconFallback(data),
        isFalse,
        reason:
            'imageUri alone still renders after a cache restore, so it counts '
            'as having an image',
      );
    });
  });

  group('the fallback applies exactly when there is nothing to show', () {
    test('a preview with no image at all is eligible', () {
      final data = UrlPreviewData(
        uri,
        siteName: 'Instagram',
        title: 'Blocked thumbnail post',
      );

      expect(UrlPreviewFallbackFetcher.shouldUseSiteIconFallback(data), isTrue);
    });

    test('a null preview is not eligible', () {
      expect(
        UrlPreviewFallbackFetcher.shouldUseSiteIconFallback(null),
        isFalse,
        reason: 'there is no card to decorate',
      );
    });
  });

  group('the fallback is scoped to the existing provider adapters', () {
    test('provider hosts are permitted to be fetched', () {
      for (final permitted in [
        Uri.parse('https://www.tiktok.com/@someone/video/1'),
        Uri.parse('https://www.instagram.com/p/example'),
        Uri.parse('https://www.reddit.com/r/example/comments/1/x'),
      ]) {
        expect(
          UrlPreviewFallbackFetcher.shouldPreferDirectFetch(permitted),
          isTrue,
        );
      }
    });

    test('an arbitrary host is still never fetched', () {
      expect(
        UrlPreviewFallbackFetcher.shouldPreferDirectFetch(
          Uri.parse('https://example.test/some/article'),
        ),
        isFalse,
        reason:
            'the site-icon fallback must not become a reason to fetch an '
            'arbitrary host; that is what 90f75c96 closed',
      );
    });
  });
}
